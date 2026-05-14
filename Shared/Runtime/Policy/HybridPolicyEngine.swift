// NoesisNoema - Hybrid Routing Runtime
// PolicyEngine - Pure evaluation function
// Created: 2026-03-07
// DEPRECATED: 2026-05-15 (Issue #70)
//   HybridPolicyEngine is no longer used in the execution path.
//   Routing signal derivation (toolRequired, privacySensitive, lowLatencyPreferred)
//   is now performed in HybridExecutionCoordinator.buildQuestion(from:) and stored
//   as first-class fields on NoemaQuestion.
//   Policy rule evaluation is now performed by the canonical PolicyEngine
//   (Shared/Policy/PolicyEngine.swift).
//   This file is retained for reference. Do not use in new code.
// License: MIT License

import Foundation

/// - Warning: Deprecated. See file header.
final class HybridPolicyEngine {

    private static let toolKeywords = [
        "calendar", "email", "contacts", "tool", "agent",
        "schedule", "meeting", "appointment", "remind", "notification"
    ]

    private static let privacyKeywords = [
        "address", "phone", "email", "passport", "personal",
        "ssn", "social security", "credit card", "password",
        "bank", "account", "salary", "medical", "health"
    ]

    @available(*, deprecated, message: "Use PolicyEngine.evaluate(question:runtimeState:rules:) instead.")
    func evaluate(_ request: NoemaRequest) -> PolicyResult {
        let query = request.query.lowercased()
        let toolRequired = Self.toolKeywords.contains { query.contains($0) }
        let privacySensitive = Self.privacyKeywords.contains { query.contains($0) }
        let lowLatencyPreferred = query.count < 100
        return PolicyResult(
            toolRequired: toolRequired,
            privacySensitive: privacySensitive,
            lowLatencyPreferred: lowLatencyPreferred
        )
    }
}
