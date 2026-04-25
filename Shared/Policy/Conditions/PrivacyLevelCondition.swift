//
//  PrivacyLevelCondition.swift
//  NoesisNoema
//
//  Phase 1 of EPIC4 #68. Concrete ConditionEvaluator for the question's
//  privacy classification. Mirrors the `case "privacy_level":` branch of
//  the current PolicyEngine.evaluateCondition.
//
//  License: MIT License
//

import Foundation

/// Evaluates a string match against `NoemaQuestion.privacyLevel.rawValue`.
///
/// Unlike `IntentCondition`, `privacyLevel` is non-optional on
/// `NoemaQuestion`, so this evaluator always has a value to compare.
struct PrivacyLevelCondition: ConditionEvaluator {

    let matcher: StringMatcher
    let pattern: String

    func evaluate(
        question: NoemaQuestion,
        runtimeState: RuntimeState
    ) -> Bool {
        matcher.matches(question.privacyLevel.rawValue, against: pattern)
    }
}
