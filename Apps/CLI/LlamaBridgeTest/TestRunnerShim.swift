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

        print("\n🔬 Test: SemanticAnswerCache 👍 caches and retrieves similar query")
        ok = await testSemanticCacheThumbsUpHit() && ok

        print("\n🔬 Test: SemanticAnswerCache 👎 not cached / short TTL")
        ok = await testSemanticCacheThumbsDownNoCache() && ok

        print("\n🔬 Test: SemanticAnswerCache re-verification blocks stale sources")
        ok = await testSemanticCacheReverificationBlocksStale() && ok

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

    // New tests for SemanticAnswerCache
    private static func seedDemoCorpusA() {
        VectorStore.shared.clear()
        let docs = [
            "Swift is a powerful and intuitive programming language for iOS and macOS.",
            "BM25 is a ranking function used in search engines.",
            "Embeddings map text to vectors in a semantic space.",
            "MMR balances relevance and diversity for reranking.",
            "Apple's M2 chips have unified memory."
        ]
        VectorStore.shared.addTexts(docs, deduplicate: false)
    }

    private static func seedDemoCorpusB() {
        VectorStore.shared.clear()
        let docs = [
            "Quantum mechanics studies the behavior of particles at microscopic scales.",
            "Photosynthesis converts light energy into chemical energy in plants.",
            "The French Revolution began in 1789 and led to significant political change.",
            "Neural networks approximate complex functions using layers of perceptrons."
        ]
        VectorStore.shared.addTexts(docs, deduplicate: false)
    }

    private static func makeQAContext(question: String, answer: String) -> ShimCtx {
        let embedder = VectorStore.shared.embeddingModel
        let sources = VectorStore.shared.retrieveChunks(for: question, topK: 3)
        let qaId = UUID()
        _ = embedder.embed(text: question) // keep embedding path hot; QAContextStore.put re-embeds
        return ShimCtx(qaId: qaId, question: question, answer: answer, sources: sources)
    }

    private struct ShimCtx {
        let qaId: UUID
        let question: String
        let answer: String
        let sources: [Chunk]
    }

    private static func waitBrief() async { try? await Task.sleep(nanoseconds: 150_000_000) }

    private static func assert(_ cond: @autoclosure () -> Bool, _ msg: String) -> Bool {
        if !cond() { print("❌ " + msg); return false }
        print("✅ " + msg)
        return true
    }

    private static func testSemanticCacheThumbsUpHit() async -> Bool {
        SemanticAnswerCache.shared.resetForTests()
        seedDemoCorpusA()
        let q = "swift programming language"
        let a = "Swift is used for iOS/macOS."
        let ctx = makeQAContext(question: q, answer: a)
        // store context for feedback handler
        QAContextStore.shared.put(qaId: ctx.qaId, question: ctx.question, answer: ctx.answer, sources: ctx.sources, embedder: VectorStore.shared.embeddingModel)
        // thumbs up -> cache insert
        RewardBus.shared.publish(qaId: ctx.qaId, verdict: .up, tags: [])
        await waitBrief()
        // similar query should hit
        if let hit = SemanticAnswerCache.shared.lookup(question: "swift language on macos", embedder: VectorStore.shared.embeddingModel, store: .shared, topK: 3, trace: true) {
            return assert(hit.answer == a, "Cache hit returns stored answer")
        }
        return assert(false, "Cache lookup should have hit for similar query")
    }

    private static func testSemanticCacheThumbsDownNoCache() async -> Bool {
        SemanticAnswerCache.shared.resetForTests()
        seedDemoCorpusA()
        let q = "what is bm25?"
        let a = "BM25 is a ranking function."
        let ctx = makeQAContext(question: q, answer: a)
        QAContextStore.shared.put(qaId: ctx.qaId, question: ctx.question, answer: ctx.answer, sources: ctx.sources, embedder: VectorStore.shared.embeddingModel)
        // thumbs down -> do not insert
        RewardBus.shared.publish(qaId: ctx.qaId, verdict: .down, tags: ["incorrect"])
        await waitBrief()
        let miss = SemanticAnswerCache.shared.lookup(question: "bm25 ranking", embedder: VectorStore.shared.embeddingModel, store: .shared, topK: 3, trace: true) == nil
        return assert(miss, "Thumbs-down answers are not cached")
    }

    private static func testSemanticCacheReverificationBlocksStale() async -> Bool {
        SemanticAnswerCache.shared.resetForTests()
        seedDemoCorpusA()
        let q = "what are embeddings?"
        let a = "Embeddings map text to vectors."
        let ctx = makeQAContext(question: q, answer: a)
        QAContextStore.shared.put(qaId: ctx.qaId, question: ctx.question, answer: ctx.answer, sources: ctx.sources, embedder: VectorStore.shared.embeddingModel)
        RewardBus.shared.publish(qaId: ctx.qaId, verdict: .up, tags: [])
        await waitBrief()
        // mutate corpus so overlap becomes 0
        seedDemoCorpusB()
        let res = SemanticAnswerCache.shared.lookup(question: "text embeddings semantic space", embedder: VectorStore.shared.embeddingModel, store: .shared, topK: 3, trace: true)
        return assert(res == nil, "Re-verification blocks stale cached answer when sources diverge")
    }
}
#endif
