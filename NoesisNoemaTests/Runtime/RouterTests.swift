// NoesisNoema - HybridRuntime: Hybrid Routing Runtime
// Router Tests
// Created: 2026-03-07
// License: MIT License

import XCTest
@testable import NoesisNoema

/// Tests for HybridRouter determinism and purity
///
/// These tests verify constitutional constraints (ADR-0000):
/// - Side-effect freedom (run twice, compare results)
/// - Determinism (same input → same output)
/// - No randomness or time-based branching
/// - Correct routing logic
final class HybridRouterTests: XCTestCase {

    var router: HybridRouter!

    override func setUp() {
        super.setUp()
        router = HybridRouter()
    }

    override func tearDown() {
        router = nil
        super.tearDown()
    }

    // MARK: - Determinism Tests

    func testDeterminism_SameInputProducesSameOutput() {
        // Given: A PolicyResult
        let policy = PolicyResult(
            toolRequired: true,
            privacySensitive: false,
            lowLatencyPreferred: false
        )

        // When: Routing the same policy twice
        let route1 = router.route(policy)
        let route2 = router.route(policy)

        // Then: Results must be identical (proves determinism)
        XCTAssertEqual(route1, route2, "Router must be deterministic")
    }

    func testDeterminism_MultipleRoutingsProduceSameResults() {
        // Given: A PolicyResult
        let policy = PolicyResult(
            toolRequired: false,
            privacySensitive: true,
            lowLatencyPreferred: false
        )

        // When: Routing 10 times
        let routes = (0..<10).map { _ in router.route(policy) }

        // Then: All routes must be identical
        let firstRoute = routes[0]
        for route in routes {
            XCTAssertEqual(route, firstRoute, "All routings must produce identical results")
        }
    }

    // MARK: - Rule 1: Tool Required → Remote Agent

    func testRouting_ToolRequired_RoutesToRemoteAgent() {
        // Given: Policy with toolRequired = true
        let policy = PolicyResult(
            toolRequired: true,
            privacySensitive: false,
            lowLatencyPreferred: false
        )

        // When: Routing
        let route = router.route(policy)

        // Then: Should route to remoteAgent
        XCTAssertEqual(route, .cloud, "toolRequired should route to remoteAgent")
    }

    func testRouting_ToolRequired_OverridesOtherSignals() {
        // Given: Policy with toolRequired = true and other signals also true
        let policy = PolicyResult(
            toolRequired: true,
            privacySensitive: true,  // Would prefer local
            lowLatencyPreferred: true  // Would prefer local
        )

        // When: Routing
        let route = router.route(policy)

        // Then: Should route to remoteAgent (toolRequired has priority)
        XCTAssertEqual(route, .cloud, "toolRequired should override other signals")
    }

    // MARK: - Rule 2: Privacy Sensitive → Local LLM

    func testRouting_PrivacySensitive_RoutesToLocalLLM() {
        // Given: Policy with privacySensitive = true, toolRequired = false
        let policy = PolicyResult(
            toolRequired: false,
            privacySensitive: true,
            lowLatencyPreferred: false
        )

        // When: Routing
        let route = router.route(policy)

        // Then: Should route to localLLM
        XCTAssertEqual(route, .local, "privacySensitive should route to localLLM")
    }

    func testRouting_PrivacySensitive_OverridesLowLatency() {
        // Given: Policy with privacySensitive = true and lowLatencyPreferred = true
        let policy = PolicyResult(
            toolRequired: false,
            privacySensitive: true,
            lowLatencyPreferred: true
        )

        // When: Routing
        let route = router.route(policy)

        // Then: Should route to localLLM (privacy has priority over latency)
        XCTAssertEqual(route, .local, "privacySensitive should route to localLLM")
    }

    // MARK: - Rule 3: Low Latency Preferred → Local LLM

    func testRouting_LowLatencyPreferred_RoutesToLocalLLM() {
        // Given: Policy with lowLatencyPreferred = true, others false
        let policy = PolicyResult(
            toolRequired: false,
            privacySensitive: false,
            lowLatencyPreferred: true
        )

        // When: Routing
        let route = router.route(policy)

        // Then: Should route to localLLM
        XCTAssertEqual(route, .local, "lowLatencyPreferred should route to localLLM")
    }

    // MARK: - Rule 4: Default → Remote Agent

    func testRouting_NoSignals_RoutesToRemoteAgent() {
        // Given: Policy with all signals false
        let policy = PolicyResult(
            toolRequired: false,
            privacySensitive: false,
            lowLatencyPreferred: false
        )

        // When: Routing
        let route = router.route(policy)

        // Then: Should route to remoteAgent (default)
        XCTAssertEqual(route, .cloud, "Default should route to remoteAgent")
    }

    // MARK: - Comprehensive Routing Matrix Tests

    func testRoutingMatrix_AllCombinations() {
        // Test all 8 possible combinations of boolean signals
        let testCases: [(Bool, Bool, Bool, ExecutionRoute)] = [
            // (toolRequired, privacySensitive, lowLatencyPreferred, expectedRoute)
            (false, false, false, .cloud),  // Rule 4: Default
            (false, false, true,  .local),     // Rule 3: Low latency
            (false, true,  false, .local),     // Rule 2: Privacy
            (false, true,  true,  .local),     // Rule 2: Privacy (overrides latency)
            (true,  false, false, .cloud),  // Rule 1: Tool
            (true,  false, true,  .cloud),  // Rule 1: Tool (overrides latency)
            (true,  true,  false, .cloud),  // Rule 1: Tool (overrides privacy)
            (true,  true,  true,  .cloud),  // Rule 1: Tool (overrides all)
        ]

        for (toolRequired, privacySensitive, lowLatencyPreferred, expectedRoute) in testCases {
            // Given: Policy with specific combination
            let policy = PolicyResult(
                toolRequired: toolRequired,
                privacySensitive: privacySensitive,
                lowLatencyPreferred: lowLatencyPreferred
            )

            // When: Routing
            let route = router.route(policy)

            // Then: Should match expected route
            XCTAssertEqual(
                route,
                expectedRoute,
                "Policy(\(toolRequired), \(privacySensitive), \(lowLatencyPreferred)) should route to \(expectedRoute)"
            )
        }
    }

    // MARK: - Rule Priority Tests

    func testRulePriority_ToolRequiredIsHighestPriority() {
        // Given: Policy with toolRequired = true
        let policy = PolicyResult(
            toolRequired: true,
            privacySensitive: true,
            lowLatencyPreferred: true
        )

        // When: Routing
        let route = router.route(policy)

        // Then: Should route to remoteAgent (tool has highest priority)
        XCTAssertEqual(route, .cloud, "toolRequired has highest priority")
    }

    func testRulePriority_PrivacySensitiveIsSecondPriority() {
        // Given: Policy with privacySensitive = true, toolRequired = false
        let policy = PolicyResult(
            toolRequired: false,
            privacySensitive: true,
            lowLatencyPreferred: true
        )

        // When: Routing
        let route = router.route(policy)

        // Then: Should route to localLLM (privacy has second priority)
        XCTAssertEqual(route, .local, "privacySensitive has second priority")
    }

    func testRulePriority_LowLatencyIsThirdPriority() {
        // Given: Policy with lowLatencyPreferred = true, others false
        let policy = PolicyResult(
            toolRequired: false,
            privacySensitive: false,
            lowLatencyPreferred: true
        )

        // When: Routing
        let route = router.route(policy)

        // Then: Should route to localLLM (latency has third priority)
        XCTAssertEqual(route, .local, "lowLatencyPreferred has third priority")
    }

    // MARK: - Integration Tests (PolicyEngine + Router)

    func testIntegration_ToolQuery_RoutesToRemoteAgent() {
        // Given: Request with tool keyword
        let request = NoemaRequest(query: "Send an email to John")
        let policyEngine = HybridPolicyEngine()

        // When: Evaluating and routing
        let policy = policyEngine.evaluate(request)
        let route = router.route(policy)

        // Then: Should route to remoteAgent
        XCTAssertEqual(route, .cloud, "Tool queries should route to remoteAgent")
    }

    func testIntegration_PrivacyQuery_RoutesToLocalLLM() {
        // Given: Request with privacy keyword
        let request = NoemaRequest(query: "What is my phone number?")
        let policyEngine = HybridPolicyEngine()

        // When: Evaluating and routing
        let policy = policyEngine.evaluate(request)
        let route = router.route(policy)

        // Then: Should route to localLLM
        XCTAssertEqual(route, .local, "Privacy queries should route to localLLM")
    }

    func testIntegration_SimpleQuery_RoutesToLocalLLM() {
        // Given: Short simple query
        let request = NoemaRequest(query: "Hello")
        let policyEngine = HybridPolicyEngine()

        // When: Evaluating and routing
        let policy = policyEngine.evaluate(request)
        let route = router.route(policy)

        // Then: Should route to localLLM (low latency)
        XCTAssertEqual(route, .local, "Simple queries should route to localLLM")
    }

    func testIntegration_ComplexQuery_RoutesToRemoteAgent() {
        // Given: Long complex query
        let longQuery = "Tell me about the history of artificial intelligence and its development over the past several decades"
        let request = NoemaRequest(query: longQuery)
        let policyEngine = HybridPolicyEngine()

        // When: Evaluating and routing
        let policy = policyEngine.evaluate(request)
        let route = router.route(policy)

        // Then: Should route to remoteAgent (default for complex queries)
        XCTAssertEqual(route, .cloud, "Complex queries should route to remoteAgent")
    }
}
