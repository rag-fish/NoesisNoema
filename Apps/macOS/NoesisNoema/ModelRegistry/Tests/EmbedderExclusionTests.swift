#if !BRIDGE_TEST
// Project: NoesisNoema
// File: EmbedderExclusionTests.swift
// Description: Unit smoke for ModelRegistry.looksLikeEmbedder — the registry-scan
//   guard that keeps embedding-only GGUFs (nomic-embed-text, BGE, E5, Jina, …) out
//   of the LLM picker. Regression cover for the UAT blocker where the Spinoza chat
//   returned identical [unusedN] reserved-vocab garbage to every question because
//   the embedder was selected as the chat LLM.
// License: MIT License
//
// The NoesisNoemaTests Xcode target is unwired (see auto-memory), so — like
// TestRunner.swift — this is a self-contained, dependency-free checker runnable
// from a scratch call site or the debugger. `runAllTests()` returns true iff every
// case passes; it does not depend on XCTest.

import Foundation

/// Pure unit cover for `ModelRegistry.looksLikeEmbedder`.
enum EmbedderExclusionTests {

    /// One table row: (fileName, architecture) → expected `looksLikeEmbedder`.
    private struct Case {
        let fileName: String
        let architecture: String
        let expected: Bool
    }

    private static let cases: [Case] = [
        // Embedders — must be TRUE.
        Case(fileName: "nomic-embed-text-v1.5.Q5_K_M.gguf", architecture: "nomic-bert", expected: true),
        Case(fileName: "bge-large-en-v1.5.gguf",            architecture: "bert",       expected: true),
        Case(fileName: "jina-embeddings-v2.gguf",           architecture: "jina-bert",  expected: true),
        // Architecture-only signal (file name gives nothing away).
        Case(fileName: "mystery-model-q4.gguf",             architecture: "mpnet-bert", expected: true),
        // File-name-only signal (architecture lies / is unknown).
        Case(fileName: "e5-large-v2.embed.gguf",            architecture: "unknown",    expected: true),

        // Generators — must be FALSE.
        Case(fileName: "Llama-3.2-3B-Instruct-Q4_K_M.gguf", architecture: "llama",      expected: false),
        Case(fileName: "Jan-v1-4B-Q4_K_M.gguf",             architecture: "qwen2",      expected: false),
        Case(fileName: "gpt-oss-20b-F16.gguf",              architecture: "gptoss",     expected: false),
        // Edge: empty inputs default to generator (do not over-block).
        Case(fileName: "",                                  architecture: "",           expected: false),
        // Edge: "bert" only as a substring of the architecture is the intended trigger,
        // but a generator whose name merely contains "ember" must NOT match "embed".
        Case(fileName: "ember-7b.gguf",                     architecture: "llama",      expected: false),
    ]

    /// Run every case, print a result table, return true iff all pass.
    @discardableResult
    static func runAllTests() -> Bool {
        print("🧪 ModelRegistry.looksLikeEmbedder")
        print(String(repeating: "=", count: 64))
        print("result  actual  expected  [fileName | architecture]")

        var allPassed = true
        for c in cases {
            let metadata = GGUFMetadata(architecture: c.architecture)
            let actual = ModelRegistry.looksLikeEmbedder(fileName: c.fileName, metadata: metadata)
            let pass = actual == c.expected
            allPassed = allPassed && pass
            let mark = pass ? "✅" : "❌"
            let shown = c.fileName.isEmpty ? "(empty)" : c.fileName
            print("\(mark) \(actual)  exp=\(c.expected)  [\(shown) | \(c.architecture)]")
        }

        print(String(repeating: "-", count: 64))
        print(allPassed
              ? "✅ looksLikeEmbedder: all \(cases.count) cases passed"
              : "❌ looksLikeEmbedder: FAILURES present")
        return allPassed
    }
}
#endif
