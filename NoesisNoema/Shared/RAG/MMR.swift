// filepath: Shared/RAG/MMR.swift
// Project: NoesisNoema
// File: MMR.swift
// Description: Maximal Marginal Relevance reranker over embedding space.
// License: MIT License

import Foundation

struct MMR {
    /// Perform MMR reranking.
    /// - Parameters:
    ///   - queryEmbedding: query embedding vector
    ///   - candidates: candidate chunks
    ///   - k: number of results to select
    ///   - lambda: trade-off between relevance (to query) and diversity (away from selected)
    ///   - trace: print decision logs
    /// - Returns: top-k chunks in selected order
    static func rerank(queryEmbedding: [Float], candidates: [Chunk], k: Int, lambda: Float = 0.7, trace: Bool = false) -> [Chunk] {
        guard !candidates.isEmpty else { return [] }
        let k = min(max(k, 1), candidates.count)
        var selected: [Chunk] = []
        var remaining = candidates
        if trace { print("[MMR] lambda=\(String(format: "%.2f", lambda)), k=\(k)") }
        while selected.count < k && !remaining.isEmpty {
            var bestIdx = 0
            var bestScore: Float = -Float.greatestFiniteMagnitude
            for (i, cand) in remaining.enumerated() {
                let relevance = cosine(queryEmbedding, cand.embedding)
                var diversity: Float = 0
                if !selected.isEmpty {
                    var maxSim: Float = -Float.greatestFiniteMagnitude
                    for s in selected {
                        let sim = cosine(cand.embedding, s.embedding)
                        if sim > maxSim { maxSim = sim }
                    }
                    diversity = maxSim
                }
                let score = lambda * relevance - (1 - lambda) * diversity
                if score > bestScore { bestScore = score; bestIdx = i }
            }
            let chosen = remaining.remove(at: bestIdx)
            if trace {
                let preview = String(chosen.content.prefix(60))
                print(String(format: "[MMR] + '%@' score=%.3f", preview as NSString, bestScore))
            }
            selected.append(chosen)
        }
        return selected
    }
    
    private static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        let n = min(a.count, b.count)
        var i = 0
        while i < n { let x=a[i], y=b[i]; dot+=x*y; na+=x*x; nb+=y*y; i+=1 }
        let denom = (sqrtf(max(na, 1e-9)) * sqrtf(max(nb, 1e-9)))
        if denom == 0 { return 0 }
        return dot / denom
    }
}
