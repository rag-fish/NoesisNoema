//
//  ConditionRule+ToEvaluator.swift
//  NoesisNoema
//
//  Phase 1 of EPIC4 #68. Adapter that lifts the existing ConditionRule
//  (string-keyed data) to a concrete ConditionEvaluator (typed struct).
//
//  This adapter is the single field-name dispatch point for Phase 1.
//  The current PolicyEngine.evaluateCondition switch is replicated
//  here in spirit, but each branch now produces an evaluator instead
//  of a Bool. Phase 2 deletes the engine-side switch; Phase 3 replaces
//  this adapter when the storage representation changes.
//
//  License: MIT License
//

import Foundation

extension ConditionRule {

    /// Convert a serialized ConditionRule into its concrete evaluator.
    ///
    /// Returns `nil` for fields the current PolicyEngine treats as
    /// "unknown field — does not match" (the `default: return false`
    /// branch). The caller can then drop the condition or force the
    /// rule to non-match, matching current semantics.
    ///
    /// For `token_count`, the operator must be a numeric one
    /// (exceeds / lessThan / equals / notEquals). String operators
    /// (contains / notContains) on `token_count` produce `nil`,
    /// matching the `default: return false` behaviour of the current
    /// evaluateNumericCondition.
    ///
    /// Conversely, string fields (content / intent / privacy_level)
    /// with numeric operators (exceeds / lessThan) produce `nil`,
    /// matching evaluateStringCondition's `default: return false`.
    func toEvaluator() -> ConditionEvaluator? {
        switch field {
        case "content":
            guard let mode = stringMode(from: `operator`) else { return nil }
            return ContentCondition(
                matcher: StringMatcher(mode: mode),
                pattern: value
            )

        case "token_count":
            guard let mode = numericMode(from: `operator`) else { return nil }
            guard let threshold = Int(value) else { return nil }
            return TokenCountCondition(
                comparator: NumericComparator(mode: mode),
                threshold: threshold
            )

        case "intent":
            guard let mode = stringMode(from: `operator`) else { return nil }
            return IntentCondition(
                matcher: StringMatcher(mode: mode),
                pattern: value
            )

        case "privacy_level":
            guard let mode = stringMode(from: `operator`) else { return nil }
            return PrivacyLevelCondition(
                matcher: StringMatcher(mode: mode),
                pattern: value
            )

        default:
            // Unknown field — current PolicyEngine returns false here.
            // The caller represents this as "no evaluator", which the
            // PolicyRule.evaluate() helper treats as a non-match.
            return nil
        }
    }

    private func stringMode(from op: Operator) -> StringMatcher.Mode? {
        switch op {
        case .contains:    return .contains
        case .notContains: return .notContains
        case .equals:      return .equals
        case .notEquals:   return .notEquals
        case .exceeds, .lessThan:
            // Numeric operators on string fields: current
            // evaluateStringCondition returns false (default branch).
            return nil
        }
    }

    private func numericMode(from op: Operator) -> NumericComparator.Mode? {
        switch op {
        case .exceeds:     return .exceeds
        case .lessThan:    return .lessThan
        case .equals:      return .equals
        case .notEquals:   return .notEquals
        case .contains, .notContains:
            // String operators on numeric fields: current
            // evaluateNumericCondition returns false (default branch).
            return nil
        }
    }
}
