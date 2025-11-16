// filepath: LlamaBridgeTest/RewardBusShim.swift
// BRIDGE_TEST-only RewardBus shim
#if BRIDGE_TEST
import Foundation
import Combine

enum FeedbackVerdict: String, Codable {
    case up
    case down
}

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
#endif
