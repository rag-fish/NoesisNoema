// NoesisNoema is a knowledge graph framework for building AI applications.
// This file implements the deterministic Router as a pure function.
// EPIC1: Client Authority Hardening (Phase 2) - Section 2.5
// Created: 2026-02-21
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

    /// Route a question to local or cloud execution
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

        // STEP 1: Apply Policy Decision Engine Result
        // Policy constraints have absolute priority over all other rules
        switch policyResult.effectiveAction {
        case .block(let reason):
            // Policy blocks execution entirely
            throw RoutingError.policyViolation(reason: reason)

        case .forceLocal:
            // Policy forces local execution
            return RoutingDecision(
                routeTarget: .local,
                model: runtimeState.localModelCapability.modelName,
                reason: "Policy constraint forced local execution",
                ruleId: .POLICY_FORCE_LOCAL,
                fallbackAllowed: false,
                requiresConfirmation: policyResult.requiresConfirmation
            )

        case .forceCloud:
            // Policy forces cloud execution
            // Check network availability first
            guard runtimeState.networkState == .online else {
                throw RoutingError.networkUnavailable
            }

            return RoutingDecision(
                routeTarget: .cloud,
                model: runtimeState.cloudModelName,
                reason: "Policy constraint forced cloud execution",
                ruleId: .POLICY_FORCE_CLOUD,
                fallbackAllowed: false,
                requiresConfirmation: policyResult.requiresConfirmation
            )

        case .allow:
            // Policy allows routing to proceed - continue to Step 2
            break
        }

        // STEP 2: Enforce Privacy Guarantees
        // Privacy constraints cannot be bypassed by any subsequent logic
        switch question.privacyLevel {
        case .local:
            // User explicitly requests local execution
            // GUARANTEE: Network request will NEVER be constructed
            return RoutingDecision(
                routeTarget: .local,
                model: runtimeState.localModelCapability.modelName,
                reason: "User requested local-only execution (privacy constraint)",
                ruleId: .PRIVACY_LOCAL,
                fallbackAllowed: false,
                requiresConfirmation: false
            )

        case .cloud:
            // User explicitly requests cloud execution
            guard runtimeState.networkState == .online else {
                throw RoutingError.networkUnavailable
            }

            return RoutingDecision(
                routeTarget: .cloud,
                model: runtimeState.cloudModelName,
                reason: "User requested cloud execution",
                ruleId: .PRIVACY_CLOUD,
                fallbackAllowed: false,
                requiresConfirmation: false
            )

        case .auto:
            // Continue to Step 3 for auto mode logic
            break
        }

        // STEP 3: Apply Auto Mode Logic
        // Evaluate multiple factors to determine optimal route

        // Step 3.1: Estimate token count
        let tokenCount = estimateTokenCount(question.content)

        // Step 3.2: Check local model availability
        let localModelAvailable = runtimeState.localModelCapability.available

        // Step 3.3: Check if intent is supported locally
        let intentSupportedLocally: Bool
        if let intent = question.intent {
            intentSupportedLocally = runtimeState.localModelCapability
                .supportedIntents.contains(intent)
        } else {
            // No intent specified - assume supported
            intentSupportedLocally = true
        }

        // Step 3.4: Apply routing logic
        if tokenCount <= runtimeState.tokenThreshold
            && localModelAvailable
            && intentSupportedLocally {

            // Route to local execution
            return RoutingDecision(
                routeTarget: .local,
                model: runtimeState.localModelCapability.modelName,
                reason: "Token count within threshold, local model capable",
                ruleId: .AUTO_LOCAL,
                fallbackAllowed: true,  // Can fallback to cloud if local fails
                requiresConfirmation: false
            )
        } else {
            // Route to cloud execution
            guard runtimeState.networkState == .online else {
                throw RoutingError.networkUnavailable
            }

            return RoutingDecision(
                routeTarget: .cloud,
                model: runtimeState.cloudModelName,
                reason: "Token count exceeds threshold or local model insufficient",
                ruleId: .AUTO_CLOUD,
                fallbackAllowed: false,
                requiresConfirmation: false
            )
        }
    }

    // MARK: - Private Pure Functions

    /// Estimate token count from text content
    /// This is a deterministic approximation (4 chars ≈ 1 token)
    /// - Parameter content: The text content
    /// - Returns: Estimated token count
    private static func estimateTokenCount(_ content: String) -> Int {
        // Simple deterministic estimation: ~4 characters per token
        // This matches typical tokenization ratios for English text
        return max(1, content.count / 4)
    }
}
