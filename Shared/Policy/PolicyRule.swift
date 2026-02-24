// NoesisNoema is a knowledge graph framework for building AI applications.
// This file defines the PolicyRule (Constraint) model for policy evaluation.
// EPIC1: Client Authority Hardening (Phase 3)
// Created: 2026-02-21
// License: MIT License

import Foundation

/// Type of constraint
enum ConstraintType: String, Codable, Equatable {
    case privacy
    case cost
    case performance
    case intent
}

/// Condition operator for rule evaluation
enum Operator: String, Codable, Equatable {
    case contains
    case notContains
    case exceeds
    case lessThan
    case equals
    case notEquals
}

/// Condition rule for constraint evaluation
struct ConditionRule: Codable, Equatable {
    /// Field to evaluate ("content", "token_count", "intent")
    let field: String

    /// Comparison operator
    let `operator`: Operator

    /// Value to compare against
    let value: String
}

/// Action to take when constraint matches
enum ConstraintAction: Codable, Equatable {
    case block(reason: String)                    // Precedence: 1 (highest)
    case forceLocal                               // Precedence: 2
    case forceCloud                               // Precedence: 3
    case requireConfirmation(prompt: String)      // Precedence: 4
    case warn(message: String)                    // Precedence: 5 (lowest)
}

/// Policy rule (constraint) for evaluation
/// Renamed from Constraint to PolicyRule to avoid naming conflicts
struct PolicyRule: Codable, Identifiable, Equatable {
    /// Stable, unique identifier
    let id: UUID

    /// Human-readable name
    let name: String

    /// Type of constraint
    let type: ConstraintType

    /// Whether this constraint is active
    let enabled: Bool

    /// Evaluation priority (lower number = higher priority)
    let priority: Int

    /// Conditions that must all be true for this constraint to apply
    let conditions: [ConditionRule]

    /// Action to take if conditions match
    let action: ConstraintAction

    init(
        id: UUID = UUID(),
        name: String,
        type: ConstraintType,
        enabled: Bool,
        priority: Int,
        conditions: [ConditionRule],
        action: ConstraintAction
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.enabled = enabled
        self.priority = priority
        self.conditions = conditions
        self.action = action
    }
}
