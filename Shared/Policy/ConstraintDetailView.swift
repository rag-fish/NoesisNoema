//
//  ConstraintDetailView.swift
//  NoesisNoema
//
//  Created for EPIC1 Phase 4-B
//  Purpose: Detail editor for individual constraints (modal sheet)
//  License: MIT License
//

import SwiftUI

/// Detail view for editing a single constraint (modal sheet)
struct ConstraintDetailView: View {
    @Binding var constraint: EditablePolicyRule
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            Form {
                // Basic Info Section
                Section("Basic Info") {
                    TextField("Name", text: $constraint.name)

                    Picker("Type", selection: $constraint.type) {
                        Text("Privacy").tag(ConstraintType.privacy)
                        Text("Cost").tag(ConstraintType.cost)
                        Text("Performance").tag(ConstraintType.performance)
                        Text("Intent").tag(ConstraintType.intent)
                    }

                    HStack {
                        Text("Priority")
                        Spacer()
                        TextField("Priority", value: $constraint.priority, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Toggle("Enabled", isOn: $constraint.enabled)
                }

                // Conditions Section
                Section("Conditions (All must match)") {
                    ForEach($constraint.conditions) { $condition in
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Field", selection: $condition.field) {
                                Text("content").tag("content")
                                Text("token_count").tag("token_count")
                                Text("intent").tag("intent")
                                Text("privacy_level").tag("privacy_level")
                            }

                            Picker("Operator", selection: $condition.operator) {
                                Text("contains").tag(Operator.contains)
                                Text("not contains").tag(Operator.notContains)
                                Text("equals").tag(Operator.equals)
                                Text("not equals").tag(Operator.notEquals)
                                Text("exceeds").tag(Operator.exceeds)
                                Text("less than").tag(Operator.lessThan)
                            }

                            TextField("Value", text: $condition.value)

                            Button(action: {
                                constraint.conditions.removeAll { $0.id == condition.id }
                            }) {
                                Label("Remove Condition", systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button(action: {
                        constraint.conditions.append(EditableConditionRule())
                    }) {
                        Label("Add Condition", systemImage: "plus")
                    }
                }

                // Action Section
                Section("Action") {
                    Picker("Action Type", selection: actionTypeBinding) {
                        Text("Force Local").tag("forceLocal")
                        Text("Force Cloud").tag("forceCloud")
                        Text("Block").tag("block")
                        Text("Require Confirmation").tag("confirm")
                        Text("Warn").tag("warn")
                    }
                    .onChange(of: actionTypeBinding.wrappedValue) { newValue in
                        updateActionFromType(newValue)
                    }

                    // Conditional fields based on action type
                    if case .block = constraint.action {
                        TextField("Reason", text: blockReasonBinding)
                    }

                    if case .requireConfirmation = constraint.action {
                        TextField("Prompt", text: confirmationPromptBinding)
                    }

                    if case .warn = constraint.action {
                        TextField("Message", text: warnMessageBinding)
                    }
                }
            }
            .navigationTitle("Edit Constraint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                }
            }
        }
    }

    // MARK: - Helpers for action type binding

    private var actionTypeBinding: Binding<String> {
        Binding(
            get: {
                switch constraint.action {
                case .forceLocal: return "forceLocal"
                case .forceCloud: return "forceCloud"
                case .block: return "block"
                case .requireConfirmation: return "confirm"
                case .warn: return "warn"
                }
            },
            set: { _ in }  // Handled by onChange
        )
    }

    private func updateActionFromType(_ type: String) {
        switch type {
        case "forceLocal":
            constraint.action = .forceLocal
        case "forceCloud":
            constraint.action = .forceCloud
        case "block":
            constraint.action = .block(reason: "")
        case "confirm":
            constraint.action = .requireConfirmation(prompt: "")
        case "warn":
            constraint.action = .warn(message: "")
        default:
            break
        }
    }

    private var blockReasonBinding: Binding<String> {
        Binding(
            get: {
                if case .block(let reason) = constraint.action {
                    return reason
                }
                return ""
            },
            set: { newValue in
                constraint.action = .block(reason: newValue)
            }
        )
    }

    private var confirmationPromptBinding: Binding<String> {
        Binding(
            get: {
                if case .requireConfirmation(let prompt) = constraint.action {
                    return prompt
                }
                return ""
            },
            set: { newValue in
                constraint.action = .requireConfirmation(prompt: newValue)
            }
        )
    }

    private var warnMessageBinding: Binding<String> {
        Binding(
            get: {
                if case .warn(let message) = constraint.action {
                    return message
                }
                return ""
            },
            set: { newValue in
                constraint.action = .warn(message: newValue)
            }
        )
    }
}
