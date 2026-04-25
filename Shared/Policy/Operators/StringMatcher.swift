//
//  StringMatcher.swift
//  NoesisNoema
//
//  Phase 1 of EPIC4 #68. Operator strategy for string-typed conditions.
//  See docs/EPIC4_Policy_Engine_Extensibility_Design.md (section 4.2).
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
/// when the candidate contains any of the alternatives. This preserves
/// the semantics of the current `PolicyEngine.evaluateStringCondition`
/// implementation.
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
        switch mode {
        case .contains:
            // Pipe-separated OR semantics, lowercase compare,
            // matching the current implementation in PolicyEngine.
            let lowered = candidate.lowercased()
            return pattern
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
                .contains(where: { lowered.contains($0) })

        case .notContains:
            return !StringMatcher(mode: .contains)
                .matches(candidate, against: pattern)

        case .equals:
            return candidate.compare(pattern, options: .caseInsensitive) == .orderedSame

        case .notEquals:
            return !StringMatcher(mode: .equals)
                .matches(candidate, against: pattern)
        }
    }
}
