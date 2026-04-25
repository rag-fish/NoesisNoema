//
//  NumericComparator.swift
//  NoesisNoema
//
//  Phase 1 of EPIC4 #68. Operator strategy for numeric-typed conditions.
//  See docs/EPIC4_Policy_Engine_Extensibility_Design.md (section 4.2).
//
//  License: MIT License
//

import Foundation

/// Value-typed comparison strategy for numeric-valued conditions.
///
/// Encapsulates the four current numeric operators. Adding a new mode
/// (between, percentage, etc.) is a strategy-level change; condition
/// types and `PolicyEngine` do not need to be touched.
struct NumericComparator {

    enum Mode {
        case exceeds
        case lessThan
        case equals
        case notEquals
    }

    let mode: Mode

    /// Apply the strategy.
    /// - Parameters:
    ///   - candidate: The runtime value being checked.
    ///   - threshold: The threshold from the rule.
    /// - Returns: `true` if the candidate matches under this mode.
    func matches(_ candidate: Int, against threshold: Int) -> Bool {
        switch mode {
        case .exceeds:    return candidate > threshold
        case .lessThan:   return candidate < threshold
        case .equals:     return candidate == threshold
        case .notEquals:  return candidate != threshold
        }
    }
}
