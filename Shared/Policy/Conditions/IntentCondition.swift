//
//  IntentCondition.swift
//  NoesisNoema
//
//  Phase 1 of EPIC4 #68. Concrete ConditionEvaluator for the question's
//  intent classification. Mirrors the `case "intent":` branch of the
//  current PolicyEngine.evaluateCondition.
//
//  License: MIT License
//

import Foundation

/// Evaluates a string match against `NoemaQuestion.intent.rawValue`.
///
/// `NoemaQuestion.intent` is optional. When the intent has not been
/// classified for this question, the condition does not match. This
/// preserves the current PolicyEngine behaviour exactly:
///
///     guard let intent = question.intent else { return false }
struct IntentCondition: ConditionEvaluator {

    let matcher: StringMatcher
    let pattern: String

    func evaluate(
        question: NoemaQuestion,
        runtimeState: RuntimeState
    ) -> Bool {
        guard let intent = question.intent else { return false }
        return matcher.matches(intent.rawValue, against: pattern)
    }
}
