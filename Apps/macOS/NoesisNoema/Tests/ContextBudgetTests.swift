#if DEBUG
// Project: NoesisNoema
// File: ContextBudgetTests.swift
// Description: Pure unit cover for the token-budget allocator
//   (`ContextBudget.allocate`), the decision seam behind the generation
//   token-budget manager. Mirrors the device repro that motivated raising
//   n_ctx to 4096: a multi-turn Spinoza conversation whose accumulating
//   history overflowed the 1024 KV cache and BAILed completion_init. The
//   allocator now trims history (then RAG) to fit instead of rejecting, and at
//   n_ctx=4096 the measured prompts (~1.4–1.8k tokens) fit with zero trimming.
//
//   Like LibLlamaCompletionBailTests / EmbedderExclusionTests, this is a
//   self-contained, dependency-free checker (the NoesisNoemaTests target is
//   unwired — see auto-memory). `runAllTests()` returns true iff every case
//   passes; it needs no model GGUF because the decision is in the arithmetic.
// License: MIT License

import Foundation

enum ContextBudgetTests {

    // Llama-3.2-3B on iOS uses n_len=256 (auto/balanced). The device harness
    // measured real Spinoza prompts at ~1.4–1.8k tokens total.
    private static let nLen = 256
    private static let nCtx4096 = 4096
    private static let nCtx1024 = 1024

    @discardableResult
    static func runAllTests() -> Bool {
        print("🧪 ContextBudget.allocate")
        print(String(repeating: "=", count: 64))

        var all = true
        all = checkBasicFit()                    && all
        all = checkHistoryTrimOldestFirst()      && all
        all = checkRagPriorityOverHistory()      && all
        all = checkPathologicalRagTooBig()       && all
        all = checkReserveNeverConsumed()        && all
        all = checkMandatoryCannotFitErrors()    && all
        all = checkSpinoza5QRegressionNoBail()   && all

        print(String(repeating: "-", count: 64))
        print(all
              ? "✅ ContextBudget: all checks passed"
              : "❌ ContextBudget: FAILURES present")
        return all
    }

    // MARK: - Helpers

    private static func expect(_ cond: Bool, _ label: String) -> Bool {
        print("\(cond ? "✅" : "❌") \(label)")
        return cond
    }

    /// Invariant that protects the PR #111 generation reserve: the planned
    /// prompt must never eat into n_len. Holds whenever the question fits.
    private static func reserveIntact(_ plan: ContextBudgetPlan, nCtx: Int, nLen: Int) -> Bool {
        return plan.plannedPromptTokens <= plan.promptBudget
            && (nCtx - plan.plannedPromptTokens) >= nLen
    }

    // MARK: - Test 1: basic allocation, everything fits

    private static func checkBasicFit() -> Bool {
        // 3 history turns, RAG, all comfortably within 4096.
        let plan = ContextBudget.allocate(
            nCtx: nCtx4096, nLen: nLen,
            mandatoryTokens: 200, ragTokens: 600,
            historyTurnTokensNewestFirst: [300, 300, 300]
        )
        var ok = true
        ok = expect(plan.mandatoryFits, "basic: question fits") && ok
        ok = expect(plan.ragGrantedTokens == 600 && !plan.ragTrimmed, "basic: full RAG granted") && ok
        ok = expect(plan.keptHistoryCount == 3 && plan.droppedHistoryCount == 0, "basic: all 3 history turns kept") && ok
        ok = expect(reserveIntact(plan, nCtx: nCtx4096, nLen: nLen), "basic: n_len reserve intact") && ok
        return ok
    }

    // MARK: - Test 2: history trimmed oldest-first when tight

    private static func checkHistoryTrimOldestFirst() -> Bool {
        // budget=3840, mandatory=200, rag=3000 ⇒ 640 left for history.
        // 4 turns of 300 ⇒ only the 2 NEWEST fit (600 ≤ 640); 2 oldest dropped.
        let plan = ContextBudget.allocate(
            nCtx: nCtx4096, nLen: nLen,
            mandatoryTokens: 200, ragTokens: 3000,
            historyTurnTokensNewestFirst: [300, 300, 300, 300]
        )
        var ok = true
        ok = expect(plan.keptHistoryCount == 2, "trim: 2 newest turns kept") && ok
        ok = expect(plan.droppedHistoryCount == 2, "trim: 2 oldest turns dropped") && ok
        ok = expect(!plan.ragTrimmed, "trim: RAG kept whole (history yields first)") && ok
        ok = expect(reserveIntact(plan, nCtx: nCtx4096, nLen: nLen), "trim: n_len reserve intact") && ok
        return ok
    }

    // MARK: - Test 3: RAG keeps priority over history

    private static func checkRagPriorityOverHistory() -> Bool {
        // budget=3840, mandatory=200, rag=3500 ⇒ 140 left ⇒ no history fits,
        // but RAG is granted in full.
        let plan = ContextBudget.allocate(
            nCtx: nCtx4096, nLen: nLen,
            mandatoryTokens: 200, ragTokens: 3500,
            historyTurnTokensNewestFirst: [200, 200]
        )
        var ok = true
        ok = expect(plan.ragGrantedTokens == 3500 && !plan.ragTrimmed, "priority: RAG kept whole") && ok
        ok = expect(plan.keptHistoryCount == 0 && plan.droppedHistoryCount == 2, "priority: history dropped before RAG") && ok
        ok = expect(reserveIntact(plan, nCtx: nCtx4096, nLen: nLen), "priority: n_len reserve intact") && ok
        return ok
    }

    // MARK: - Test 4: pathological RAG too big ⇒ RAG degrades, question fits

    private static func checkPathologicalRagTooBig() -> Bool {
        // RAG alone dwarfs the budget. It must be trimmed to what's left after
        // the mandatory skeleton; question + generation reserve still fit.
        let plan = ContextBudget.allocate(
            nCtx: nCtx4096, nLen: nLen,
            mandatoryTokens: 200, ragTokens: 99_999,
            historyTurnTokensNewestFirst: [300, 300, 300]
        )
        var ok = true
        ok = expect(plan.mandatoryFits, "pathological: question + reserve still fit") && ok
        ok = expect(plan.ragTrimmed && plan.ragGrantedTokens == 3640, "pathological: RAG trimmed to remaining budget") && ok
        ok = expect(plan.keptHistoryCount == 0, "pathological: no room for history") && ok
        ok = expect(reserveIntact(plan, nCtx: nCtx4096, nLen: nLen), "pathological: n_len reserve intact") && ok
        return ok
    }

    // MARK: - Test 5: reserve never consumed across a sweep (PR #111 guard)

    private static func checkReserveNeverConsumed() -> Bool {
        var ok = true
        let mandatories = [120, 200, 700]
        let rags = [0, 600, 3000, 50_000]
        let histories: [[Int]] = [[], [320], [320, 320, 320], [400, 400, 400, 400, 400]]
        for m in mandatories {
            for r in rags {
                for h in histories {
                    let plan = ContextBudget.allocate(
                        nCtx: nCtx4096, nLen: nLen,
                        mandatoryTokens: m, ragTokens: r,
                        historyTurnTokensNewestFirst: h
                    )
                    // When the question fits, the reserve must always survive.
                    if plan.mandatoryFits && !reserveIntact(plan, nCtx: nCtx4096, nLen: nLen) {
                        ok = expect(false, "reserve: VIOLATED at m=\(m) r=\(r) h=\(h)") && ok
                    }
                }
            }
        }
        ok = expect(ok, "reserve: n_len never consumed across \(mandatories.count * rags.count * histories.count) combos") && ok
        return ok
    }

    // MARK: - Test 6: only true error path — question itself can't fit

    private static func checkMandatoryCannotFitErrors() -> Bool {
        // n_ctx=1024, budget=768, but a 900-token mandatory skeleton ⇒ cannot
        // fit even with empty RAG/history ⇒ caller must fall back to an error.
        let plan = ContextBudget.allocate(
            nCtx: nCtx1024, nLen: nLen,
            mandatoryTokens: 900, ragTokens: 0,
            historyTurnTokensNewestFirst: []
        )
        return expect(!plan.mandatoryFits, "error-path: oversized question reported as cannot-fit")
    }

    // MARK: - Test 7: device regression — 5 sequential Spinoza Qs, BAIL=0 @4096

    private static func checkSpinoza5QRegressionNoBail() -> Bool {
        // Measured shapes from the device harness (PR #116): mandatory skeleton
        // ~120tk, RAG (3 chunks) ~600tk, each prior turn (Q ~40 + A ~256) ~320tk.
        // History accumulates under the 3-turn cap.
        let mandatory = 120
        let rag = 600
        let turn = 320
        // history-turn-counts (newest-first) at the START of each question:
        let perQuestionHistory: [[Int]] = [
            [],                       // Q1
            [turn],                   // Q2
            [turn, turn],             // Q3
            [turn, turn, turn],       // Q4 (3-turn cap)
            [turn, turn, turn],       // Q5 (3-turn cap)
        ]

        var ok = true

        // (a) At 4096: every question fits with ZERO trimming ⇒ BAIL count 0.
        var bail4096 = 0
        for (i, h) in perQuestionHistory.enumerated() {
            let plan = ContextBudget.allocate(
                nCtx: nCtx4096, nLen: nLen,
                mandatoryTokens: mandatory, ragTokens: rag,
                historyTurnTokensNewestFirst: h
            )
            let fitsClean = plan.mandatoryFits
                && !plan.ragTrimmed
                && plan.droppedHistoryCount == 0
                && reserveIntact(plan, nCtx: nCtx4096, nLen: nLen)
            if !plan.mandatoryFits { bail4096 += 1 }
            ok = expect(fitsClean, "regression@4096: Q\(i + 1) fits clean (prompt=\(plan.plannedPromptTokens)tk ≤ \(plan.promptBudget))") && ok
        }
        ok = expect(bail4096 == 0, "regression@4096: BAIL count == 0 (was 1/5 at n_ctx=1024)") && ok

        // (b) At the OLD 1024 default, the same Q4/Q5 would have BAILed under the
        // pre-fix reject behavior (1680tk prompt > 768 budget). The budget
        // manager instead keeps the question answerable (mandatory still fits)
        // by dropping history / trimming RAG — graceful degradation, not a BAIL.
        var degraded = 0
        for h in perQuestionHistory {
            let plan = ContextBudget.allocate(
                nCtx: nCtx1024, nLen: nLen,
                mandatoryTokens: mandatory, ragTokens: rag,
                historyTurnTokensNewestFirst: h
            )
            ok = expect(plan.mandatoryFits, "regression@1024: question still answerable (no hard reject)") && ok
            ok = expect(reserveIntact(plan, nCtx: nCtx1024, nLen: nLen), "regression@1024: n_len reserve intact") && ok
            if plan.ragTrimmed || plan.droppedHistoryCount > 0 { degraded += 1 }
        }
        ok = expect(degraded > 0, "regression@1024: degraded (trim) rather than BAILed on tight turns") && ok

        return ok
    }
}
#endif
