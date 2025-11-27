// filepath: NoesisNoema/Shared/RAG/HardNegCache.swift
// Description: LRU-based hard negative cache to penalize repeatedly bad documents in reranking.
// License: MIT

import Foundation

final class HardNegCache {
    struct Entry { let key: String; var ts: TimeInterval }

    private let capacity: Int
    private var map: [String: Entry] = [:]
    private var order: [String] = [] // most-recent at end
    private let lock = NSLock()

    init(capacity: Int = 512) {
        self.capacity = max(8, capacity)
    }

    func makeKey(query: String, chunk: Chunk) -> String {
        // Query-agnostic key to penalize repeated bad docs globally
        return chunk.content.hashValue.description
    }

    func insert(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        if map[key] != nil {
            map[key]?.ts = now
            if let idx = order.firstIndex(of: key) { order.remove(at: idx) }
            order.append(key)
            return
        }
        // evict if needed
        if order.count >= capacity, let victim = order.first {
            order.removeFirst()
            map.removeValue(forKey: victim)
        }
        map[key] = Entry(key: key, ts: now)
        order.append(key)
    }

    func contains(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return map[key] != nil
    }

    func remove(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        map.removeValue(forKey: key)
        if let idx = order.firstIndex(of: key) { order.remove(at: idx) }
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        map.removeAll(); order.removeAll()
    }
}
