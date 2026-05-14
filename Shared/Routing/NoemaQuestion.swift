// NoesisNoema is a knowledge graph framework for building AI applications.
// This file defines the NoemaQuestion struct for routing inputs.
// Created: 2026-02-21
// Updated: 2026-05-15 — added toolRequired, privacySensitive, lowLatencyPreferred
//   as first-class routing signals (Phase 2, Issue #70)
// License: MIT License

import Foundation

/// Privacy level for execution control
enum PrivacyLevel: String, Codable, Equatable {
    case local = "local"   // Force local execution
    case cloud = "cloud"   // Force cloud execution
    case auto = "auto"     // Allow Router to decide
}

/// Intent classification for questions
enum Intent: String, Codable, Equatable {
    case informational  // Simple factual queries
    case analytical     // Reasoning, analysis
    case retrieval      // RAG-based context retrieval
}

/// Question object representing user input for routing
struct NoemaQuestion: Equatable {
    /// Unique question identifier
    let id: UUID

    /// User prompt text
    let content: String

    /// Privacy level constraint
    let privacyLevel: PrivacyLevel

    /// Optional intent classification
    let intent: Intent?

    /// Active session identifier
    let sessionId: UUID

    // MARK: - Routing Signals
    // These fields are first-class routing signals derived from policy evaluation.
    // They inform Router decisions and are captured in RoutingInputSnapshot.
    // All three default to false so existing call sites require no changes.

    /// Whether this question requires tool/function calling capabilities.
    /// When true, Router should prefer cloud (tools require cloud agent).
    let toolRequired: Bool

    /// Whether this question contains privacy-sensitive information.
    /// When true, Router should prefer local (privacy stays on-device).
    let privacySensitive: Bool

    /// Whether a low-latency response is preferred for this question.
    /// When true, Router should prefer local (local LLM is faster).
    let lowLatencyPreferred: Bool

    init(
        id: UUID = UUID(),
        content: String,
        privacyLevel: PrivacyLevel,
        intent: Intent? = nil,
        sessionId: UUID,
        toolRequired: Bool = false,
        privacySensitive: Bool = false,
        lowLatencyPreferred: Bool = false
    ) {
        self.id = id
        self.content = content
        self.privacyLevel = privacyLevel
        self.intent = intent
        self.sessionId = sessionId
        self.toolRequired = toolRequired
        self.privacySensitive = privacySensitive
        self.lowLatencyPreferred = lowLatencyPreferred
    }
}
