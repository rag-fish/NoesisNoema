// filepath: NoesisNoema/Shared/RAG/BanditRetriever.swift
// Description: Adapter that applies ParamBandit to choose retrieval params per query.
// License: MIT

import Foundation

struct BanditRetriever {
    var bandit: ParamBandit
    var base: LocalRetriever
    private let store: VectorStore

    init(bandit: ParamBandit = .default, store: VectorStore = .shared) {
        self.bandit = bandit
        self.store = store
        self.base = LocalRetriever(store: store, config: .init())
    }

    /// Retrieve chunks using Thompson-sampled parameters per query cluster.
    /// - Parameters:
    ///   - query: input query
    ///   - qaId: identifier for this QA session (used to attribute reward updates)
    ///   - trace: log decisions
    func retrieve(query: String, qaId: UUID = UUID(), trace: Bool = false) -> [Chunk] {
        let choice = bandit.chooseParams(for: query, qaId: qaId)
        if trace { print("[BanditRetriever] cluster=\(choice.cluster) arm=\(choice.arm.id) params=\(choice.arm.params)") }
        let ps = choice.arm.params
        let results = base.retrieve(query: query, k: ps.topK, lambda: ps.mmrLambda, trace: trace)
        if ps.minScore <= 0 { return results }
        // Filter by minScore using cosine similarity to the original query
        let q = store.embeddingModel.embed(text: query)
        var filtered: [Chunk] = []
        filtered.reserveCapacity(results.count)
        for c in results {
            let sim = cosine(q, c.embedding)
            if sim >= ps.minScore { filtered.append(c) }
        }
        return filtered
    }
}

// Local cosine util (duplicated from MMR for lightweight use)
private func cosine(_ a: [Float], _ b: [Float]) -> Float {
    var dot: Float = 0, na: Float = 0, nb: Float = 0
    let n = min(a.count, b.count)
    var i = 0
    while i < n { let x=a[i], y=b[i]; dot+=x*y; na+=x*x; nb+=y*y; i+=1 }
    let denom = (sqrtf(max(na, 1e-9)) * sqrtf(max(nb, 1e-9)))
    if denom == 0 { return 0 }
    return dot / denom
}
