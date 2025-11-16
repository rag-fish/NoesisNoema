// filepath: NoesisNoema/Shared/RAG/SemanticAnswerCache.swift
// Description: In-memory semantic answer cache with verification and TTL, wired to RewardBus.
// License: MIT

import Foundation
import Combine

struct CachedAnswer: Codable {
    let id: UUID
    var question: String
    var queryEmbedding: [Float]
    var answer: String
    var sources: [Chunk]
    var createdAt: Date
    var expiresAt: Date
}

final class HNSWLite {
    // NOTE: For scale < 10k, a brute-force cosine scan is fast enough. Keep API minimal.
    private var items: [CachedAnswer] = []
    private let queue = DispatchQueue(label: "hnsw.lite.queue", attributes: .concurrent)

    func upsert(_ item: CachedAnswer) {
        queue.async(flags: .barrier) {
            if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                self.items[idx] = item
            } else {
                self.items.append(item)
            }
        }
    }

    func clear() {
        queue.async(flags: .barrier) { self.items.removeAll() }
    }

    func remove(id: UUID) {
        queue.async(flags: .barrier) {
            self.items.removeAll { $0.id == id }
        }
    }

    func search(queryVec: [Float], topK: Int = 3) -> [CachedAnswer] {
        var snapshot: [CachedAnswer] = []
        queue.sync { snapshot = self.items }
        guard !snapshot.isEmpty else { return [] }
        let dim = queryVec.count
        var scored: [(CachedAnswer, Float)] = []
        for it in snapshot {
            guard it.queryEmbedding.count == dim else { continue }
            let s = cosine(queryVec, it.queryEmbedding)
            scored.append((it, s))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(topK).map { $0.0 }
    }

    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        let n = min(a.count, b.count)
        var i = 0
        while i < n { let x=a[i], y=b[i]; dot+=x*y; na+=x*x; nb+=y*y; i+=1 }
        let denom = (sqrtf(max(na, 1e-9)) * sqrtf(max(nb, 1e-9)))
        return denom == 0 ? 0 : dot/denom
    }
}

final class SemanticAnswerCache {
    static let shared = SemanticAnswerCache()

    // Config
    struct Config {
        var similarityThreshold: Float = 0.92
        var defaultTTL: TimeInterval = 7 * 24 * 3600 // 7 days
        var boostTTL: TimeInterval = 30 * 24 * 3600 // +30 days on 👍
        var punishTTL: TimeInterval = 3600 // set to 1h on 👎
        var minSourceOverlap: Float = 0.4 // require >=40% overlap to serve from cache
    }
    var config = Config()

    private let index = HNSWLite()
    private var bag = Set<AnyCancellable>()
    private let clock: () -> Date = { Date() }

    // Map QA id -> cache id to adjust TTL from RewardBus
    private var qaToCacheId: [UUID: UUID] = [:]
    private let sync = DispatchQueue(label: "semantic.cache.sync")

    private init() {
        // Subscribe to RewardBus for TTL updates and insertions based on QA context
        RewardBus.shared.subject
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] ev in self?.handleRewardEvent(ev) }
            .store(in: &bag)
    }

    // Public API
    func lookup(question: String, embedder: EmbeddingModel, store: VectorStore, topK: Int = 3, trace: Bool = false) -> (answer: String, sources: [Chunk])? {
        let qv = embedder.embed(text: question)
        let cands = index.search(queryVec: qv, topK: topK)
        let now = clock()
        for c in cands {
            if c.expiresAt < now { continue }
            // similarity already ensured by search ordering; quick check against threshold
            let sim = cosine(qv, c.queryEmbedding)
            if sim < config.similarityThreshold { continue }
            // Always re-verify sources
            if verifySources(question: question, cached: c, store: store, embedder: embedder, trace: trace) {
                if trace { print("[SAC] Cache HIT (sim=\(String(format: "%.3f", sim))) and verified (") }
                return (c.answer, c.sources)
            }
        }
        return nil
    }

    func putFromQAContext(_ ctx: AnswerContext) {
        let now = clock()
        let entry = CachedAnswer(id: UUID(), question: ctx.question, queryEmbedding: ctx.queryEmbedding, answer: ctx.answer, sources: ctx.sources, createdAt: now, expiresAt: now.addingTimeInterval(config.defaultTTL))
        index.upsert(entry)
        // Remember mapping for TTL adjustments on feedback
        sync.async { self.qaToCacheId[ctx.qaId] = entry.id }
    }

    // MARK: - Internal
    private func handleRewardEvent(_ ev: RewardEvent) {
        guard let ctx = QAContextStore.shared.get(ev.qaId) else { return }
        switch ev.verdict {
        case .up:
            // Insert or extend TTL
            self.putFromQAContext(ctx)
            self.extendTTL(qaId: ev.qaId, by: config.boostTTL)
        case .down:
            // Reduce TTL drastically
            self.setTTL(qaId: ev.qaId, to: config.punishTTL)
        }
    }

    private func extendTTL(qaId: UUID, by: TimeInterval) {
        adjustTTL(qaId: qaId) { expiresAt in expiresAt.addingTimeInterval(by) }
    }

    private func setTTL(qaId: UUID, to: TimeInterval) {
        adjustTTL(qaId: qaId) { _ in self.clock().addingTimeInterval(to) }
    }

    private func adjustTTL(qaId: UUID, _ f: @escaping (Date) -> Date) {
        var cacheId: UUID?
        sync.sync { cacheId = qaToCacheId[qaId] }
        guard let cacheId else { return }
        // reinsert with modified expiresAt (simplify by fetching nearest item by id via a search copy)
        // Since HNSWLite has no direct get-by-id, we perform a scan
        let q = DispatchQueue(label: "semantic.cache.adjust")
        q.async {
            // Snapshot and rebuild just this item
            // For simplicity in this minimal cache, we can't fetch item directly; we store an ephemeral context
            // Instead, re-add from QAContext since it has full payload
            if let ctx = QAContextStore.shared.get(qaId) {
                let nowEntry = CachedAnswer(id: cacheId, question: ctx.question, queryEmbedding: ctx.queryEmbedding, answer: ctx.answer, sources: ctx.sources, createdAt: Date(), expiresAt: f(Date()))
                self.index.upsert(nowEntry)
            }
        }
    }

    private func verifySources(question: String, cached: CachedAnswer, store: VectorStore, embedder: EmbeddingModel, trace: Bool) -> Bool {
        // Retrieve fresh top chunks and check overlap with cached sources by content
        let fresh = store.retrieveChunks(for: question, topK: max(3, min(cached.sources.count, 6)))
        if fresh.isEmpty { return false }
        let freshSet = Set(fresh.map { $0.content })
        let cachedSet = Set(cached.sources.map { $0.content })
        let inter = freshSet.intersection(cachedSet)
        let union = freshSet.union(cachedSet)
        let jaccard = union.isEmpty ? 0 : Float(inter.count) / Float(union.count)
        if trace { print("[SAC] verify Jaccard=\(String(format: "%.2f", jaccard)) inter=\(inter.count) union=\(union.count)") }
        return jaccard >= config.minSourceOverlap
    }

    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        let n = min(a.count, b.count)
        var i = 0
        while i < n { let x=a[i], y=b[i]; dot+=x*y; na+=x*x; nb+=y*y; i+=1 }
        let denom = (sqrtf(max(na, 1e-9)) * sqrtf(max(nb, 1e-9)))
        return denom == 0 ? 0 : dot/denom
    }
    // Test helper
    func resetForTests() {
        index.clear()
        sync.async { self.qaToCacheId.removeAll() }
    }
}
