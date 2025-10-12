// filepath: NoesisNoema/Shared/RAG/DeepSearch.swift
// Project: NoesisNoema
// File: DeepSearch.swift
// Description: Multi-round local deep search over VectorStore using LocalRetriever + keyword expansion.
// License: MIT License

// Responsibility: ローカル VectorStore に対する多段クエリ拡張＋MMR再ランクでのディープサーチを提供。
// Depends on: VectorStore, LocalRetriever, MMR, EmbeddingModel, Foundation
import Foundation

/// DeepSearch performs multi-round retrieval with lightweight query expansion from top results.
/// It is fully local and does not require network calls.
struct DeepSearch {
    struct Config {
        var rounds: Int = 2            // number of expansion rounds
        var breadth: Int = 8           // candidates per round (pre-rerank)
        var topK: Int = 5              // final topK
        var mmrLambda: Float = 0.7     // trade-off for MMR in LocalRetriever
        var enableQueryIteration: Bool = true // reuse QueryIterator in LocalRetriever
        var trace: Bool = false
    }
    var config: Config = .init()

    private let store: VectorStore
    private var retriever: LocalRetriever

    init(store: VectorStore = .shared, config: Config = .init()) {
        self.store = store
        self.config = config
        var rcfg = LocalRetriever.Config()
        rcfg.stageCandidates = max(config.breadth, rcfg.stageCandidates)
        rcfg.topK = max(config.topK, 1)
        rcfg.mmrLambda = config.mmrLambda
        rcfg.enableQueryIteration = config.enableQueryIteration
        self.retriever = LocalRetriever(store: store, config: rcfg)
    }

    /// Run deep retrieval for a query.
    func retrieve(query: String) -> [Chunk] {
        let _log = SystemLog()
        let _t0 = Date()
        _log.logEvent(event: "[DeepSearch] retrieve enter qLen=\(query.count) rounds=\(config.rounds) breadth=\(config.breadth) topK=\(config.topK)")
        defer {
            let dt = Date().timeIntervalSince(_t0)
            _log.logEvent(event: String(format: "[DeepSearch] retrieve exit (%.2f ms)", dt*1000))
        }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var pool: [Chunk] = []
        var seen = Set<String>() // dedupe by content
        var currentQueries: [String] = [normalize(query)]

        for round in 0..<max(1, config.rounds) {
            if config.trace { print("[DeepSearch] Round #\(round+1) queries: \(currentQueries)") }
            // For each query, retrieve breadth candidates
            for q in currentQueries {
                let cs = retriever.retrieve(query: q, k: config.breadth, lambda: config.mmrLambda, trace: config.trace)
                for c in cs where seen.insert(c.content).inserted { pool.append(c) }
            }
            if round < config.rounds - 1 {
                // Expand queries from current pool
                let expanded = expandQueries(from: pool, limit: 6)
                // Merge with previous queries (preserve order, drop duplicates)
                var merged: [String] = []
                var qseen = Set<String>()
                for q in currentQueries + expanded {
                    let n = normalize(q)
                    if n.isEmpty { continue }
                    if qseen.insert(n).inserted { merged.append(n) }
                }
                currentQueries = Array(merged.prefix(8))
            }
        }
        if pool.isEmpty { return [] }
        // Final rerank with MMR using original query as anchor
        let qEmb = store.embeddingModel.embed(text: query)
        let ranked = MMR.rerank(queryEmbedding: qEmb, candidates: pool, k: config.topK, lambda: config.mmrLambda, trace: config.trace)
        return ranked
    }

    // MARK: - Query expansion (keyword-based)
    private func expandQueries(from chunks: [Chunk], limit: Int) -> [String] {
        guard !chunks.isEmpty else { return [] }
        // Score tokens by frequency across top chunks, penalize stopwords and short tokens
        var freq: [String: Int] = [:]
        for c in chunks.prefix(config.breadth) {
            let toks = tokenize(c.content)
            // unique within a chunk to reduce repetition bias
            for t in Set(toks) {
                if stopwords.contains(t) { continue }
                if t.count < 3 { continue }
                freq[t, default: 0] += 1
            }
        }
        if freq.isEmpty { return [] }
        let topTerms = freq.sorted { $0.value > $1.value }.prefix(12).map { $0.key }
        var out: [String] = []
        // Create short expanded queries by combining original salient terms
        for term in topTerms {
            out.append(term)
        }
        // Also add 2-grams heuristically
        for i in 0..<(topTerms.count - 1) {
            out.append(topTerms[i] + " " + topTerms[i+1])
        }
        // de-dup and cap
        var seen = Set<String>()
        var res: [String] = []
        for q in out {
            let n = normalize(q)
            if n.isEmpty { continue }
            if seen.insert(n).inserted { res.append(n) }
        }
        return Array(res.prefix(limit))
    }

    // MARK: - Utils
    private func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let collapsed = lowered.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let stopwords: Set<String> = [
        // English
        "the","a","an","of","to","and","or","in","on","for","with","is","are","be","as","by","at","from","that","this","it","its","was","were","has","have","had",
        // Japanese (lite)
        "の","に","は","を","が","と","で","も","へ","する","なる","ある","ない"
    ]

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
