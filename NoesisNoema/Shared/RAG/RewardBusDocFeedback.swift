// filepath: NoesisNoema/Shared/RAG/RewardBus+DocFeedback.swift
// Description: DocFeedback API layered on top of RewardBus (defined in Shared/Feedback/RewardBus.swift)
// License: MIT

import Foundation

// Reasons for document-level feedback mapping to re-ranking coefficients
enum FeedbackReason: String {
    case helpful = "Helpful"
    case notRelevant = "Not relevant"
    case unknown = "Unknown"
}

// Feedback payload for documents/chunks
struct DocFeedbackEvent {
    let qaId: UUID?
    let verdict: FeedbackVerdict
    let reason: FeedbackReason
    let chunk: Chunk
    let timestamp: Date
}

// Extend the canonical RewardBus with doc feedback pub/sub
extension RewardBus {
    typealias DocFeedbackListener = (DocFeedbackEvent) -> Void

    private var _docFeedbackListeners: [UUID: DocFeedbackListener] {
        get { RewardBus._docListenersStore }
        set { RewardBus._docListenersStore = newValue }
    }

    @discardableResult
    func subscribeDocFeedback(_ listener: @escaping DocFeedbackListener) -> UUID {
        let id = UUID()
        _docFeedbackListeners[id] = listener
        return id
    }

    func unsubscribeDocFeedback(_ id: UUID) {
        _docFeedbackListeners.removeValue(forKey: id)
    }

    func publishDocFeedback(qaId: UUID?, verdict: FeedbackVerdict, reason: FeedbackReason, chunk: Chunk) {
        let ev = DocFeedbackEvent(qaId: qaId, verdict: verdict, reason: reason, chunk: chunk, timestamp: Date())
        for (_, cb) in _docFeedbackListeners { cb(ev) }
    }
}

// Static backing store for doc feedback listeners
private extension RewardBus {
    private static var _docListenersStore: [UUID: (DocFeedbackEvent) -> Void] = [:]
}
