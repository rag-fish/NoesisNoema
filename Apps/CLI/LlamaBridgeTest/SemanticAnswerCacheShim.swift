// filepath: LlamaBridgeTest/SemanticAnswerCacheShim.swift
// BRIDGE_TEST-only SemanticAnswerCache shim
#if BRIDGE_TEST
import Foundation
import Combine

final class SemanticAnswerCache {
    static let shared = SemanticAnswerCache()

    struct Config {
        var defaultTTL: TimeInterval = 7 * 24 * 3600 // 7 days
        var boostTTL: TimeInterval = 30 * 24 * 3600
        var punishTTL: TimeInterval = 3600 // 1h
        var minSourceOverlap: Float = 0.4
    }
    var config = Config()

    private struct Entry {
        let id: UUID
        var question: String
        var answer: String
        var sources: [Chunk]
        var createdAt: Date
        var expiresAt: Date
    }

    private let q = DispatchQueue(label: "semantic.cache.shim", attributes: .concurrent)
    private var items: [UUID: Entry] = [:]
    private var qaToCacheId: [UUID: UUID] = [:]
    private var bag = Set<AnyCancellable>()

    private init() {
        RewardBus.shared.subject
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] ev in self?.handleReward(ev) }
            .store(in: &bag)
    }

    private func handleReward(_ ev: RewardEvent) {
        switch ev.verdict {
        case .up:
            if let ac = QAContextStore.shared.get(ev.qaId) {
                let now = Date()
                let entry = Entry(id: UUID(), question: ac.question, answer: ac.answer, sources: ac.sources, createdAt: now, expiresAt: now.addingTimeInterval(config.defaultTTL))
                q.async(flags: .barrier) {
                    self.items[entry.id] = entry
                    self.qaToCacheId[ev.qaId] = entry.id
                }
            }
        case .down:
            q.async(flags: .barrier) {
                if let id = self.qaToCacheId[ev.qaId], var e = self.items[id] {
                    e.expiresAt = Date().addingTimeInterval(self.config.punishTTL)
                    self.items[id] = e
                }
            }
        }
    }

    func lookup(question: String, embedder: EmbeddingModel, store: VectorStore, topK: Int = 3, trace: Bool = false) -> (answer: String, sources: [Chunk])? {
        // Take a snapshot
        var snapshot: [Entry] = []
        q.sync { snapshot = Array(self.items.values) }
        guard !snapshot.isEmpty else { return nil }
        let now = Date()
        // Fresh sources for verification
        let fresh = store.retrieveChunks(for: question, topK: max(3, topK))
        if fresh.isEmpty { return nil }
        let freshSet = Set(fresh.map { $0.content })
        var best: (Entry, Float)? = nil
        for e in snapshot where e.expiresAt > now {
            let cachedSet = Set(e.sources.map { $0.content })
            let inter = freshSet.intersection(cachedSet)
            let union = freshSet.union(cachedSet)
            let jaccard: Float = union.isEmpty ? 0 : Float(inter.count) / Float(union.count)
            if trace { print(String(format: "[SAC-shim] candidate '%@' J=%.2f", e.question, jaccard)) }
            if jaccard >= config.minSourceOverlap {
                if best == nil || jaccard > best!.1 { best = (e, jaccard) }
            }
        }
        if let b = best {
            if trace { print(String(format: "[SAC-shim] HIT '%@' J=%.2f", b.0.question, b.1)) }
            return (b.0.answer, b.0.sources)
        }
        return nil
    }

    func resetForTests() {
        q.async(flags: .barrier) {
            self.items.removeAll()
            self.qaToCacheId.removeAll()
        }
    }
}
#endif
