//
//  ContextBudget.swift
//  NoesisNoema
//
//  Pure token-budget allocator for the generation prompt. This is the decision
//  seam — like `LlamaContext.kvBudgetExceeds` — extracted so it is unit-testable
//  with plain integer token counts and no model GGUF.
//
//  The prompt budget (= n_ctx − n_len) is allocated in strict PRIORITY order:
//    1. RESERVE generation: `n_len` tokens are never available to the prompt
//       (protects the PR #111 generation reserve — the KV cache must hold the
//       prompt PLUS every token we intend to generate).
//    2. INCLUDE the user question: always whole (mandatory skeleton).
//    3. INCLUDE RAG context: trimmed only if it would not otherwise fit; RAG
//       keeps priority over chat history.
//    4. FILL chat history: newest-first until the budget is hit, dropping the
//       oldest turns that no longer fit.
//
//  Only if the mandatory skeleton (system + question + answer header) plus the
//  generation reserve cannot fit at all does the caller fall back to an error —
//  which cannot happen at n_ctx = 4096 for any real question.
//
//  License: MIT License
//

import Foundation

/// The outcome of allocating the prompt budget. All values are token counts.
struct ContextBudgetPlan: Equatable {
    /// Tokens available to the whole prompt (= nCtx − nLen).
    let promptBudget: Int
    /// Generation reserve held back from the prompt (= nLen). PR #111 guard.
    let reserve: Int
    /// Mandatory skeleton cost (system + question turn + assistant header).
    let mandatoryTokens: Int
    /// Tokens RAG context is requesting (full, untrimmed).
    let ragRequestedTokens: Int
    /// Tokens RAG context is permitted to occupy (≤ requested). When this is
    /// less than requested, the caller must trim the context to fit.
    let ragGrantedTokens: Int
    /// Number of (newest) history turns kept.
    let keptHistoryCount: Int
    /// Number of (oldest) history turns dropped for budget.
    let droppedHistoryCount: Int
    /// False ⇒ even question + generation reserve cannot fit ⇒ caller errors.
    let mandatoryFits: Bool

    /// True when RAG context had to be shortened to fit the budget.
    var ragTrimmed: Bool { ragGrantedTokens < ragRequestedTokens }

    /// Total prompt tokens this plan implies (mandatory + granted RAG + kept
    /// history). Always ≤ promptBudget by construction when `mandatoryFits`.
    var plannedPromptTokens: Int {
        mandatoryTokens + ragGrantedTokens + keptHistoryTokens
    }

    /// Sum of the kept history-turn token counts (filled in by `allocate`).
    let keptHistoryTokens: Int
}

enum ContextBudget {

    /// Allocate the prompt budget across RAG context and chat history.
    ///
    /// - Parameters:
    ///   - nCtx: effective llama-context size (KV cache capacity).
    ///   - nLen: generation reserve (tokens we intend to generate).
    ///   - mandatoryTokens: cost of the always-present skeleton (system prompt +
    ///     current question turn + assistant header), question included whole.
    ///   - ragTokens: full token cost of the retrieved RAG context insertion.
    ///   - historyTurnTokensNewestFirst: per-turn token costs, NEWEST FIRST.
    /// - Returns: a `ContextBudgetPlan` describing what fits.
    static func allocate(
        nCtx: Int,
        nLen: Int,
        mandatoryTokens: Int,
        ragTokens: Int,
        historyTurnTokensNewestFirst: [Int]
    ) -> ContextBudgetPlan {
        let promptBudget = max(0, nCtx - nLen)

        // (2) Question is mandatory. If even it + the reserve cannot fit, the
        // caller must error — RAG/history trimming cannot rescue this.
        let mandatoryFits = mandatoryTokens <= promptBudget

        // Remaining budget after the mandatory skeleton.
        let afterMandatory = max(0, promptBudget - mandatoryTokens)

        // (3) RAG has priority over history; grant up to what remains.
        let ragGranted = min(max(0, ragTokens), afterMandatory)
        var remaining = afterMandatory - ragGranted

        // (4) History newest-first; keep while it fits, drop the rest (oldest).
        var kept = 0
        var keptTokens = 0
        for turnTokens in historyTurnTokensNewestFirst {
            if turnTokens <= remaining {
                remaining -= turnTokens
                keptTokens += turnTokens
                kept += 1
            } else {
                break
            }
        }

        return ContextBudgetPlan(
            promptBudget: promptBudget,
            reserve: nLen,
            mandatoryTokens: mandatoryTokens,
            ragRequestedTokens: max(0, ragTokens),
            ragGrantedTokens: ragGranted,
            keptHistoryCount: kept,
            droppedHistoryCount: historyTurnTokensNewestFirst.count - kept,
            mandatoryFits: mandatoryFits,
            keptHistoryTokens: keptTokens
        )
    }
}
