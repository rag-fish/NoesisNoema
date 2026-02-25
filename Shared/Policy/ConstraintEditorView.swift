//
//  ConstraintEditorView.swift
//  NoesisNoema
//
//  Created for EPIC1 Phase 4-B
//  Purpose: Main UI for constraint editor (simple list)
//  License: MIT License
//

import SwiftUI

/// Constraint Editor main view (MVP: simple list with modal editor)
struct ConstraintEditorView: View {
    @StateObject private var viewModel = ConstraintEditorViewModel()
    @State private var showingEditor: Bool = false
    @State private var editingConstraint: EditablePolicyRule? = nil

    var body: some View {
        NavigationView {
            VStack {
                // Constraint list
                List {
                    ForEach($viewModel.constraints) { $constraint in
                        ConstraintRow(constraint: $constraint) {
                            // Edit action
                            editingConstraint = constraint
                            showingEditor = true
                        } onDelete: {
                            // Delete action
                            viewModel.deleteConstraint(id: constraint.id)
                        } onToggle: {
                            // Toggle enabled
                            viewModel.toggleConstraint(id: constraint.id)
                        }
                    }
                }
                .listStyle(.inset)

                // Validation errors
                if !viewModel.validationErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.validationErrors) { error in
                            Text("⚠️ \(error.message)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                }

                // Save error
                if let error = viewModel.saveError {
                    Text("❌ \(error.localizedDescription)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                }

                // Action buttons
                HStack {
                    Button(action: {
                        editingConstraint = EditablePolicyRule()
                        showingEditor = true
                    }) {
                        Label("New Constraint", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button(action: {
                        viewModel.saveConstraints()
                    }) {
                        if viewModel.isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Label("Save All", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isSaving)
                }
                .padding()
            }
            .navigationTitle("Policy Constraints")
            .sheet(isPresented: $showingEditor) {
                if let constraint = editingConstraint {
                    ConstraintDetailView(
                        constraint: binding(for: constraint),
                        onSave: {
                            if let index = viewModel.constraints.firstIndex(where: { $0.id == constraint.id }) {
                                // Update existing
                                viewModel.constraints[index] = editingConstraint!
                            } else {
                                // Add new
                                viewModel.constraints.append(editingConstraint!)
                            }
                            showingEditor = false
                            editingConstraint = nil
                        },
                        onCancel: {
                            showingEditor = false
                            editingConstraint = nil
                        }
                    )
                }
            }
            .alert("Constraints Saved", isPresented: $viewModel.showRestartNotice) {
                Button("OK") {
                    viewModel.showRestartNotice = false
                }
            } message: {
                Text("Restart the app to apply changes in production execution.")
            }
        }
    }

    // Helper to create binding for editing constraint
    private func binding(for constraint: EditablePolicyRule) -> Binding<EditablePolicyRule> {
        Binding(
            get: { editingConstraint ?? constraint },
            set: { editingConstraint = $0 }
        )
    }
}

/// Constraint row view
struct ConstraintRow: View {
    @Binding var constraint: EditablePolicyRule
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack {
            // Enable/disable toggle
            Toggle("", isOn: .init(
                get: { constraint.enabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(constraint.name)
                    .font(.headline)
                    .foregroundColor(constraint.enabled ? .primary : .secondary)

                HStack {
                    // Type badge
                    Text(constraint.type.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)

                    // Priority
                    Text("Priority: \(constraint.priority)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Condition count
                    Text("\(constraint.conditions.count) condition(s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action buttons
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
