// NoesisNoema is a knowledge graph framework for building AI applications.
// This file implements the deterministic Policy Engine as a pure function.
// Created: 2026-02-21
// Phase 2 of EPIC4 #68: PolicyEngine reduced to a pure orchestrator.
//   - STEP 3 now delegates per-rule evaluation to PolicyRule.evaluate(...).
//   - The legacy switch-chain (evaluateConditions / evaluateCondition /
//     evaluateStringCondition / evaluateNumericCondition / estimateTokenCount)
//     has been removed. Its responsibilities now live in
//     Shared/Policy/Conditions/* and Shared/Policy/Operators/*, behind the
//     ConditionEvaluator protocol.
// License: MIT License

import Foundation

/// Deterministic Policy Engine - Pure Orchestrator
///
/// Purity Contract:
/// 1. Deterministic: Same inputs → same outputs (always)
/// 2. Side-effect free: No I/O, no logging, no global state mutation
/// 3. Free of randomness: No probabilistic branching
/// 4. Free of time-based branching: No Date.now() comparisons
///
/// Evaluation Order (Section 3.7):
/// Step 1: Filter enabled constraints
/// Step 2: Sort by (priority, id) for deterministic ordering
/// Step 3: Evaluate each rule via PolicyRule.evaluate(...) and collect matches
/// Step 4: Apply conflict resolution with precedence hierarchy
///
/// Precedence Hierarchy (Section 3.7):
/// BLOCK > FORCE_LOCAL > FORCE_CLOUD > REQUIRE_CONFIRMATION > WARN
///
/// Extensibility (EPIC4 #68):
/// New condition kinds and new operators are added by introducing new
/// `ConditionEvaluator`-conforming structs and new operator strategy
/// structs respectively. PolicyEngine itself is not modified for those
/// additions; it operates uniformly on whatever evaluators a PolicyRule
/// resolves to.
struct PolicyEngine {

    /// Evaluate policy constraints against a question
    /// - Parameters:
    ///   - question: The user's question to evaluate
    ///   - runtimeState: Current runtime state
    ///   - rules: List of policy rules to evaluate
    /// - Returns: Policy evaluation result with effective action
    /// - Throws: RoutingError.policyViolation if a BLOCK action is triggered
    static func evaluate(
        question: NoemaQuestion,
        runtimeState: RuntimeState,
        rules: [PolicyRule]
    ) throws -> PolicyEvaluationResult {

        // STEP 1: Filter enabled constraints
        let activeRules = rules.filter { $0.enabled }

        // STEP 2: Sort by (priority, id) for deterministic ordering
        let sortedRules = activeRules.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority  // Lower priority number first
            } else {
                return lhs.id.uuidString < rhs.id.uuidString  // Stable UUID ordering
            }
        }

        // STEP 3: Evaluate conditions and collect matching constraints.
        // Per-rule evaluation is owned by PolicyRule itself (Phase 1
        // introduced `PolicyRule.evaluate(question:runtimeState:)`).
        // PolicyEngine no longer inspects the shape of any condition.
        var matchedRules: [PolicyRule] = []
        for rule in sortedRules {
            if rule.evaluate(question: question, runtimeState: runtimeState) {
                matchedRules.append(rule)
            }
        }

        // STEP 4: Apply conflict resolution
        return try resolveConflicts(matchedRules: matchedRules)
    }

    // MARK: - Private Pure Functions

    /// Resolve conflicts between multiple matching constraints
    /// Applies precedence hierarchy: BLOCK > FORCE_LOCAL > FORCE_CLOUD > REQUIRE_CONFIRMATION > WARN
    /// - Parameter matchedRules: List of constraints that matched
    /// - Returns: Policy evaluation result with effective action
    /// - Throws: RoutingError.policyViolation if BLOCK action is triggered
    private static func resolveConflicts(matchedRules: [PolicyRule]) throws -> PolicyEvaluationResult {
        var effectiveAction: PolicyAction? = nil
        var appliedConstraintIds: [UUID] = []
        var warnings: [String] = []
        var confirmationPrompts: [String] = []

        for rule in matchedRules {
            appliedConstraintIds.append(rule.id)

            switch rule.action {
            case .block(let reason):
                // BLOCK has highest precedence; throw immediately
                throw RoutingError.policyViolation(reason: reason)

            case .forceLocal:
                // Force local unless forceCloud has already been set
                // forceLocal wins in conflicts (privacy-first principle)
                if effectiveAction == nil || effectiveAction == .forceCloud {
                    effectiveAction = .forceLocal
                }

            case .forceCloud:
                // Force cloud only if no route has been forced yet
                if effectiveAction == nil {
                    effectiveAction = .forceCloud
                }
                // If forceLocal was already set, forceLocal wins (no-op here)

            case .requireConfirmation(let prompt):
                confirmationPrompts.append(prompt)

            case .warn(let message):
                warnings.append(message)
            }
        }

        // Determine if confirmation is required
        let requiresConfirmation = !confirmationPrompts.isEmpty

        return PolicyEvaluationResult(
            effectiveAction: effectiveAction ?? .allow,
            appliedConstraints: appliedConstraintIds,
            warnings: warnings,
            requiresConfirmation: requiresConfirmation
        )
    }
}
