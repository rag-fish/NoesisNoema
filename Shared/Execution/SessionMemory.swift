//
//  SessionMemory.swift
//  NoesisNoema
//
//  ADR-0009 (Session Memory — Multi-Turn Conversation Context):
//  pure helpers that map the visible chat transcript (`[QAPair]`) onto the
//  bounded `[ConversationTurn]` carried on `NoemaRequest`.
//
//  Subordinate to ADR-0000 §4 ("No hidden conversation memory"): this helper
//  derives history strictly from the user-visible transcript supplied by the
//  caller. There is no hidden store and no I/O — it is a pure value
//  transformation, which is why it is testable in isolation.
//
//  License: MIT License
//

import Foundation

/// ADR-0009 session-memory cap policy.
///
/// Lives in `Shared/Execution` next to `NoemaRequest` so the executor and the
/// UI agree on the same caps, but the *application* of those caps is the
/// caller's job: the UI invokes `SessionMemory.history(from:)` when
/// constructing the request. The executor never re-derives history.
enum SessionMemory {

    /// Recency window — turns older than this are excluded
    /// (`design/execution-flow.md` §4).
    static let defaultWindow: TimeInterval = 45 * 60

    /// Maximum turns admitted into the prompt, regardless of how many fit
    /// inside the window (ADR-0009 Decision 2 — 3B on-device budget).
    static let defaultMaxTurns: Int = 3

    /// Map a visible transcript to the session-memory turns carried on
    /// `NoemaRequest.history`.
    ///
    /// Caps are applied in this order:
    /// 1. Drop turns whose `date` is missing — without a timestamp we cannot
    ///    prove they fall inside the window, and admitting them silently
    ///    would violate the recency contract.
    /// 2. Drop turns older than `now - window`.
    /// 3. Keep at most `maxTurns` of the most recent surviving turns,
    ///    returned in chronological (oldest → newest) order so the prompt
    ///    reads as a conversation.
    ///
    /// Empty input ⇒ empty output ⇒ single-turn behaviour
    /// (ADR-0009 Decision 2).
    static func history(
        from qaHistory: [QAPair],
        now: Date = Date(),
        window: TimeInterval = SessionMemory.defaultWindow,
        maxTurns: Int = SessionMemory.defaultMaxTurns
    ) -> [ConversationTurn] {
        guard maxTurns > 0, window > 0 else { return [] }

        let cutoff = now.addingTimeInterval(-window)
        let inWindow = qaHistory.compactMap { qa -> (QAPair, Date)? in
            guard let date = qa.date, date >= cutoff, date <= now else {
                return nil
            }
            return (qa, date)
        }

        // `qaHistory` is appended-to in chronological order, so suffix() picks
        // the most recent N in-window turns while preserving that order.
        let recent = Array(inWindow.suffix(maxTurns))
        return recent.map { (qa, date) in
            ConversationTurn(
                question: qa.question,
                answer: qa.answer,
                date: date
            )
        }
    }
}
