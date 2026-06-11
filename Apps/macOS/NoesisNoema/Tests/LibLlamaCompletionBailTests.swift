#if DEBUG
// Project: NoesisNoema
// File: LibLlamaCompletionBailTests.swift
// Description: Unit smoke for the KV-cache-overflow bail-out (hotfix #4, Fix B1).
//   Regression cover for the UAT blocker where Spinoza chat Q5 hung the runtime:
//   the rendered ChatML prompt (system + 3 prior Q/A turns + ~2,500-token RAG
//   context) reached ~12–13k tokens, far past macOS n_ctx=4096. completion_init
//   only PRINTED the overflow and decoded anyway; llama.cpp then capped its KV
//   cache at n_ctx-1 (X=4095) while the Swift loop ran n_cur away into the
//   hundreds of thousands (Y=910640+), emitting "inconsistent sequence positions"
//   on every one of ~910k iterations and never terminating.
//
//   `LlamaContext.kvBudgetExceeds(nPrompt:nLen:nCtx:)` is the pure decision seam
//   completion_init now consults BEFORE decode (returning false + setting
//   last_error + is_done on overflow). Exercising it directly needs no model
//   GGUF — the failure is in the arithmetic, not the C bindings.
// License: MIT License
//
// The NoesisNoemaTests Xcode target is unwired (see auto-memory), so — like
// EmbedderExclusionTests / TestRunner — this is a self-contained, dependency-free
// checker runnable from a scratch call site or the debugger. `runAllTests()`
// returns true iff every case passes; it does not depend on XCTest.

import Foundation

/// Pure unit cover for `LlamaContext.kvBudgetExceeds`.
enum LibLlamaCompletionBailTests {

    /// One row: (nPrompt, nLen, nCtx) → expected `kvBudgetExceeds`.
    private struct Case {
        let nPrompt: Int
        let nLen: Int
        let nCtx: Int
        let expected: Bool
        let note: String
    }

    private static let cases: [Case] = [
        // The UAT Q5 shape: ~13k-token prompt + 512 generate, macOS n_ctx=4096.
        // MUST overflow (true) so completion_init bails instead of looping.
        Case(nPrompt: 13_000, nLen: 512, nCtx: 4096, expected: true,  note: "Q5 over-budget multi-turn"),
        // A healthy Q1-style single-turn prompt comfortably fits.
        Case(nPrompt: 1_200,  nLen: 512, nCtx: 4096, expected: false, note: "Q1 single-turn fits"),
        // Exact-fit boundary: prompt + n_len == n_ctx is NOT an overflow.
        Case(nPrompt: 3_584,  nLen: 512, nCtx: 4096, expected: false, note: "exact fit (== n_ctx)"),
        // One token over the boundary IS an overflow.
        Case(nPrompt: 3_585,  nLen: 512, nCtx: 4096, expected: true,  note: "one token over"),
        // iOS lightweight context (n_ctx=1024) is far easier to overflow.
        Case(nPrompt: 800,    nLen: 256, nCtx: 1024, expected: true,  note: "iOS n_ctx=1024 overflow"),
        Case(nPrompt: 700,    nLen: 256, nCtx: 1024, expected: false, note: "iOS n_ctx=1024 fits"),
        // Degenerate: empty prompt, generate within budget.
        Case(nPrompt: 0,      nLen: 512, nCtx: 4096, expected: false, note: "empty prompt fits"),
    ]

    /// Run every case, print a result table, return true iff all pass.
    @discardableResult
    static func runAllTests() -> Bool {
        print("🧪 LlamaContext.kvBudgetExceeds")
        print(String(repeating: "=", count: 64))
        print("result  actual  expected  [nPrompt + nLen vs nCtx | note]")

        var allPassed = true
        for c in cases {
            let actual = LlamaContext.kvBudgetExceeds(nPrompt: c.nPrompt, nLen: c.nLen, nCtx: c.nCtx)
            let pass = actual == c.expected
            allPassed = allPassed && pass
            let mark = pass ? "✅" : "❌"
            print("\(mark) \(actual)  exp=\(c.expected)  [\(c.nPrompt) + \(c.nLen) vs \(c.nCtx) | \(c.note)]")
        }

        print(String(repeating: "-", count: 64))
        print(allPassed
              ? "✅ kvBudgetExceeds: all \(cases.count) cases passed"
              : "❌ kvBudgetExceeds: FAILURES present")
        return allPassed
    }
}
#endif
