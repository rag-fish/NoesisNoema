// filepath: Shared/RAG/LocalRetriever.swift
// Project: NoesisNoema
// File: LocalRetriever.swift
// Description: Two-stage local retriever (BM25 + embedding hybrid) with query iteration and MMR rerank.
// License: MIT License

// Responsibility: ローカル VectorStore に対するBM25＋埋め込みハイブリッド検索とMMR再ランク、クエリ反復を提供。
// Depends on: VectorStore, EmbeddingModel, QueryIterator, MMR, Foundation
import Foundation

final class LocalRetriever {
    struct Config {
        var bm25_k1: Float = 1.5
        var bm25_b: Float = 0.75
        var stageCandidates: Int = 12 // per strategy
        var mmrLambda: Float = 0.7
        var topK: Int = 5
        var enableQueryIteration: Bool = true
    }

    var config: Config
    private let store: VectorStore
    private var embedder: EmbeddingModel { store.embeddingModel }
    private let qi = QueryIterator()

    init(store: VectorStore = .shared, config: Config = .init()) {
        self.store = store
        self.config = config
    }

    // MARK: - Public API
    // PERFORMANCE: Async retrieval off main thread
    func retrieve(query: String, k: Int? = nil, lambda: Float? = nil, trace: Bool = false) -> [Chunk] {
        let _log = SystemLog()
        let _t0 = Date()
        _log.logEvent(event: "[Retriever] retrieve enter qLen=\(query.count) k=\(k ?? config.topK) lambda=\(lambda ?? config.mmrLambda) docs=\(store.chunks.count)")
        defer {
            let dt = Date().timeIntervalSince(_t0)
            _log.logEvent(event: String(format: "[Retriever] retrieve exit (%.2f ms)", dt*1000))
        }
        let K = k ?? config.topK
        let L = lambda ?? config.mmrLambda
        let allChunks = store.chunks
        guard !allChunks.isEmpty else {
            if trace { print("[Retriever] No chunks in VectorStore.") }
            return []
        }

        // PERFORMANCE: Dynamic context window based on query length
        let effectiveK = dynamicTopK(queryLength: query.count, requestedK: K)
        let variants = (config.enableQueryIteration ? qi.variants(for: query) : [query])
        if trace { print("[Retriever] Query variants: \(variants), effectiveK: \(effectiveK)") }

        // Pre-tokenize documents for BM25 (cached in memory)
        let docsTokens: [[String]] = allChunks.map { tokenize($0.content) }
        let avgdl: Float = docsTokens.isEmpty ? 0 : Float(docsTokens.map { $0.count }.reduce(0,+)) / Float(docsTokens.count)
        var df: [String: Int] = [:]
        for toks in docsTokens { Set(toks).forEach { df[$0, default: 0] += 1 } }
        let N = allChunks.count

        // Collect candidates from both strategies for each variant
        var candidateList: [Chunk] = []
        var seen = Set<String>() // duplicate suppression by content
        for v in variants {
            // BM25
            let bm = bm25TopK(query: v, docsTokens: docsTokens, chunks: allChunks, N: N, df: df, avgdl: avgdl, topK: config.stageCandidates)
            for c in bm where seen.insert(c.content).inserted { candidateList.append(c) }

            // Embedding
            let em = store.retrieveChunks(for: v, topK: config.stageCandidates)
            for c in em where seen.insert(c.content).inserted { candidateList.append(c) }
        }
        if trace { print("[Retriever] Candidates after hybrid+dedupe: \(candidateList.count) (from \(N) docs)") }
        if candidateList.isEmpty { return [] }

        // Final rerank with MMR
        let qEmb = embedder.embed(text: query)
        let ranked = MMR.rerank(queryEmbedding: qEmb, candidates: candidateList, k: effectiveK, lambda: L, trace: trace)
        return ranked
    }

    // MARK: - Dynamic Context Window
    private func dynamicTopK(queryLength: Int, requestedK: Int) -> Int {
        // Small question → small context
        if queryLength < 20 { return min(requestedK, 2) }
        if queryLength < 50 { return min(requestedK, 3) }
        // Long question → expanded window
        if queryLength > 100 { return min(requestedK + 2, 8) }
        return requestedK
    }

    // MARK: - BM25
    private func bm25TopK(query: String, docsTokens: [[String]], chunks: [Chunk], N: Int, df: [String:Int], avgdl: Float, topK: Int) -> [Chunk] {
        let qToks = tokenize(query)
        guard !qToks.isEmpty else { return [] }
        let k1 = config.bm25_k1
        let b = config.bm25_b

        var scored: [(Int, Float)] = []
        scored.reserveCapacity(chunks.count)
        for (i, toks) in docsTokens.enumerated() {
            if toks.isEmpty { continue }
            let dl = Float(toks.count)
            // term frequencies
            var tf: [String:Int] = [:]
            for t in toks { tf[t, default: 0] += 1 }
            var score: Float = 0
            for t in qToks {
                guard let n = df[t] else { continue }
                let idf = logf((Float(N - n) + 0.5) / (Float(n) + 0.5) + 1)
                let f = Float(tf[t] ?? 0)
                if f == 0 { continue }
                let denom = f + k1 * (1 - b + b * (dl / max(avgdl, 1e-6)))
                score += idf * (f * (k1 + 1)) / denom
            }
            if score > 0 { scored.append((i, score)) }
        }
        if scored.isEmpty { return [] }
        let top = scored.sorted { $0.1 > $1.1 }.prefix(topK)
        return top.map { chunks[$0.0] }
    }

    // MARK: - Tokenization
    private func tokenize(_ s: String) -> [String] {
        let lowered = s.lowercased()
        let pattern = "[A-Za-z0-9一-龥ぁ-ゔァ-ヴー々〆〤_]+"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
        let matches = regex?.matches(in: lowered, options: [], range: range) ?? []
        return matches.compactMap { m in
            guard let r = Range(m.range, in: lowered) else { return nil }
            return String(lowered[r])
        }
    }
}
