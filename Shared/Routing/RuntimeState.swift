// NoesisNoema is a knowledge graph framework for building AI applications.
// This file defines the RuntimeState struct for routing decisions.
// EPIC1: Client Authority Hardening (Phase 2)
// Created: 2026-02-21
// License: MIT License

import Foundation

/// Network connectivity state
enum NetworkState: String, Codable, Equatable {
    case online    // Network confirmed
    case offline   // Network unavailable
    case degraded  // High latency
}

/// Local model capability information
struct LocalModelCapability: Equatable {
    /// Model name (e.g., "llama-3.2-8b")
    let modelName: String

    /// Maximum token capacity
    let maxTokens: Int

    /// Intents supported by this local model
    let supportedIntents: [Intent]

    /// Is the local model available and initialized?
    let available: Bool

    init(
        modelName: String,
        maxTokens: Int,
        supportedIntents: [Intent],
        available: Bool
    ) {
        self.modelName = modelName
        self.maxTokens = maxTokens
        self.supportedIntents = supportedIntents
        self.available = available
    }
}

/// Runtime state for routing decisions
struct RuntimeState: Equatable {
    /// Local model capability information
    let localModelCapability: LocalModelCapability

    /// Current network state
    let networkState: NetworkState

    /// Token threshold for local vs cloud routing (default: 4096)
    let tokenThreshold: Int

    /// Cloud model name (e.g., "gpt-4")
    let cloudModelName: String

    init(
        localModelCapability: LocalModelCapability,
        networkState: NetworkState,
        tokenThreshold: Int = 4096,
        cloudModelName: String = "gpt-4"
    ) {
        self.localModelCapability = localModelCapability
        self.networkState = networkState
        self.tokenThreshold = tokenThreshold
        self.cloudModelName = cloudModelName
    }
}
