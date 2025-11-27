// filepath: NoesisNoema/Shared/RAG/QAContextStore.swift
// Description: Stores per-QA context (query embedding, answer, sources) so RewardBus handlers can cache on feedback.
// License: MIT

import Foundation

struct AnswerContext: Codable {
    let qaId: UUID
    let question: String
    let queryEmbedding: [Float]
    let answer: String
    let sources: [Chunk]
    let createdAt: Date
}

final class QAContextStore {
    static let shared = QAContextStore()
    private var ctx: [UUID: AnswerContext] = [:]
    private let queue = DispatchQueue(label: "qa.context.store.queue", attributes: .concurrent)
    private init() {}

    func put(qaId: UUID, question: String, answer: String, sources: [Chunk], embedder: EmbeddingModel) {
        let emb = embedder.embed(text: question)
        let ac = AnswerContext(qaId: qaId, question: question, queryEmbedding: emb, answer: answer, sources: sources, createdAt: Date())
        queue.async(flags: .barrier) { self.ctx[qaId] = ac }
    }

    func get(_ qaId: UUID) -> AnswerContext? {
        var v: AnswerContext?
        queue.sync { v = ctx[qaId] }
        return v
    }

    func remove(_ qaId: UUID) {
        queue.async(flags: .barrier) { self.ctx.removeValue(forKey: qaId) }
    }
}
