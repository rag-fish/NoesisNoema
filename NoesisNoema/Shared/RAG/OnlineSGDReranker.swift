// filepath: NoesisNoema/Shared/RAG/OnlineSGDReranker.swift
// Description: Lightweight logistic-regression reranker with online SGD updates and HardNegCache.
// License: MIT

import Foundation

final class OnlineSGDReranker {
    struct Config {
        var lr: Float = 0.05       // learning rate
        var l2: Float = 1e-4       // L2 regularization
        var hardNegPenalty: Float = 0.5 // subtract from score when in cache
        var featureCount: Int = 6  // [bias, dense, bm25, pos, diversity, citation]
        var keepTopForDiversity: Int = 8
    }

    static let shared = OnlineSGDReranker()

    private(set) var w: [Float]
    private let cfg: Config
    private let cache = HardNegCache(capacity: 1024)

    // Store latest feature vectors by key for online updates upon feedback
    private var latestFeat: [String: [Float]] = [:]
    private let qLock = NSLock()

    private init(cfg: Config = .init()) {
        self.cfg = cfg
        self.w = Array(repeating: 0, count: cfg.featureCount)
        self.w[0] = 0 // bias
        // subscribe feedback
        _ = RewardBus.shared.subscribeDocFeedback { [weak self] ev in
            self?.handleFeedback(ev)
        }
    }

    // MARK: - Test helpers
    func reset() {
        qLock.lock(); defer { qLock.unlock() }
        w = Array(repeating: 0, count: cfg.featureCount)
        latestFeat.removeAll()
        cache.clear()
    }

    // MARK: - Public API
    func rerank(query: String,
                candidates: [Chunk],
                bm25Scores: [String: Float]? = nil,
                topK: Int) -> [Chunk] {
        guard !candidates.isEmpty else { return [] }
        // Precompute dense sims
        let qEmb = VectorStore.shared.embeddingModel.embed(text: query)
        var dense: [String: Float] = [:]
        dense.reserveCapacity(candidates.count)
        for c in candidates { dense[c.content] = cosine(qEmb, c.embedding) }

        // Diversity reference set: top-N by dense for quick approx
        let topDiverse = candidates.sorted { (dense[$0.content] ?? 0) > (dense[$1.content] ?? 0) }
            .prefix(max(2, min(cfg.keepTopForDiversity, candidates.count)))

        // Feature and score per candidate
        var scored: [(Chunk, Float)] = []
        scored.reserveCapacity(candidates.count)
        for (idx, c) in candidates.enumerated() {
            let pos = 1.0 / Float(idx + 1)
            let f = makeFeatures(query: query,
                                 chunk: c,
                                 denseScore: dense[c.content] ?? 0,
                                 bm25Score: bm25Scores?[c.content] ?? 0,
                                 pos: pos,
                                 diversityAnchors: Array(topDiverse))
            let s = sigmoid(dot(w, f))
            // apply hard-neg penalty
            let key = cache.makeKey(query: query, chunk: c)
            let penalized = cache.contains(key) ? max(0, s - cfg.hardNegPenalty) : s
            qLock.lock(); latestFeat[key] = f; qLock.unlock()
            scored.append((c, penalized))
        }
        // Sort by score desc and cut topK
        let top = scored.sorted { $0.1 > $1.1 }.prefix(max(1, min(topK, scored.count)))
        return top.map { $0.0 }
    }

    // Update from feedback (up=1, down=0)
    private func handleFeedback(_ ev: DocFeedbackEvent) {
        let y: Float
        switch ev.verdict {
        case .up: y = 1
        case .down: y = 0
        }
        let key = cache.makeKey(query: ev.qaId?.uuidString ?? "", chunk: ev.chunk)
        // Prefer previously stored features using query+chunk; fallback to best-effort recompute without BM25/pos
        let x: [Float]
        if let f = latestFeat[key] {
            x = f
        } else {
            // Last resort: compute with zeros (has minimal effect but keeps training stable)
            x = makeFeatures(query: ev.qaId?.uuidString ?? "",
                             chunk: ev.chunk,
                             denseScore: 0,
                             bm25Score: 0,
                             pos: 0,
                             diversityAnchors: [])
        }
        sgdUpdate(x: x, y: y)
        if y == 0 {
            // remember hard negative
            cache.insert(key)
        } else {
            cache.remove(key)
        }
    }

    // MARK: - SGD
    private func sgdUpdate(x: [Float], y: Float) {
        let wx = dot(w, x)
        let p = sigmoid(wx)
        let err = p - y // derivative of logloss wrt wx
        // w := w - lr * (err * x + l2 * w)
        for i in 0..<min(w.count, x.count) {
            let grad = err * x[i] + cfg.l2 * w[i]
            w[i] -= cfg.lr * grad
        }
    }

    // MARK: - Features
    private func makeFeatures(query: String,
                              chunk: Chunk,
                              denseScore: Float,
                              bm25Score: Float,
                              pos: Float,
                              diversityAnchors: [Chunk]) -> [Float] {
        var feats = Array(repeating: Float(0), count: cfg.featureCount)
        feats[0] = 1 // bias
        feats[1] = clamp01(denseScore * 0.5 + 0.5) // cosine [-1,1] -> [0,1]
        feats[2] = clamp01(bm25Score.isFinite ? tanh(bm25Score) : 0)
        feats[3] = clamp01(pos)
        // Diversity = 1 - max cosine(sim to anchors)
        var maxSim: Float = 0
        for a in diversityAnchors where a.content != chunk.content {
            maxSim = max(maxSim, cosine(a.embedding, chunk.embedding))
        }
        feats[4] = clamp01(1 - maxSim) // higher is more diverse
        // citation match (placeholder): title/path overlap with query tokens
        feats[5] = citationMatchScore(query: query, chunk: chunk)
        return feats
    }

    private func citationMatchScore(query: String, chunk: Chunk) -> Float {
        let q = query.lowercased()
        var score: Float = 0
        if let t = chunk.sourceTitle?.lowercased(), !t.isEmpty, q.contains(t) { score += 0.5 }
        if let p = chunk.sourcePath?.lowercased(), !p.isEmpty, q.contains(URL(fileURLWithPath: p).lastPathComponent.lowercased()) { score += 0.5 }
        return min(1, score)
    }

    // MARK: - Math helpers
    private func dot(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in 0..<min(a.count, b.count) { s += a[i] * b[i] }
        return s
    }
    private func sigmoid(_ x: Float) -> Float { 1 / (1 + exp(-x)) }
    private func clamp01(_ x: Float) -> Float { max(0, min(1, x)) }
    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        let n = min(a.count, b.count)
        var i = 0
        while i < n { let x=a[i], y=b[i]; dot+=x*y; na+=x*x; nb+=y*y; i+=1 }
        let denom = (sqrtf(max(na, 1e-9)) * sqrtf(max(nb, 1e-9)))
        if denom == 0 { return 0 }
        return dot / denom
    }
}
