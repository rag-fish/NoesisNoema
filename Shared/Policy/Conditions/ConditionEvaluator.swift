//
//  ConditionEvaluator.swift
//  NoesisNoema
//
//  Phase 1 of EPIC4 #68 PolicyEngine extensibility.
//  See docs/EPIC4_Policy_Engine_Extensibility_Design.md (section 4.1).
//
//  Pure, deterministic predicate. No Sendable annotation, no actor
//  isolation, no async. Concrete conformers are value-type structs.
//
//  License: MIT License
//

import Foundation

/// A pure predicate that decides whether a single policy condition holds
/// for a given question and runtime state.
///
/// Adding a new condition kind (for example, a future `TimeOfDayCondition`)
/// is achieved by introducing a new struct that conforms to this protocol.
/// `PolicyEngine` does not need to be modified.
///
/// Conformers MUST be deterministic, side-effect free, and synchronous.
/// They MUST NOT throw, depend on `@MainActor` state, or perform any
/// async or external call.
protocol ConditionEvaluator {

    /// Evaluate the condition.
    ///
    /// - Returns: `true` if the condition is satisfied, `false` otherwise.
    func evaluate(
        question: NoemaQuestion,
        runtimeState: RuntimeState
    ) -> Bool
}
