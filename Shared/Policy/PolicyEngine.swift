// NoesisNoema is a knowledge graph framework for building AI applications.
// This file implements the deterministic Policy Engine as a pure function.
// EPIC1: Client Authority Hardening (Phase 3) - Section 3.7
// Created: 2026-02-21
// License: MIT License

import Foundation

/// Deterministic Policy Engine - Pure Function Implementation
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
/// Step 3: Evaluate conditions and collect matching constraints
/// Step 4: Apply conflict resolution with precedence hierarchy
///
/// Precedence Hierarchy (Section 3.7):
/// BLOCK > FORCE_LOCAL > FORCE_CLOUD > REQUIRE_CONFIRMATION > WARN
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

        // STEP 3: Evaluate conditions and collect matching constraints
        var matchedRules: [PolicyRule] = []
        for rule in sortedRules {
            if evaluateConditions(rule.conditions, question: question, runtimeState: runtimeState) {
                matchedRules.append(rule)
            }
        }

        // STEP 4: Apply conflict resolution
        return try resolveConflicts(matchedRules: matchedRules)
    }

    // MARK: - Private Pure Functions

    /// Evaluate all conditions for a constraint (AND logic)
    /// - Parameters:
    ///   - conditions: List of conditions to evaluate
    ///   - question: The question being evaluated
    ///   - runtimeState: Current runtime state
    /// - Returns: True if all conditions match, false otherwise
    private static func evaluateConditions(
        _ conditions: [ConditionRule],
        question: NoemaQuestion,
        runtimeState: RuntimeState
    ) -> Bool {
        // All conditions must be true (AND logic)
        return conditions.allSatisfy { condition in
            evaluateCondition(condition, question: question, runtimeState: runtimeState)
        }
    }

    /// Evaluate a single condition
    /// - Parameters:
    ///   - condition: The condition to evaluate
    ///   - question: The question being evaluated
    ///   - runtimeState: Current runtime state
    /// - Returns: True if condition matches, false otherwise
    private static func evaluateCondition(
        _ condition: ConditionRule,
        question: NoemaQuestion,
        runtimeState: RuntimeState
    ) -> Bool {
        switch condition.field {
        case "content":
            return evaluateStringCondition(condition, value: question.content)

        case "token_count":
            let tokenCount = estimateTokenCount(question.content)
            return evaluateNumericCondition(condition, value: tokenCount)

        case "intent":
            guard let intent = question.intent else { return false }
            return evaluateStringCondition(condition, value: intent.rawValue)

        case "privacy_level":
            return evaluateStringCondition(condition, value: question.privacyLevel.rawValue)

        default:
            // Unknown field - condition does not match
            return false
        }
    }

    /// Evaluate string-based condition
    /// - Parameters:
    ///   - condition: The condition with operator
    ///   - value: The string value to test
    /// - Returns: True if condition matches
    private static func evaluateStringCondition(
        _ condition: ConditionRule,
        value: String
    ) -> Bool {
        let conditionValue = condition.value.lowercased()
        let testValue = value.lowercased()

        switch condition.operator {
        case .contains:
            // Support pipe-separated OR patterns (e.g., "SSN|credit card|password")
            let patterns = conditionValue.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
            return patterns.contains { testValue.contains($0) }

        case .notContains:
            let patterns = conditionValue.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
            return !patterns.contains { testValue.contains($0) }

        case .equals:
            return testValue == conditionValue

        case .notEquals:
            return testValue != conditionValue

        default:
            return false
        }
    }

    /// Evaluate numeric-based condition
    /// - Parameters:
    ///   - condition: The condition with operator
    ///   - value: The numeric value to test
    /// - Returns: True if condition matches
    private static func evaluateNumericCondition(
        _ condition: ConditionRule,
        value: Int
    ) -> Bool {
        guard let conditionValue = Int(condition.value) else {
            return false
        }

        switch condition.operator {
        case .exceeds:
            return value > conditionValue

        case .lessThan:
            return value < conditionValue

        case .equals:
            return value == conditionValue

        case .notEquals:
            return value != conditionValue

        default:
            return false
        }
    }

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

    /// Estimate token count from text content
    /// This is a deterministic approximation (4 chars ≈ 1 token)
    /// - Parameter content: The text content
    /// - Returns: Estimated token count
    private static func estimateTokenCount(_ content: String) -> Int {
        // Simple deterministic estimation: ~4 characters per token
        // This matches typical tokenization ratios for English text
        return max(1, content.count / 4)
    }
}
