//
//  ContentCondition.swift
//  NoesisNoema
//
//  Phase 1 of EPIC4 #68. Concrete ConditionEvaluator for the question's
//  text content. Mirrors the `case "content":` branch of the current
//  PolicyEngine.evaluateCondition.
//
//  License: MIT License
//

import Foundation

/// Evaluates a string match against `NoemaQuestion.content`.
///
/// Equivalent to the current PolicyEngine behaviour for
/// `condition.field == "content"`. Pattern semantics (lowercased,
/// pipe-separated alternatives) are delegated to `StringMatcher`.
struct ContentCondition: ConditionEvaluator {

    let matcher: StringMatcher
    let pattern: String

    func evaluate(
        question: NoemaQuestion,
        runtimeState: RuntimeState
    ) -> Bool {
        matcher.matches(question.content, against: pattern)
    }
}
