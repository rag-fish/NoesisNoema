//
//  PolicyRule+Evaluate.swift
//  NoesisNoema
//
//  Phase 1 of EPIC4 #68. Adds a non-mutating `evaluate(...)` to PolicyRule
//  so that the rule itself, not PolicyEngine, owns its evaluation.
//
//  The body delegates to ConditionRule.toEvaluator() per condition and
//  ANDs the results, matching the current PolicyEngine.evaluateConditions
//  behaviour byte-for-byte. Phase 2 deletes PolicyEngine's switch chain
//  and routes via this method.
//
//  This file does NOT change PolicyRule's stored properties or its
//  initializers. It only adds a method, so it is safe to land alongside
//  the existing PolicyEngine path.
//
//  License: MIT License
//

import Foundation

extension PolicyRule {

    /// Evaluate this rule against a question and runtime state.
    ///
    /// All conditions must hold (AND logic). A condition that cannot be
    /// converted to a `ConditionEvaluator` (unknown field, mismatched
    /// operator/field combination, non-integer numeric value) is treated
    /// as a non-match — identical to the current PolicyEngine behaviour
    /// where such cases hit `default: return false` in the inner switch.
    ///
    /// - Returns: `true` if every condition holds, `false` otherwise.
    func evaluate(
        question: NoemaQuestion,
        runtimeState: RuntimeState
    ) -> Bool {
        // AND logic: every condition must produce an evaluator AND
        // every evaluator must return true. A nil evaluator (untranslatable
        // condition) short-circuits the rule to non-match, just like the
        // existing engine's `default: return false`.
        for condition in conditions {
            guard let evaluator = condition.toEvaluator() else {
                return false
            }
            if !evaluator.evaluate(question: question, runtimeState: runtimeState) {
                return false
            }
        }
        return true
    }
}
