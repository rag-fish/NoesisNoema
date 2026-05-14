//
//  RoutingStepTrace.swift
//  NoesisNoema
//
//  Purpose: Step-level routing debug trace types (Phase 1, Issue #70)
//  License: MIT License
//

import Foundation

// MARK: - RoutingStep

/// Identifies each discrete decision point in Router.routeWithTrace()
enum RoutingStep: String, Codable, Equatable {
    case policyEnforcement   // STEP 1: PolicyEvaluationResult applied
    case privacyEnforcement  // STEP 2: NoemaQuestion.privacyLevel enforced
    case autoModeLogic       // STEP 3: Token/capability auto-routing
}

// MARK: - RoutingStepOutcome

/// Outcome of a single routing step
enum RoutingStepOutcome: String, Codable, Equatable {
    /// Step evaluated its condition but did not terminate routing
    case passedThrough
    /// Step produced the final RoutingDecision
    case terminated
    /// Step threw a RoutingError (routing did not complete)
    case threw
}

// MARK: - RoutingStepRecord

/// Record for a single evaluated routing step
struct RoutingStepRecord: Codable, Equatable {
    /// Which step this record belongs to
    let step: RoutingStep

    /// Outcome of this step
    let outcome: RoutingStepOutcome

    /// Human-readable detail, e.g. "action=forceLocal → POLICY_FORCE_LOCAL"
    /// Must not contain raw query text.
    let detail: String
}

// MARK: - RoutingInputSnapshot

/// Snapshot of routing-relevant inputs at the time Router.routeWithTrace() was called.
/// Captures the decision surface visible to Router — no raw query text.
struct RoutingInputSnapshot: Codable, Equatable {
    // From NoemaQuestion
    /// Privacy level of the question
    let privacyLevel: String
    /// Whether the question requires a tool call
    let toolRequired: Bool
    /// Whether the question is marked privacy-sensitive
    let privacySensitive: Bool
    /// Whether low-latency response is preferred
    let lowLatencyPreferred: Bool

    // From RuntimeState
    /// Current network state ("online", "offline", "degraded")
    let networkState: String
    /// Estimated token count of the question content
    let tokenCount: Int
    /// Token threshold configured in RuntimeState
    let tokenThreshold: Int
    /// Whether the local model is available and initialized
    let localModelAvailable: Bool
    /// Whether the question's intent is supported by the local model
    let intentSupportedLocally: Bool
    /// Whether debug mode was active during this routing call
    let debugMode: Bool

    // From PolicyEvaluationResult
    /// String representation of the effective policy action
    let policyEffectiveAction: String

    // Future-ready: human override mode (nil until #69 is implemented)
    /// Override mode, if set (reserved for Issue #69)
    let overrideMode: String?
}

// MARK: - RoutingStepTrace

/// Full step-level trace produced by Router.routeWithTrace().
/// Contains the terminating step, per-step records, and input snapshot.
/// Purely a value type — no I/O, no side effects.
struct RoutingStepTrace: Codable, Equatable {
    /// The step that produced (or threw) the final RoutingDecision
    let terminatingStep: RoutingStep

    /// Records for each step that was evaluated, in evaluation order
    let steps: [RoutingStepRecord]

    /// Snapshot of routing inputs captured before evaluation began
    let inputSnapshot: RoutingInputSnapshot
}
