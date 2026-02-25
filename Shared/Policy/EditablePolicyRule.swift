//
//  EditablePolicyRule.swift
//  NoesisNoema
//
//  Created for EPIC1 Phase 4-B
//  Purpose: Mutable UI-facing model for policy rule editing
//  License: MIT License
//

import Foundation

/// Mutable version of PolicyRule for UI editing
/// Converts to/from immutable PolicyRule for storage and evaluation
struct EditablePolicyRule: Identifiable {
    var id: UUID
    var name: String
    var type: ConstraintType
    var enabled: Bool
    var priority: Int
    var conditions: [EditableConditionRule]
    var action: EditableConstraintAction

    init(
        id: UUID = UUID(),
        name: String = "",
        type: ConstraintType = .privacy,
        enabled: Bool = true,
        priority: Int = 1,
        conditions: [EditableConditionRule] = [],
        action: EditableConstraintAction = .forceLocal
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.enabled = enabled
        self.priority = priority
        self.conditions = conditions
        self.action = action
    }

    /// Convert to immutable PolicyRule for storage and evaluation
    /// - Throws: Never (validation should be done before calling this)
    /// - Returns: Immutable PolicyRule
    func toPolicyRule() -> PolicyRule {
        let immutableConditions = conditions.map { editableCondition in
            ConditionRule(
                field: editableCondition.field,
                operator: editableCondition.operator,
                value: editableCondition.value
            )
        }

        let immutableAction: ConstraintAction
        switch action {
        case .block(let reason):
            immutableAction = .block(reason: reason)
        case .forceLocal:
            immutableAction = .forceLocal
        case .forceCloud:
            immutableAction = .forceCloud
        case .requireConfirmation(let prompt):
            immutableAction = .requireConfirmation(prompt: prompt)
        case .warn(let message):
            immutableAction = .warn(message: message)
        }

        return PolicyRule(
            id: id,
            name: name,
            type: type,
            enabled: enabled,
            priority: priority,
            conditions: immutableConditions,
            action: immutableAction
        )
    }

    /// Create from immutable PolicyRule
    /// - Parameter policyRule: The immutable policy rule
    init(from policyRule: PolicyRule) {
        self.id = policyRule.id
        self.name = policyRule.name
        self.type = policyRule.type
        self.enabled = policyRule.enabled
        self.priority = policyRule.priority

        self.conditions = policyRule.conditions.map { condition in
            EditableConditionRule(
                field: condition.field,
                operator: condition.operator,
                value: condition.value
            )
        }

        switch policyRule.action {
        case .block(let reason):
            self.action = .block(reason: reason)
        case .forceLocal:
            self.action = .forceLocal
        case .forceCloud:
            self.action = .forceCloud
        case .requireConfirmation(let prompt):
            self.action = .requireConfirmation(prompt: prompt)
        case .warn(let message):
            self.action = .warn(message: message)
        }
    }
}

/// Mutable version of ConditionRule
struct EditableConditionRule: Identifiable {
    var id: UUID = UUID()
    var field: String
    var `operator`: Operator
    var value: String

    init(field: String = "content", operator: Operator = .contains, value: String = "") {
        self.field = field
        self.operator = `operator`
        self.value = value
    }
}

/// Mutable version of ConstraintAction (mirrors ConstraintAction)
enum EditableConstraintAction: Equatable {
    case block(reason: String)
    case forceLocal
    case forceCloud
    case requireConfirmation(prompt: String)
    case warn(message: String)
}
