//
//  PolicyRulesProvider.swift
//  NoesisNoema
//
//  Purpose: Dependency injection for policy rules
//  License: MIT License
//

import Foundation

/// Protocol for providing policy rules to execution components
/// Enables dependency injection and testability
protocol PolicyRulesProvider {
    /// Returns the current set of policy rules synchronously.
    /// - Returns: Array of policy rules (immutable value copies)
    func getPolicyRules() -> [PolicyRule]

    /// Returns the current set of policy rules, awaited.
    ///
    /// The hybrid runtime coordinator (`HybridExecutionCoordinator`) is not
    /// MainActor-isolated and loads rules off the main thread. The default
    /// implementation bridges to `getPolicyRules()`; conformers backed by
    /// genuinely asynchronous storage may override it.
    func loadRules() async -> [PolicyRule]
}

extension PolicyRulesProvider {
    func loadRules() async -> [PolicyRule] {
        getPolicyRules()
    }
}

/// Default policy rules provider for the hybrid runtime.
///
/// A value type — implicitly `Sendable` and free of actor isolation — so it can
/// be constructed and read off the MainActor by `HybridExecutionCoordinator`.
/// Unlike `PolicyRulesStore` it performs no eager I/O at init: rules are read
/// from the shared `ConstraintStore` on each call.
struct DefaultPolicyRulesProvider: PolicyRulesProvider {
    func getPolicyRules() -> [PolicyRule] {
        do {
            return try ConstraintStore.shared.load()
        } catch {
            // Graceful degradation — consistent with PolicyRulesStore.
            // This is not an executor fallback: ADR-0000's no-silent-fallback
            // rule governs routing/execution, not the optional policy rule set.
            // An absent rule set means PolicyEngine evaluates with defaults.
            print("⚠️ DefaultPolicyRulesProvider: failed to load rules: \(error)")
            return []
        }
    }
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

    // MARK: - Future Hook

    /// Called by ConstraintEditor after saving new rules
    /// Currently no-op (requires app restart to apply changes)
    /// Future: Will reload cachedRules and notify observers
    func notifyRulesUpdated() {
        // No-op for now
        // Restart required to apply constraint changes
    }
}
