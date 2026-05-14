// NoesisNoema is a knowledge graph framework for building AI applications.
// This file implements the deterministic Router as a pure function.
// Created: 2026-02-21
// Updated: 2026-05-15 — added routeWithTrace() for debug observability (Phase 2, Issue #70)
// License: MIT License

import Foundation

/// Deterministic Router - Pure Function Implementation
///
/// Purity Contract:
/// 1. Deterministic: Same inputs → same outputs (always)
/// 2. Side-effect free: No I/O, no logging, no global state mutation
/// 3. Free of randomness: No probabilistic branching
/// 4. Free of time-based branching: No Date.now() comparisons
///
/// Evaluation Order (Section 2.5):
/// Step 1: Apply Policy Decision Engine Result
/// Step 2: Enforce Privacy Guarantees
/// Step 3: Apply Auto Mode Logic
/// Step 4: Fallback Handling (occurs in ExecutionCoordinator, not here)
struct Router {

    // MARK: - Production Entry Point

    /// Route a question to local or cloud execution.
    /// This is the production path. It is unchanged by debug mode.
    /// - Parameters:
    ///   - question: The user's question with privacy constraints
    ///   - runtimeState: Current runtime state (network, local model capability)
    ///   - policyResult: Result from Policy Engine evaluation
    /// - Returns: A deterministic routing decision
    /// - Throws: RoutingError if routing cannot proceed
    static func route(
        question: NoemaQuestion,
        runtimeState: RuntimeState,
        policyResult: PolicyEvaluationResult
    ) throws -> RoutingDecision {
        try _evaluate(question: question, runtimeState: runtimeState, policyResult: policyResult).decision
    }

    // MARK: - Debug Entry Point

    /// Route a question and return both the decision and a step-level trace.
    /// Called only when RuntimeState.debugMode == true.
    ///
    /// Purity constraints (same as route()):
    /// - No logging, no print, no I/O, no state mutation
    /// - Same routing result as route() for identical inputs
    /// - Returns: (RoutingDecision, RoutingStepTrace)
    /// - Throws: RoutingError (same conditions as route())
    static func routeWithTrace(
        question: NoemaQuestion,
        runtimeState: RuntimeState,
        policyResult: PolicyEvaluationResult
    ) throws -> (decision: RoutingDecision, trace: RoutingStepTrace) {
        try _evaluate(question: question, runtimeState: runtimeState, policyResult: policyResult)
    }

    // MARK: - Shared Core Logic

    /// Internal implementation shared by route() and routeWithTrace().
    /// Returns both a decision and a full step trace; route() discards the trace.
    private static func _evaluate(
        question: NoemaQuestion,
        runtimeState: RuntimeState,
        policyResult: PolicyEvaluationResult
    ) throws -> (decision: RoutingDecision, trace: RoutingStepTrace) {

        // Capture input snapshot before evaluation begins.
        // No raw query text is stored here.
        let tokenCount = estimateTokenCount(question.content)
        let intentSupportedLocally: Bool = {
            guard let intent = question.intent else { return true }
            return runtimeState.localModelCapability.supportedIntents.contains(intent)
        }()

        let inputSnapshot = RoutingInputSnapshot(
            privacyLevel: question.privacyLevel.rawValue,
            toolRequired: question.toolRequired,
            privacySensitive: question.privacySensitive,
            lowLatencyPreferred: question.lowLatencyPreferred,
            networkState: runtimeState.networkState.rawValue,
            tokenCount: tokenCount,
            tokenThreshold: runtimeState.tokenThreshold,
            localModelAvailable: runtimeState.localModelCapability.available,
            intentSupportedLocally: intentSupportedLocally,
            debugMode: runtimeState.debugMode,
            policyEffectiveAction: String(describing: policyResult.effectiveAction),
            overrideMode: nil  // Reserved for Issue #69
        )

        var steps: [RoutingStepRecord] = []

        // STEP 1: Apply Policy Decision Engine Result
        switch policyResult.effectiveAction {
        case .block(let reason):
            steps.append(RoutingStepRecord(
                step: .policyEnforcement,
                outcome: .threw,
                detail: "action=block reason=\(reason)"
            ))
            throw RoutingError.policyViolation(reason: reason)

        case .forceLocal:
            let decision = RoutingDecision(
                routeTarget: .local,
                model: runtimeState.localModelCapability.modelName,
                reason: "Policy constraint forced local execution",
                ruleId: .POLICY_FORCE_LOCAL,
                fallbackAllowed: false,
                requiresConfirmation: policyResult.requiresConfirmation
            )
            steps.append(RoutingStepRecord(
                step: .policyEnforcement,
                outcome: .terminated,
                detail: "action=forceLocal → POLICY_FORCE_LOCAL"
            ))
            return (decision, RoutingStepTrace(terminatingStep: .policyEnforcement, steps: steps, inputSnapshot: inputSnapshot))

        case .forceCloud:
            guard runtimeState.networkState == .online else {
                steps.append(RoutingStepRecord(
                    step: .policyEnforcement,
                    outcome: .threw,
                    detail: "action=forceCloud but networkState=\(runtimeState.networkState.rawValue)"
                ))
                throw RoutingError.networkUnavailable
            }
            let decision = RoutingDecision(
                routeTarget: .cloud,
                model: runtimeState.cloudModelName,
                reason: "Policy constraint forced cloud execution",
                ruleId: .POLICY_FORCE_CLOUD,
                fallbackAllowed: false,
                requiresConfirmation: policyResult.requiresConfirmation
            )
            steps.append(RoutingStepRecord(
                step: .policyEnforcement,
                outcome: .terminated,
                detail: "action=forceCloud → POLICY_FORCE_CLOUD"
            ))
            return (decision, RoutingStepTrace(terminatingStep: .policyEnforcement, steps: steps, inputSnapshot: inputSnapshot))

        case .allow:
            steps.append(RoutingStepRecord(
                step: .policyEnforcement,
                outcome: .passedThrough,
                detail: "action=allow"
            ))
        }

        // STEP 2: Enforce Privacy Guarantees
        switch question.privacyLevel {
        case .local:
            let decision = RoutingDecision(
                routeTarget: .local,
                model: runtimeState.localModelCapability.modelName,
                reason: "User requested local-only execution (privacy constraint)",
                ruleId: .PRIVACY_LOCAL,
                fallbackAllowed: false,
                requiresConfirmation: false
            )
            steps.append(RoutingStepRecord(
                step: .privacyEnforcement,
                outcome: .terminated,
                detail: "privacyLevel=local → PRIVACY_LOCAL"
            ))
            return (decision, RoutingStepTrace(terminatingStep: .privacyEnforcement, steps: steps, inputSnapshot: inputSnapshot))

        case .cloud:
            guard runtimeState.networkState == .online else {
                steps.append(RoutingStepRecord(
                    step: .privacyEnforcement,
                    outcome: .threw,
                    detail: "privacyLevel=cloud but networkState=\(runtimeState.networkState.rawValue)"
                ))
                throw RoutingError.networkUnavailable
            }
            let decision = RoutingDecision(
                routeTarget: .cloud,
                model: runtimeState.cloudModelName,
                reason: "User requested cloud execution",
                ruleId: .PRIVACY_CLOUD,
                fallbackAllowed: false,
                requiresConfirmation: false
            )
            steps.append(RoutingStepRecord(
                step: .privacyEnforcement,
                outcome: .terminated,
                detail: "privacyLevel=cloud → PRIVACY_CLOUD"
            ))
            return (decision, RoutingStepTrace(terminatingStep: .privacyEnforcement, steps: steps, inputSnapshot: inputSnapshot))

        case .auto:
            steps.append(RoutingStepRecord(
                step: .privacyEnforcement,
                outcome: .passedThrough,
                detail: "privacyLevel=auto"
            ))
        }

        // STEP 3: Apply Auto Mode Logic
        let localModelAvailable = runtimeState.localModelCapability.available

        if tokenCount <= runtimeState.tokenThreshold
            && localModelAvailable
            && intentSupportedLocally {
            let decision = RoutingDecision(
                routeTarget: .local,
                model: runtimeState.localModelCapability.modelName,
                reason: "Token count within threshold, local model capable",
                ruleId: .AUTO_LOCAL,
                fallbackAllowed: true,
                requiresConfirmation: false
            )
            steps.append(RoutingStepRecord(
                step: .autoModeLogic,
                outcome: .terminated,
                detail: "tokens=\(tokenCount)≤threshold=\(runtimeState.tokenThreshold) localAvail=\(localModelAvailable) intentOK=\(intentSupportedLocally) → AUTO_LOCAL"
            ))
            return (decision, RoutingStepTrace(terminatingStep: .autoModeLogic, steps: steps, inputSnapshot: inputSnapshot))
        } else {
            guard runtimeState.networkState == .online else {
                steps.append(RoutingStepRecord(
                    step: .autoModeLogic,
                    outcome: .threw,
                    detail: "auto→cloud but networkState=\(runtimeState.networkState.rawValue)"
                ))
                throw RoutingError.networkUnavailable
            }
            let decision = RoutingDecision(
                routeTarget: .cloud,
                model: runtimeState.cloudModelName,
                reason: "Token count exceeds threshold or local model insufficient",
                ruleId: .AUTO_CLOUD,
                fallbackAllowed: false,
                requiresConfirmation: false
            )
            steps.append(RoutingStepRecord(
                step: .autoModeLogic,
                outcome: .terminated,
                detail: "tokens=\(tokenCount) threshold=\(runtimeState.tokenThreshold) localAvail=\(localModelAvailable) intentOK=\(intentSupportedLocally) → AUTO_CLOUD"
            ))
            return (decision, RoutingStepTrace(terminatingStep: .autoModeLogic, steps: steps, inputSnapshot: inputSnapshot))
        }
    }

    // MARK: - Private Pure Functions

    /// Estimate token count from text content (deterministic approximation)
    private static func estimateTokenCount(_ content: String) -> Int {
        return max(1, content.count / 4)
    }
}
