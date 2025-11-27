// filepath: NoesisNoema/Shared/Feedback/RewardBus.swift
// Description: In-process reward signal bus for feedback events.

import Foundation
import Combine

struct RewardEvent: Codable, Hashable {
    let qaId: UUID
    let verdict: FeedbackVerdict
    let tags: [String]
    let timestamp: Date
}

final class RewardBus {
    static let shared = RewardBus()
    let subject = PassthroughSubject<RewardEvent, Never>()
    private init() {}
    func publish(qaId: UUID, verdict: FeedbackVerdict, tags: [String]) {
        subject.send(RewardEvent(qaId: qaId, verdict: verdict, tags: tags, timestamp: Date()))
    }
}
