// filepath: LlamaBridgeTest/QAContextStoreShim.swift
// BRIDGE_TEST-only QAContextStore shim
#if BRIDGE_TEST
import Foundation

struct AnswerContextShim: Codable {
    let qaId: UUID
    let question: String
    let answer: String
    let sources: [Chunk]
    let createdAt: Date
}

final class QAContextStore {
    static let shared = QAContextStore()
    private var ctx: [UUID: AnswerContextShim] = [:]
    private let queue = DispatchQueue(label: "qa.context.store.shim.queue", attributes: .concurrent)
    private init() {}

    func put(qaId: UUID, question: String, answer: String, sources: [Chunk], embedder: EmbeddingModel) {
        let ac = AnswerContextShim(qaId: qaId, question: question, answer: answer, sources: sources, createdAt: Date())
        queue.async(flags: .barrier) { self.ctx[qaId] = ac }
    }

    func get(_ qaId: UUID) -> AnswerContextShim? {
        var v: AnswerContextShim?
        queue.sync { v = ctx[qaId] }
        return v
    }

    func remove(_ qaId: UUID) {
        queue.async(flags: .barrier) { self.ctx.removeValue(forKey: qaId) }
    }
}
#endif
