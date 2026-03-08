// NoesisNoema - Hybrid Routing Runtime
// PolicyEngine - Pure evaluation function
// Created: 2026-03-07
// License: MIT License

import Foundation

/// Deterministic Policy Engine
///
/// Constitutional Constraints (ADR-0000):
/// 1. MUST be side-effect free (no I/O, no logging, no state mutation)
/// 2. MUST be deterministic (same input → same output)
/// 3. MUST NOT contain randomness or time-based branching
/// 4. MUST NOT make routing decisions (only evaluates signals)
///
/// Analyzes a NoemaRequest and returns PolicyResult.
/// Evaluates whether the request requires tools, contains sensitive data,
/// or prefers low latency. These are signals for the Router, not decisions.
final class HybridPolicyEngine {

    /// Tool-related keywords that suggest tool/function calling is needed
    private static let toolKeywords = [
        "calendar", "email", "contacts", "tool", "agent",
        "schedule", "meeting", "appointment", "remind", "notification"
    ]

    /// Privacy-sensitive keywords that indicate PII or sensitive data
    private static let privacyKeywords = [
        "address", "phone", "email", "passport", "personal",
        "ssn", "social security", "credit card", "password",
        "bank", "account", "salary", "medical", "health"
    ]

    /// Evaluate policy signals for a given request
    ///
    /// This is a pure function with zero side effects.
    /// - Parameter request: The NoemaRequest to evaluate
    /// - Returns: PolicyResult containing routing signals
    func evaluate(_ request: NoemaRequest) -> PolicyResult {
        let query = request.query.lowercased()

        // Signal 1: Does request require tool/function calling?
        let toolRequired = Self.toolKeywords.contains { keyword in
            query.contains(keyword)
        }

        // Signal 2: Does request contain privacy-sensitive information?
        let privacySensitive = Self.privacyKeywords.contains { keyword in
            query.contains(keyword)
        }

        // Signal 3: Is low-latency preferred? (simple heuristic: short query)
        let lowLatencyPreferred = query.count < 100

        return PolicyResult(
            toolRequired: toolRequired,
            privacySensitive: privacySensitive,
            lowLatencyPreferred: lowLatencyPreferred
        )
    }
}
