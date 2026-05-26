// NoesisNoema - Hybrid Routing Runtime
// Session Memory Tests (ADR-0009)
// Created: 2026-05-26
// License: MIT License
//
// Source-level tests for ADR-0009 (Session Memory). The test target is not
// wired to a run scheme in this repo, so these compile-checked tests serve as
// executable documentation of the invariants — they will run wherever the
// target is wired in (e.g. via Xcode's test scheme).

import XCTest
@testable import NoesisNoema

final class SessionMemoryTests: XCTestCase {

    // MARK: - SessionMemory.history (ADR-0009 Decision 2)

    /// 5 turns spanning >45 min ⇒ only the ≤3 most-recent **in-window** turns
    /// survive, in chronological order.
    func test_history_appliesBothCaps_3turnsAnd45MinWindow() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        // Build five turns: t-90m, t-60m (both outside the 45-min window),
        // then t-20m, t-10m, t-2m (all inside) — the helper should drop the
        // first two and return the three recent in-window turns in order.
        let qaPairs: [QAPair] = [
            QAPair(question: "Q-90", answer: "A-90", date: now.addingTimeInterval(-90 * 60)),
            QAPair(question: "Q-60", answer: "A-60", date: now.addingTimeInterval(-60 * 60)),
            QAPair(question: "Q-20", answer: "A-20", date: now.addingTimeInterval(-20 * 60)),
            QAPair(question: "Q-10", answer: "A-10", date: now.addingTimeInterval(-10 * 60)),
            QAPair(question: "Q-2",  answer: "A-2",  date: now.addingTimeInterval(-2  * 60)),
        ]

        let history = SessionMemory.history(from: qaPairs, now: now)

        XCTAssertEqual(history.count, 3, "must apply both the 45-min window and the 3-turn cap")
        XCTAssertEqual(history.map(\.question), ["Q-20", "Q-10", "Q-2"],
                       "must return the three most recent in-window turns, oldest→newest")
    }

    /// >3 turns all inside the 45-min window ⇒ only the 3 most recent survive.
    func test_history_capsToThreeWhenAllInWindow() {
        let now = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let qaPairs: [QAPair] = (1...5).map { i in
            QAPair(
                question: "Q\(i)",
                answer: "A\(i)",
                // 30m, 25m, 20m, 15m, 10m ago — all inside the 45m window.
                date: now.addingTimeInterval(TimeInterval(-(35 - i * 5) * 60))
            )
        }

        let history = SessionMemory.history(from: qaPairs, now: now)

        XCTAssertEqual(history.map(\.question), ["Q3", "Q4", "Q5"])
    }

    /// Empty transcript ⇒ empty history (ADR-0009 Decision 2 — single-turn).
    func test_history_emptyInput_returnsEmpty() {
        XCTAssertEqual(SessionMemory.history(from: []), [])
    }

    /// Turns missing a `date` are excluded — without a timestamp we cannot
    /// prove they are in-window. Conservative-by-design.
    func test_history_excludesUndatedTurns() {
        let now = Date(timeIntervalSinceReferenceDate: 3_000_000)
        let qaPairs: [QAPair] = [
            QAPair(question: "no-date", answer: "x", date: nil),
            QAPair(question: "dated", answer: "y", date: now.addingTimeInterval(-5 * 60)),
        ]

        let history = SessionMemory.history(from: qaPairs, now: now)

        XCTAssertEqual(history.map(\.question), ["dated"])
    }

    // MARK: - NoemaRequest contract (ADR-0006-safe additive default)

    /// Existing call sites that omit `history` must still compile and yield
    /// an empty history field — ADR-0009 Decision 2 (empty ⇒ single-turn).
    func test_noemaRequest_historyDefaultsToEmpty() {
        let r1 = NoemaRequest(query: "q")
        let r2 = NoemaRequest(query: "q", sessionId: UUID())
        XCTAssertEqual(r1.history, [])
        XCTAssertEqual(r2.history, [])
    }

    func test_noemaRequest_carriesHistoryWhenProvided() {
        let turn = ConversationTurn(question: "prior?", answer: "yes.", date: Date())
        let req = NoemaRequest(query: "follow-up?", history: [turn])
        XCTAssertEqual(req.history, [turn])
    }

    // MARK: - buildPrompt (ChatML rendering, no template change)

    /// Empty history ⇒ prompt is identical to the prior single-turn build
    /// (no extra `<|im_start|>user` / `<|im_start|>assistant` turns inserted
    /// before the current question).
    func test_buildPrompt_emptyHistory_unchangedSingleTurnShape() {
        let prompt = buildPrompt(
            question: "What is RAG?",
            context: "Some context.",
            history: []
        )
        // Exactly one user turn and one trailing assistant opener.
        XCTAssertEqual(occurrences(of: "<|im_start|>user", in: prompt), 1)
        XCTAssertEqual(occurrences(of: "<|im_start|>assistant", in: prompt), 1)
        XCTAssertTrue(prompt.contains("Question: What is RAG?"))
        XCTAssertTrue(prompt.contains("Context:\nSome context."))
    }

    /// Prior turns render as ChatML user/assistant pairs BEFORE the current
    /// question. The current question carries the retrieved Context;
    /// historical turns do not.
    func test_buildPrompt_rendersPriorTurnsBeforeCurrent() {
        let now = Date()
        let history = [
            ConversationTurn(question: "Who fought in WW2?", answer: "Allies vs Axis.", date: now.addingTimeInterval(-600)),
            ConversationTurn(question: "When did it end?", answer: "1945.", date: now.addingTimeInterval(-60)),
        ]
        let prompt = buildPrompt(
            question: "Continue describing the war",
            context: "Battle of the Bulge began in December 1944.",
            history: history
        )

        // 2 prior user turns + 1 current = 3 user turns; 2 prior assistant
        // turns + 1 trailing assistant opener = 3 assistant markers.
        XCTAssertEqual(occurrences(of: "<|im_start|>user", in: prompt), 3)
        XCTAssertEqual(occurrences(of: "<|im_start|>assistant", in: prompt), 3)

        // Historical turns appear verbatim, BEFORE the current question.
        let currentRange = prompt.range(of: "Continue describing the war")
        XCTAssertNotNil(currentRange)
        if let currentRange = currentRange {
            let head = String(prompt[..<currentRange.lowerBound])
            XCTAssertTrue(head.contains("Who fought in WW2?"))
            XCTAssertTrue(head.contains("Allies vs Axis."))
            XCTAssertTrue(head.contains("When did it end?"))
            XCTAssertTrue(head.contains("1945."))
            // Context attaches to the CURRENT user turn only — historical
            // turns must not carry retrieved chunks.
            XCTAssertFalse(head.contains("Battle of the Bulge"))
        }

        // Single system prompt at the top.
        XCTAssertEqual(occurrences(of: "<|im_start|>system", in: prompt), 1)
    }

    // MARK: - Helpers

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<haystack.endIndex
        }
        return count
    }
}
