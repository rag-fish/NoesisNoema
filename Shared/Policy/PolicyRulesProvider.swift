//
//  PolicyRulesProvider.swift
//  NoesisNoema
//
//  Created for EPIC1 Phase 4-B
//  Purpose: Dependency injection for policy rules
//  License: MIT License
//

import Foundation

/// Protocol for providing policy rules to execution components
/// Enables dependency injection and testability
protocol PolicyRulesProvider {
    /// Returns the current set of policy rules
    /// - Returns: Array of policy rules (immutable copies)
    func getPolicyRules() -> [PolicyRule]
}

/// Concrete implementation that loads rules from ConstraintStore
/// Rules are loaded once at initialization and cached immutably
@MainActor
final class PolicyRulesStore: PolicyRulesProvider {

    // MARK: - Private Properties

    private let constraintStore: ConstraintStore
    private var cachedRules: [PolicyRule] = []

    // MARK: - Initialization

    /// Initialize with constraint store
    /// - Parameter constraintStore: The store to load rules from (defaults to shared instance)
    init(constraintStore: ConstraintStore = .shared) {
        self.constraintStore = constraintStore
        self.loadRules()
    }

    // MARK: - PolicyRulesProvider

    func getPolicyRules() -> [PolicyRule] {
        // Return cached rules (value types, so returns copies)
        return cachedRules
    }

    // MARK: - Private Methods

    /// Load rules once at initialization
    /// Errors are logged but do not crash the app (graceful degradation)
    private func loadRules() {
        do {
            self.cachedRules = try constraintStore.load()
            print("✅ Loaded \(cachedRules.count) policy rules")
        } catch {
            print("⚠️ Failed to load policy rules: \(error)")
            print("⚠️ Continuing with empty rules (graceful degradation)")
            self.cachedRules = []
        }
    }

    // MARK: - Future Hook (Phase 5)

    /// Called by ConstraintEditor after saving new rules
    /// Phase 4: No-op (requires app restart to apply changes)
    /// Phase 5: Will reload cachedRules and notify observers
    func notifyRulesUpdated() {
        // No-op in Phase 4
        // Restart required to apply constraint changes
    }
}
