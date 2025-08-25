// filepath: LlamaBridgeTest/TestRunnerShim.swift
// Description: Minimal shim TestRunner for LlamaBridgeTest builds (BRIDGE_TEST) to validate retrieval components without XCTest.
// License: MIT

#if BRIDGE_TEST
import Foundation

/// Simple test runner that can be executed from CLI (limited subset for BRIDGE_TEST builds)
class TestRunner {
    /// Run all shim tests and return exit code (0 = pass, 1 = fail)
    static func runAllTests() async -> Int {
        print("🧪 LlamaBridgeTest Shim Test Suite")
        print(String(repeating: "=", count: 50))
        var ok = true

        print("\n🔬 Test: LocalRetriever Duplicate Suppression + Trace")
        ok = testLocalRetrieverDuplicateSuppressionAndTrace() && ok

        // Note: ParamBandit tests are covered in the app test runner and skipped in BRIDGE_TEST.

        print("\n" + String(repeating: "=", count: 50))
        if ok { print("✅ All shim tests passed!"); return 0 }
        else { print("❌ Some shim tests failed!"); return 1 }
    }

    /// Validate that LocalRetriever suppresses duplicate contents and returns some results
    private static func testLocalRetrieverDuplicateSuppressionAndTrace() -> Bool {
        // Seed demo corpus with duplicates
        VectorStore.shared.clear()
        let docs = [
            "Swift is a powerful and intuitive programming language for iOS and macOS.",
            "Swift is a powerful and intuitive programming language for iOS and macOS.", // duplicate
            "BM25 is a ranking function used in search engines.",
            "Embeddings map text to vectors in a semantic space.",
            "MMR balances relevance and diversity for reranking.",
            "Apple's M2 chips have unified memory."
        ]
        VectorStore.shared.addTexts(docs, deduplicate: false)

        let retriever = LocalRetriever(store: .shared)
        let results = retriever.retrieve(query: "swift programming", k: 4, lambda: 0.7, trace: true)
        guard !results.isEmpty else {
            print("❌ Retriever returned no results")
            return false
        }
        // Ensure duplicate suppression by content
        let contents = results.map { $0.content }
        let uniqueCount = Set(contents).count
        guard uniqueCount == contents.count else {
            print("❌ Duplicate contents present in results: \(contents)")
            return false
        }
        print("✅ Duplicate suppression OK (results=\(results.count))")
        return true
    }
}
#endif
