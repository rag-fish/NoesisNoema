// NoesisNoema is a knowledge graph framework for building AI applications.
// This file contains unit tests for the deterministic Router.
// EPIC1: Client Authority Hardening (Phase 2) - Section 2.5
// Created: 2026-02-21
// License: MIT License

import XCTest
@testable import NoesisNoema

/// Test suite for Router determinism and correctness
///
/// Test Requirements (Section 2.5):
/// 1. Identical input → identical output
/// 2. Policy BLOCK always wins
/// 3. privacy_level == .local never routes to cloud
/// 4. No randomness present
final class RouterDeterminismTests: XCTestCase {

    // MARK: - Test Fixtures

    /// Create a test question with specified parameters
    private func makeQuestion(
        content: String = "Test question",
        privacyLevel: PrivacyLevel = .auto,
        intent: Intent? = nil
    ) -> NoemaQuestion {
        NoemaQuestion(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            content: content,
            privacyLevel: privacyLevel,
            intent: intent,
            sessionId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )
    }

    /// Create a test runtime state with specified parameters
    private func makeRuntimeState(
        localAvailable: Bool = true,
        networkState: NetworkState = .online,
        tokenThreshold: Int = 4096
    ) -> RuntimeState {
        let localCapability = LocalModelCapability(
            modelName: "llama-3.2-8b",
            maxTokens: 4096,
            supportedIntents: [.informational, .retrieval],
            available: localAvailable
        )

        return RuntimeState(
            localModelCapability: localCapability,
            networkState: networkState,
            tokenThreshold: tokenThreshold,
            cloudModelName: "gpt-4"
        )
    }

    // MARK: - Determinism Tests

    /// Test: Identical inputs produce identical outputs
    /// This is the fundamental requirement for a pure function
    func testDeterminism_IdenticalInputs_ProducesIdenticalOutputs() throws {
        // Arrange: Create fixed inputs
        let question = makeQuestion(content: "What is the capital of France?")
        let state = makeRuntimeState()
        let policy = PolicyEvaluationResult.allowDefault

        // Act: Call router twice with identical inputs
        let decision1 = try Router.route(
            question: question,
            runtimeState: state,
            policyResult: policy
        )
        let decision2 = try Router.route(
            question: question,
            runtimeState: state,
            policyResult: policy
        )

        // Assert: Outputs must be identical
        XCTAssertEqual(decision1.routeTarget, decision2.routeTarget,
                       "Route target must be identical")
        XCTAssertEqual(decision1.ruleId, decision2.ruleId,
                       "Rule ID must be identical")
        XCTAssertEqual(decision1.model, decision2.model,
                       "Model must be identical")
        XCTAssertEqual(decision1.fallbackAllowed, decision2.fallbackAllowed,
                       "Fallback allowed must be identical")
        XCTAssertEqual(decision1, decision2,
                       "Complete decisions must be identical")
    }

    /// Test: Multiple invocations with same inputs produce same results
    func testDeterminism_MultipleInvocations_ProducesSameResults() throws {
        // Arrange
        let question = makeQuestion(content: "Explain quantum computing")
        let state = makeRuntimeState()
        let policy = PolicyEvaluationResult.allowDefault

        // Act: Call router 10 times
        var decisions: [RoutingDecision] = []
        for _ in 0..<10 {
            let decision = try Router.route(
                question: question,
                runtimeState: state,
                policyResult: policy
            )
            decisions.append(decision)
        }

        // Assert: All decisions must be identical
        let firstDecision = decisions[0]
        for decision in decisions.dropFirst() {
            XCTAssertEqual(decision, firstDecision,
                           "All decisions must be identical")
        }
    }

    // MARK: - Policy Priority Tests

    /// Test: Policy BLOCK always wins (highest priority)
    func testPolicyPriority_BlockAlwaysWins() throws {
        // Arrange: Policy blocks, but privacy_level is .cloud
        let question = makeQuestion(privacyLevel: .cloud)
        let state = makeRuntimeState()
        let policy = PolicyEvaluationResult(
            effectiveAction: .block(reason: "Sensitive content detected")
        )

        // Act & Assert: Should throw policyViolation error
        XCTAssertThrowsError(
            try Router.route(question: question, runtimeState: state, policyResult: policy)
        ) { error in
            guard let routingError = error as? RoutingError,
                  case .policyViolation(let reason) = routingError else {
                XCTFail("Expected RoutingError.policyViolation, got \(error)")
                return
            }
            XCTAssertEqual(reason, "Sensitive content detected")
        }
    }

    /// Test: POLICY_BLOCK throws exception with correct reason
    func testPolicyBlock_ThrowsException() throws {
        // Arrange: Multiple scenarios with policy block
        let scenarios: [(String, NoemaQuestion, String)] = [
            ("Local privacy", makeQuestion(privacyLevel: .local), "Blocked: local mode"),
            ("Cloud privacy", makeQuestion(privacyLevel: .cloud), "Blocked: cloud mode"),
            ("Auto mode", makeQuestion(privacyLevel: .auto), "Blocked: auto mode"),
            ("Large content", makeQuestion(content: String(repeating: "x", count: 10000), privacyLevel: .auto), "Blocked: large content")
        ]

        for (scenario, question, expectedReason) in scenarios {
            let state = makeRuntimeState()
            let policy = PolicyEvaluationResult(
                effectiveAction: .block(reason: expectedReason)
            )

            // Act & Assert
            XCTAssertThrowsError(
                try Router.route(question: question, runtimeState: state, policyResult: policy),
                "Scenario '\(scenario)' should throw"
            ) { error in
                guard let routingError = error as? RoutingError,
                      case .policyViolation(let reason) = routingError else {
                    XCTFail("Scenario '\(scenario)': Expected RoutingError.policyViolation, got \(error)")
                    return
                }
                XCTAssertEqual(reason, expectedReason, "Scenario '\(scenario)': reason should match")
            }
        }
    }

    /// Test: POLICY_BLOCK does not return a routing decision
    func testPolicyBlock_DoesNotReturnDecision() throws {
        // Arrange
        let question = makeQuestion(privacyLevel: .auto)
        let state = makeRuntimeState()
        let policy = PolicyEvaluationResult(
            effectiveAction: .block(reason: "Test block")
        )

        // Act & Assert: Should throw, not return
        do {
            let _ = try Router.route(question: question, runtimeState: state, policyResult: policy)
            XCTFail("Router should throw RoutingError.policyViolation, not return a decision")
        } catch let error as RoutingError {
            // Expected: policy violation error
            guard case .policyViolation = error else {
                XCTFail("Expected policyViolation error, got \(error)")
                return
            }
            // Success - exception was thrown as required
        } catch {
            XCTFail("Expected RoutingError.policyViolation, got \(error)")
        }
    }

    /// Test: Policy FORCE_LOCAL overrides auto mode
    func testPolicyPriority_ForceLocalOverridesAuto() throws {
        // Arrange: Large content that would normally route to cloud
        let largeContent = String(repeating: "word ", count: 2000) // ~500 tokens
        let question = makeQuestion(content: largeContent, privacyLevel: .auto)
        let state = makeRuntimeState(tokenThreshold: 100) // Very low threshold
        let policy = PolicyEvaluationResult(
            effectiveAction: .forceLocal
        )

        // Act
        let decision = try Router.route(
            question: question,
            runtimeState: state,
            policyResult: policy
        )

        // Assert: Should route to local despite exceeding threshold
        XCTAssertEqual(decision.routeTarget, .local)
        XCTAssertEqual(decision.ruleId, .POLICY_FORCE_LOCAL)
    }

    /// Test: Policy FORCE_CLOUD overrides privacy_level == .local
    func testPolicyPriority_ForceCloudOverridesPrivacyLocal() throws {
        // Arrange: User requests local, but policy forces cloud
        let question = makeQuestion(privacyLevel: .local)
        let state = makeRuntimeState()
        let policy = PolicyEvaluationResult(
            effectiveAction: .forceCloud
        )

        // Act
        let decision = try Router.route(
            question: question,
            runtimeState: state,
            policyResult: policy
        )

        // Assert: Policy wins over privacy setting
        XCTAssertEqual(decision.routeTarget, .cloud)
        XCTAssertEqual(decision.ruleId, .POLICY_FORCE_CLOUD)
    }

    // MARK: - Privacy Guarantee Tests

    /// Test: privacy_level == .local NEVER routes to cloud
    func testPrivacyGuarantee_LocalNeverRoutesToCloud() throws {
        // Arrange: Multiple scenarios that would normally route to cloud
        let scenarios: [(String, RuntimeState)] = [
            ("Large content", makeRuntimeState(tokenThreshold: 10)),
            ("Local unavailable", makeRuntimeState(localAvailable: false)),
            ("Network offline", makeRuntimeState(networkState: .offline))
        ]

        for (scenario, state) in scenarios {
            // Act
            let question = makeQuestion(privacyLevel: .local)
            let policy = PolicyEvaluationResult.allowDefault

            let decision = try Router.route(
                question: question,
                runtimeState: state,
                policyResult: policy
            )

            // Assert: Must always route to local
            XCTAssertEqual(decision.routeTarget, .local,
                           "Scenario '\(scenario)' must route to local")
            XCTAssertEqual(decision.ruleId, .PRIVACY_LOCAL,
                           "Scenario '\(scenario)' must use PRIVACY_LOCAL rule")
            XCTAssertFalse(decision.fallbackAllowed,
                           "Scenario '\(scenario)' must not allow fallback")
        }
    }

    /// Test: privacy_level == .cloud requires network
    func testPrivacyGuarantee_CloudRequiresNetwork() throws {
        // Arrange: Cloud privacy level but network is offline
        let question = makeQuestion(privacyLevel: .cloud)
        let state = makeRuntimeState(networkState: .offline)
        let policy = PolicyEvaluationResult.allowDefault

        // Act & Assert: Should throw networkUnavailable error
        XCTAssertThrowsError(
            try Router.route(question: question, runtimeState: state, policyResult: policy)
        ) { error in
            XCTAssertEqual(error as? RoutingError, .networkUnavailable)
        }
    }

    /// Test: privacy_level == .local sets fallbackAllowed = false
    func testPrivacyGuarantee_LocalDisablesFallback() throws {
        // Arrange
        let question = makeQuestion(privacyLevel: .local)
        let state = makeRuntimeState()
        let policy = PolicyEvaluationResult.allowDefault

        // Act
        let decision = try Router.route(
            question: question,
            runtimeState: state,
            policyResult: policy
        )

        // Assert: Fallback must be disabled for privacy_level == .local
        XCTAssertFalse(decision.fallbackAllowed,
                       "Local privacy mode must disable fallback")
    }

    // MARK: - Auto Mode Tests

    /// Test: Auto mode routes to local when within threshold
    func testAutoMode_SmallContent_RoutesToLocal() throws {
        // Arrange: Small content within token threshold
        let question = makeQuestion(content: "Short question", privacyLevel: .auto)
        let state = makeRuntimeState(tokenThreshold: 4096)
        let policy = PolicyEvaluationResult.allowDefault

        // Act
        let decision = try Router.route(
            question: question,
            runtimeState: state,
            policyResult: policy
        )

        // Assert
        XCTAssertEqual(decision.routeTarget, .local)
        XCTAssertEqual(decision.ruleId, .AUTO_LOCAL)
        XCTAssertTrue(decision.fallbackAllowed,
                      "Auto local mode should allow fallback")
    }

    /// Test: Auto mode routes to cloud when exceeding threshold
    func testAutoMode_LargeContent_RoutesToCloud() throws {
        // Arrange: Large content exceeding token threshold
        let largeContent = String(repeating: "word ", count: 5000) // ~1250 tokens
        let question = makeQuestion(content: largeContent, privacyLevel: .auto)
        let state = makeRuntimeState(tokenThreshold: 100)
        let policy = PolicyEvaluationResult.allowDefault

        // Act
        let decision = try Router.route(
            question: question,
            runtimeState: state,
            policyResult: policy
        )

        // Assert
        XCTAssertEqual(decision.routeTarget, .cloud)
        XCTAssertEqual(decision.ruleId, .AUTO_CLOUD)
        XCTAssertFalse(decision.fallbackAllowed,
                       "Auto cloud mode should not allow fallback")
    }

    /// Test: Auto mode routes to cloud when local unavailable
    func testAutoMode_LocalUnavailable_RoutesToCloud() throws {
        // Arrange: Small content but local model unavailable
        let question = makeQuestion(content: "Short question", privacyLevel: .auto)
        let state = makeRuntimeState(localAvailable: false)
        let policy = PolicyEvaluationResult.allowDefault

        // Act
        let decision = try Router.route(
            question: question,
            runtimeState: state,
            policyResult: policy
        )

        // Assert
        XCTAssertEqual(decision.routeTarget, .cloud)
        XCTAssertEqual(decision.ruleId, .AUTO_CLOUD)
    }

    /// Test: Auto mode respects intent support
    func testAutoMode_UnsupportedIntent_RoutesToCloud() throws {
        // Arrange: Intent not supported by local model
        let question = makeQuestion(
            content: "Analyze this complex problem",
            privacyLevel: .auto,
            intent: .analytical  // Not in supported intents
        )
        let state = makeRuntimeState() // Supports only .informational and .retrieval
        let policy = PolicyEvaluationResult.allowDefault

        // Act
        let decision = try Router.route(
            question: question,
            runtimeState: state,
            policyResult: policy
        )

        // Assert
        XCTAssertEqual(decision.routeTarget, .cloud)
        XCTAssertEqual(decision.ruleId, .AUTO_CLOUD)
    }

    // MARK: - No Randomness Tests

    /// Test: Router produces no randomness
    /// Verifies that all decisions are deterministic
    func testNoRandomness_AllDecisionsAreDeterministic() throws {
        // Arrange: Test multiple question variations
        let questions = [
            makeQuestion(content: "Test 1", privacyLevel: .auto),
            makeQuestion(content: "Test 2", privacyLevel: .local),
            makeQuestion(content: "Test 3", privacyLevel: .cloud),
            makeQuestion(content: String(repeating: "long ", count: 1000), privacyLevel: .auto)
        ]

        let state = makeRuntimeState()
        let policy = PolicyEvaluationResult.allowDefault

        // Act & Assert: Each question should produce identical results across multiple calls
        for question in questions {
            var previousDecision: RoutingDecision?

            for iteration in 0..<5 {
                let decision = try Router.route(
                    question: question,
                    runtimeState: state,
                    policyResult: policy
                )

                if let previous = previousDecision {
                    XCTAssertEqual(decision, previous,
                                   "Iteration \(iteration) must match previous decision")
                }
                previousDecision = decision
            }
        }
    }

    /// Test: Token estimation is deterministic
    func testNoRandomness_TokenEstimationIsDeterministic() throws {
        // Arrange: Same content should always estimate same token count
        let content = "This is a test sentence with some words."
        let question = makeQuestion(content: content, privacyLevel: .auto)
        let state = makeRuntimeState()
        let policy = PolicyEvaluationResult.allowDefault

        // Act: Route multiple times
        var decisions: [RoutingDecision] = []
        for _ in 0..<10 {
            let decision = try Router.route(
                question: question,
                runtimeState: state,
                policyResult: policy
            )
            decisions.append(decision)
        }

        // Assert: All decisions should be identical (proving token estimation is deterministic)
        let firstDecision = decisions[0]
        for decision in decisions.dropFirst() {
            XCTAssertEqual(decision.ruleId, firstDecision.ruleId,
                           "Rule ID must be consistent (proving deterministic token estimation)")
        }
    }

    // MARK: - Network State Tests

    /// Test: Cloud routes require online network
    func testNetworkState_CloudRequiresOnline() throws {
        // Arrange: Try to route to cloud with offline network
        let question = makeQuestion(privacyLevel: .auto)
        let state = makeRuntimeState(
            localAvailable: false,  // Force cloud route
            networkState: .offline
        )
        let policy = PolicyEvaluationResult.allowDefault

        // Act & Assert: Should throw networkUnavailable
        XCTAssertThrowsError(
            try Router.route(question: question, runtimeState: state, policyResult: policy)
        ) { error in
            XCTAssertEqual(error as? RoutingError, .networkUnavailable)
        }
    }

    /// Test: Degraded network still allows cloud routing
    func testNetworkState_DegradedAllowsCloud() throws {
        // Arrange: Cloud route with degraded network
        let question = makeQuestion(privacyLevel: .cloud)
        let state = makeRuntimeState(networkState: .degraded)
        let policy = PolicyEvaluationResult.allowDefault

        // Act
        // Note: Degraded network is treated as .online for routing purposes
        // Actual performance handling happens in ExecutionCoordinator
        let decision = try Router.route(
            question: question,
            runtimeState: state,
            policyResult: policy
        )

        // Assert: Should still route to cloud (degraded != offline)
        XCTAssertEqual(decision.routeTarget, .cloud)
        XCTAssertEqual(decision.ruleId, .PRIVACY_CLOUD)
    }
}
