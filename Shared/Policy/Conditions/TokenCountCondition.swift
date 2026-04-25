//
//  TokenCountCondition.swift
//  NoesisNoema
//
//  Phase 1 of EPIC4 #68. Concrete ConditionEvaluator for an estimated
//  token count of `NoemaQuestion.content`. Mirrors the `case "token_count":`
//  branch of the current PolicyEngine.evaluateCondition.
//
//  License: MIT License
//

import Foundation

/// Evaluates a numeric comparison against the estimated token count of
/// `NoemaQuestion.content`.
///
/// Token estimation uses the same deterministic approximation as the
/// current PolicyEngine: `max(1, content.count / 4)`. Comparison
/// semantics are delegated to `NumericComparator`.
struct TokenCountCondition: ConditionEvaluator {

    let comparator: NumericComparator
    let threshold: Int

    func evaluate(
        question: NoemaQuestion,
        runtimeState: RuntimeState
    ) -> Bool {
        let count = Self.estimateTokenCount(question.content)
        return comparator.matches(count, against: threshold)
    }

    /// Deterministic token estimation: ~4 characters per token, with a
    /// floor of 1. Identical to PolicyEngine.estimateTokenCount.
    static func estimateTokenCount(_ content: String) -> Int {
        max(1, content.count / 4)
    }
}
