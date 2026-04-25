//
//  StringMatcher.swift
//  NoesisNoema
//
//  Phase 1 of EPIC4 #68. Operator strategy for string-typed conditions.
//  See docs/EPIC4_Policy_Engine_Extensibility_Design.md (section 4.2).
//
//  Semantics are kept strictly identical to the current
//  PolicyEngine.evaluateStringCondition implementation. In particular,
//  empty pattern alternatives are NOT filtered out, because the current
//  implementation does not filter them either, and Swift's
//  `String.contains("")` is `true`. Phase 1 commits to no behavioural
//  change.
//
//  License: MIT License
//

import Foundation

/// Value-typed comparison strategy for string-valued conditions.
///
/// Encapsulates the four current string operators. Adding a new mode
/// (regex, fuzzyMatch, etc.) is a strategy-level change; condition
/// types and `PolicyEngine` do not need to be touched.
///
/// `pattern` may contain pipe-separated alternatives (for example,
/// `"SSN|password|credit card"`); a `.contains` match returns `true`
/// when the candidate contains any alternative. This preserves the
/// semantics of the current `PolicyEngine.evaluateStringCondition`
/// implementation byte-for-byte.
struct StringMatcher {

    enum Mode {
        case contains
        case notContains
        case equals
        case notEquals
    }

    let mode: Mode

    /// Apply the strategy.
    /// - Parameters:
    ///   - candidate: The runtime value being checked.
    ///   - pattern: The pattern from the rule, possibly pipe-separated.
    /// - Returns: `true` if the candidate matches under this mode.
    func matches(_ candidate: String, against pattern: String) -> Bool {
        // Lowercase the whole pattern first, then split. This matches
        // the current PolicyEngine implementation exactly. Do NOT
        // filter empty alternatives; Swift's `String.contains("")` is
        // `true` and the current behaviour relies on that.
        let conditionValue = pattern.lowercased()
        let testValue = candidate.lowercased()
        let patterns = conditionValue
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        switch mode {
        case .contains:
            return patterns.contains { testValue.contains($0) }

        case .notContains:
            return !patterns.contains { testValue.contains($0) }

        case .equals:
            return testValue == conditionValue

        case .notEquals:
            return testValue != conditionValue
        }
    }
}
