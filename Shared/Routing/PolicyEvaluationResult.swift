// NoesisNoema is a knowledge graph framework for building AI applications.
// This file defines the PolicyEvaluationResult struct (stub for EPIC1 Phase 2).
// EPIC1: Client Authority Hardening (Phase 2)
// Created: 2026-02-21
// License: MIT License

import Foundation

/// Policy action determined by Policy Engine
enum PolicyAction: Equatable {
    case allow               // Allow routing to proceed normally
    case block(reason: String)  // Block execution entirely
    case forceLocal          // Force local execution
    case forceCloud          // Force cloud execution
}

/// Result of policy evaluation
/// NOTE: This is a stub for Phase 2. Full Policy Engine implementation in Phase 3.
struct PolicyEvaluationResult: Equatable {
    /// The effective action determined by policy evaluation
    let effectiveAction: PolicyAction

    /// IDs of constraints that were applied
    let appliedConstraints: [UUID]

    /// Warning messages (non-blocking)
    let warnings: [String]

    /// Whether user confirmation is required
    let requiresConfirmation: Bool

    init(
        effectiveAction: PolicyAction,
        appliedConstraints: [UUID] = [],
        warnings: [String] = [],
        requiresConfirmation: Bool = false
    ) {
        self.effectiveAction = effectiveAction
        self.appliedConstraints = appliedConstraints
        self.warnings = warnings
        self.requiresConfirmation = requiresConfirmation
    }

    /// Default policy result that allows routing (no constraints)
    static var allowDefault: PolicyEvaluationResult {
        PolicyEvaluationResult(effectiveAction: .allow)
    }
}
