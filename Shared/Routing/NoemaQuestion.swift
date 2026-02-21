// NoesisNoema is a knowledge graph framework for building AI applications.
// This file defines the NoemaQuestion struct for routing inputs.
// EPIC1: Client Authority Hardening (Phase 2)
// Created: 2026-02-21
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

    init(
        id: UUID = UUID(),
        content: String,
        privacyLevel: PrivacyLevel,
        intent: Intent? = nil,
        sessionId: UUID
    ) {
        self.id = id
        self.content = content
        self.privacyLevel = privacyLevel
        self.intent = intent
        self.sessionId = sessionId
    }
}
