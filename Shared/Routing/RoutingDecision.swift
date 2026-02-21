// NoesisNoema is a knowledge graph framework for building AI applications.
// This file defines the RoutingDecision struct for routing decisions.
// EPIC1: Client Authority Hardening (Phase 2)
// Created: 2026-02-21
// License: MIT License

import Foundation

/// Execution route target
enum ExecutionRoute: String, Codable, Equatable {
    case local = "local"
    case cloud = "cloud"
}

/// The routing decision produced by the Router
/// This explicitly states how execution should proceed
struct RoutingDecision: Equatable {
    /// Where execution should happen (local, cloud, or blocked)
    let routeTarget: ExecutionRoute

    /// Explicit model identifier (e.g., "llama-3.2-8b", "gpt-4")
    let model: String

    /// Human-readable explanation of the routing decision
    let reason: String

    /// Which routing rule was applied
    let ruleId: RoutingRuleId

    /// Can fallback to cloud if local execution fails?
    let fallbackAllowed: Bool

    /// Whether user confirmation is required before execution
    let requiresConfirmation: Bool

    /// Confidence level (always 1.0 for deterministic routing)
    let confidence: Double

    init(
        routeTarget: ExecutionRoute,
        model: String,
        reason: String,
        ruleId: RoutingRuleId,
        fallbackAllowed: Bool,
        requiresConfirmation: Bool = false,
        confidence: Double = 1.0
    ) {
        self.routeTarget = routeTarget
        self.model = model
        self.reason = reason
        self.ruleId = ruleId
        self.fallbackAllowed = fallbackAllowed
        self.requiresConfirmation = requiresConfirmation
        self.confidence = confidence
    }
}
