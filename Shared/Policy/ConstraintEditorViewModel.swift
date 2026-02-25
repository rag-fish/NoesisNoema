//
//  ConstraintEditorViewModel.swift
//  NoesisNoema
//
//  Created for EPIC1 Phase 4-B
//  Purpose: Business logic for constraint editor
//  License: MIT License
//

import Foundation
import SwiftUI

/// Validation errors for policy constraints
enum ConstraintValidationError: Error, Identifiable {
    case emptyName(constraintId: UUID)
    case noConditions(constraintId: UUID)
    case blockWithoutReason(constraintId: UUID)
    case confirmationWithoutPrompt(constraintId: UUID)
    case warnWithoutMessage(constraintId: UUID)

    var id: String {
        switch self {
        case .emptyName(let id): return "emptyName-\(id)"
        case .noConditions(let id): return "noConditions-\(id)"
        case .blockWithoutReason(let id): return "blockWithoutReason-\(id)"
        case .confirmationWithoutPrompt(let id): return "confirmationWithoutPrompt-\(id)"
        case .warnWithoutMessage(let id): return "warnWithoutMessage-\(id)"
        }
    }

    var message: String {
        switch self {
        case .emptyName: return "Constraint name cannot be empty"
        case .noConditions: return "At least one condition is required"
        case .blockWithoutReason: return "Block action requires a reason"
        case .confirmationWithoutPrompt: return "Confirmation action requires a prompt"
        case .warnWithoutMessage: return "Warning action requires a message"
        }
    }
}

/// ViewModel for constraint editor
/// Manages constraint list and editor state
@MainActor
class ConstraintEditorViewModel: ObservableObject {

    // MARK: - Published State

    @Published var constraints: [EditablePolicyRule] = []
    @Published var selectedConstraintId: UUID? = nil
    @Published var validationErrors: [ConstraintValidationError] = []
    @Published var isSaving: Bool = false
    @Published var saveError: Error? = nil
    @Published var showRestartNotice: Bool = false

    // MARK: - Dependencies

    private let constraintStore: ConstraintStore

    // MARK: - Initialization

    init(constraintStore: ConstraintStore = ConstraintStore.shared) {
        self.constraintStore = constraintStore
        loadConstraints()
    }

    // MARK: - Load/Save

    func loadConstraints() {
        do {
            let policyRules = try constraintStore.load()
            self.constraints = policyRules.map { EditablePolicyRule(from: $0) }
            print("📋 Loaded \(constraints.count) constraints for editing")
        } catch {
            print("⚠️ Failed to load constraints: \(error)")
            self.constraints = []
        }
    }

    func saveConstraints() {
        isSaving = true
        saveError = nil
        validationErrors = []

        // Validate all constraints
        validationErrors = validateAll()
        guard validationErrors.isEmpty else {
            isSaving = false
            return
        }

        // Convert to PolicyRule
        let policyRules = constraints.map { $0.toPolicyRule() }

        // Persist to JSON
        do {
            try constraintStore.save(policyRules)
            isSaving = false
            showRestartNotice = true  // Show restart prompt
        } catch {
            saveError = error
            isSaving = false
        }
    }

    // MARK: - CRUD Operations

    func addConstraint() {
        let maxPriority = constraints.map { $0.priority }.max() ?? 0
        let newConstraint = EditablePolicyRule(
            name: "New Constraint",
            priority: maxPriority + 1,
            conditions: [EditableConditionRule()]
        )
        constraints.append(newConstraint)
        selectedConstraintId = newConstraint.id
    }

    func deleteConstraint(id: UUID) {
        constraints.removeAll { $0.id == id }
        if selectedConstraintId == id {
            selectedConstraintId = nil
        }
    }

    func toggleConstraint(id: UUID) {
        if let index = constraints.firstIndex(where: { $0.id == id }) {
            constraints[index].enabled.toggle()
        }
    }

    // MARK: - Validation

    func validateAll() -> [ConstraintValidationError] {
        var errors: [ConstraintValidationError] = []

        for constraint in constraints {
            // Name cannot be empty
            if constraint.name.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append(.emptyName(constraintId: constraint.id))
            }

            // Must have at least one condition
            if constraint.conditions.isEmpty {
                errors.append(.noConditions(constraintId: constraint.id))
            }

            // Action must be valid
            switch constraint.action {
            case .block(let reason):
                if reason.trimmingCharacters(in: .whitespaces).isEmpty {
                    errors.append(.blockWithoutReason(constraintId: constraint.id))
                }
            case .requireConfirmation(let prompt):
                if prompt.trimmingCharacters(in: .whitespaces).isEmpty {
                    errors.append(.confirmationWithoutPrompt(constraintId: constraint.id))
                }
            case .warn(let message):
                if message.trimmingCharacters(in: .whitespaces).isEmpty {
                    errors.append(.warnWithoutMessage(constraintId: constraint.id))
                }
            default:
                break
            }
        }

        return errors
    }
}
