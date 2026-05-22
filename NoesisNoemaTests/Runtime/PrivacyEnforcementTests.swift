// NoesisNoema - Hybrid Routing Runtime
// Privacy Enforcement Tests — Privacy Step 4.5 (ADR-0008 Decision 4)
// Created: 2026-05-22 (R3: enforce execution-flow.md Step 4.5)
// License: MIT License
//
// These tests cover R3's two enforcement layers:
//
//   Layer 1 — the coordinator guard. `HybridExecutionCoordinator.execute`
//   runs a mandatory, non-bypassable privacy check between routing and
//   execution. Its decision is the pure function
//   `HybridExecutionCoordinator.evaluatePrivacyStep45(...)`, exercised
//   directly here: a privacy-local request that did not route on-device (or
//   that would permit cloud fallback) yields `.violated`, which the
//   coordinator turns into a thrown `ExecutionError.privacyViolation` —
//   never an agent/network call.
//
//   Layer 2 — the structural "zero network" guarantee. The CI form of
//   "zero network transmission" is: the network-capable executor
//   (`agentExecutor`) is never reached on a local route. The mock agent
//   below FAILS the test if its `execute` is ever invoked.
//
// NOTE: `HybridExecutionCoordinator.buildQuestion` currently hardcodes
// `privacyLevel: .auto` (the request-level privacy picker is pending), so a
// `.local` Question cannot yet be driven through the public `execute(request:)`
// API. The enforcement rule is therefore verified at the pure-function level
// (`evaluatePrivacyStep45`), and the coordinator path verifies that a
// locally-routed request never reaches the agent. This is a source-level
// guard — the NoesisNoemaTests target has no run scheme (caveat from R1).

import XCTest
@testable import NoesisNoema

/// Local executor stand-in — returns a deterministic result, no I/O.
final class R3StubLocalExecutor: Executor {
    private(set) var executeCallCount = 0

    func execute(query: String, sessionId: UUID) async throws -> ExecutionResult {
        executeCallCount += 1
        return ExecutionResult(
            output: "[r3-stub-local] \(query)",
            traceId: UUID(),
            timestamp: Date()
        )
    }
}

/// Agent (network-capable) executor stand-in that must NEVER run on a local
/// route. If `execute` is invoked the test fails — this is the CI form of the
/// "zero network transmission" guarantee (execution-flow.md Step 4.5).
final class R3NeverReachedAgentExecutor: Executor {
    private(set) var executeWasCalled = false

    func execute(query: String, sessionId: UUID) async throws -> ExecutionResult {
        executeWasCalled = true
        XCTFail("AgentExecutor (network path) was reached — the local-only guarantee is broken")
        throw ExecutionError.privacyViolation("agent executor must never run for a local route")
    }
}

final class PrivacyEnforcementTests: XCTestCase {

    // MARK: - Layer 1: evaluatePrivacyStep45 (pure enforcement rule)

    func testEvaluate_localPrivacy_routedLocalNoFallback_isSatisfied() {
        // The canonical privacy-local outcome: Router STEP 2 returns
        // routeTarget=.local, fallbackAllowed=false, ruleId=.PRIVACY_LOCAL.
        let decision = RoutingDecision(
            routeTarget: .local,
            model: "llama-3.2-8b",
            reason: "User requested local-only execution (privacy constraint)",
            ruleId: .PRIVACY_LOCAL,
            fallbackAllowed: false
        )

        let verdict = HybridExecutionCoordinator.evaluatePrivacyStep45(
            privacyLevel: .local,
            routingDecision: decision
        )

        XCTAssertEqual(verdict, .satisfied,
                       "privacy-local + on-device route + no fallback must be .satisfied")
    }

    func testEvaluate_localPrivacy_forcedCloud_isViolated() {
        // The real bypass path: Router STEP 1 (policy) runs before STEP 2, so a
        // policy .forceCloud (or human .forceRemote override) can route a
        // privacy-local Question to cloud. Step 4.5 must REFUSE this.
        let decision = RoutingDecision(
            routeTarget: .cloud,
            model: "gpt-4",
            reason: "Policy constraint forced cloud execution",
            ruleId: .POLICY_FORCE_CLOUD,
            fallbackAllowed: false
        )

        let verdict = HybridExecutionCoordinator.evaluatePrivacyStep45(
            privacyLevel: .local,
            routingDecision: decision
        )

        guard case .violated = verdict else {
            return XCTFail("privacy_level=local routed to cloud must be .violated, got \(verdict)")
        }
    }

    func testEvaluate_localPrivacy_localRouteButFallbackAllowed_isViolated() {
        // A local route that still permits cloud fallback is not zero-network:
        // a local failure could spill to cloud. Step 4.5 forbids it.
        let decision = RoutingDecision(
            routeTarget: .local,
            model: "llama-3.2-8b",
            reason: "Token count within threshold, local model capable",
            ruleId: .AUTO_LOCAL,
            fallbackAllowed: true
        )

        let verdict = HybridExecutionCoordinator.evaluatePrivacyStep45(
            privacyLevel: .local,
            routingDecision: decision
        )

        guard case .violated = verdict else {
            return XCTFail("local-only request must forbid cloud fallback, got \(verdict)")
        }
    }

    func testEvaluate_privacyLocalRuleId_forcedCloud_isViolated() {
        // Defense-in-depth: even if the Question's privacyLevel were not .local,
        // a routing decision tagged ruleId=.PRIVACY_LOCAL still triggers
        // enforcement (the OR clause).
        let decision = RoutingDecision(
            routeTarget: .cloud,
            model: "gpt-4",
            reason: "mismatched decision",
            ruleId: .PRIVACY_LOCAL,
            fallbackAllowed: false
        )

        let verdict = HybridExecutionCoordinator.evaluatePrivacyStep45(
            privacyLevel: .auto,
            routingDecision: decision
        )

        guard case .violated = verdict else {
            return XCTFail("ruleId=.PRIVACY_LOCAL routed to cloud must be .violated, got \(verdict)")
        }
    }

    func testEvaluate_autoPrivacy_imposesNoConstraint() {
        // A non-privacy (auto) request: Step 4.5 does not constrain it.
        let decision = RoutingDecision(
            routeTarget: .local,
            model: "llama-3.2-8b",
            reason: "Token count within threshold, local model capable",
            ruleId: .AUTO_LOCAL,
            fallbackAllowed: true
        )

        let verdict = HybridExecutionCoordinator.evaluatePrivacyStep45(
            privacyLevel: .auto,
            routingDecision: decision
        )

        XCTAssertEqual(verdict, .notApplicable,
                       "an auto-privacy request must not be constrained by Step 4.5")
    }

    // MARK: - ExecutionError.privacyViolation (structured error contract)

    func testPrivacyViolation_isStructuredEquatableError() {
        let error = ExecutionError.privacyViolation("routed off-device")

        XCTAssertNotNil(error.errorDescription,
                        "privacyViolation must carry a human-readable description")
        XCTAssertEqual(error, ExecutionError.privacyViolation("routed off-device"),
                       "privacyViolation is Equatable on its detail")
        XCTAssertNotEqual(error, ExecutionError.emptyOutput,
                          "privacyViolation is a distinct ExecutionError case")
    }

    // MARK: - Layer 2: a local route never reaches the agent executor

    func testHybridCoordinator_localRoute_neverReachesAgentExecutor() async throws {
        // A short, tool-free, non-privacy query routes AUTO_LOCAL (Router
        // STEP 3). The agent (network) executor must never be invoked — if it
        // is, R3NeverReachedAgentExecutor fails the test.
        let localExecutor = R3StubLocalExecutor()
        let agentExecutor = R3NeverReachedAgentExecutor()
        let coordinator = HybridExecutionCoordinator(
            localExecutor: localExecutor,
            agentExecutor: agentExecutor
        )

        let response = try await coordinator.execute(request: NoemaRequest(query: "Hi"))

        XCTAssertEqual(localExecutor.executeCallCount, 1,
                       "a locally-routed request must use the local executor")
        XCTAssertFalse(agentExecutor.executeWasCalled,
                       "a locally-routed request must never reach the network executor")
        XCTAssertFalse(response.text.isEmpty)
    }
}
