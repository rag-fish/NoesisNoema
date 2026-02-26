//
//  ExecutionCoordinatorTests.swift
//  NoesisNoema
//
//  Created for EPIC1 Phase 5-B
//  Purpose: Test policy-based routing wiring
//  License: MIT License
//

import XCTest
@testable import NoesisNoema

@MainActor
final class ExecutionCoordinatorTests: XCTestCase {

    // MARK: - Test Fixtures

    /// Mock PolicyRulesProvider that returns predefined rules
    class MockPolicyRulesProvider: PolicyRulesProvider {
        private let rules: [PolicyRule]

        init(rules: [PolicyRule]) {
            self.rules = rules
        }

        func getPolicyRules() -> [PolicyRule] {
            return rules
        }
    }

    /// Mock ModelManager for testing
    class MockModelManager: ModelManager {
        var generateCallCount = 0
        var lastQuestion: String?

        override func generateAsyncAnswer(question: String) async -> String {
            generateCallCount += 1
            lastQuestion = question
            return "Mock response to: \(question)"
        }
    }

    // MARK: - Policy Blocking Tests

    func testPolicyBlockingPreventsExecution() async throws {
        // Given: Policy that blocks "password"
        let blockRule = PolicyRule(
            name: "Block Sensitive",
            type: .privacy,
            enabled: true,
            priority: 1,
            conditions: [
                ConditionRule(field: "content", operator: .contains, value: "password")
            ],
            action: .block(reason: "Sensitive data detected")
        )

        let provider = MockPolicyRulesProvider(rules: [blockRule])
        let coordinator = ExecutionCoordinator(policyRulesProvider: provider)

        // When: Execute with blocked content
        let request = NoemaRequest(query: "What's my password?")
        let response = try await coordinator.execute(request: request)

        // Then: Response contains block message
        XCTAssertTrue(response.text.contains("blocked by policy"))
        XCTAssertTrue(response.text.contains("Sensitive data detected"))
    }

    func testPolicyBlockingAllowsNonMatchingContent() async throws {
        // Given: Policy that blocks "password"
        let blockRule = PolicyRule(
            name: "Block Sensitive",
            type: .privacy,
            enabled: true,
            priority: 1,
            conditions: [
                ConditionRule(field: "content", operator: .contains, value: "password")
            ],
            action: .block(reason: "Sensitive data")
        )

        let provider = MockPolicyRulesProvider(rules: [blockRule])
        let mockModelManager = MockModelManager()
        let coordinator = ExecutionCoordinator(
            modelManager: mockModelManager,
            policyRulesProvider: provider
        )

        // When: Execute with non-blocked content
        let request = NoemaRequest(query: "What is the weather?")
        let response = try await coordinator.execute(request: request)

        // Then: Execution proceeds normally
        XCTAssertFalse(response.text.contains("blocked"))
        XCTAssertEqual(mockModelManager.generateCallCount, 1)
        XCTAssertEqual(mockModelManager.lastQuestion, "What is the weather?")
    }

    // MARK: - Policy Force Local Tests

    func testPolicyForceLocalRoutesToLocal() async throws {
        // Given: Policy that forces local execution
        let forceLocalRule = PolicyRule(
            name: "Force Local for Privacy",
            type: .privacy,
            enabled: true,
            priority: 1,
            conditions: [
                ConditionRule(field: "content", operator: .contains, value: "private")
            ],
            action: .forceLocal
        )

        let provider = MockPolicyRulesProvider(rules: [forceLocalRule])
        let mockModelManager = MockModelManager()
        let coordinator = ExecutionCoordinator(
            modelManager: mockModelManager,
            policyRulesProvider: provider
        )

        // When: Execute with content matching force-local rule
        let request = NoemaRequest(query: "This is private information")
        let response = try await coordinator.execute(request: request)

        // Then: Local execution occurs
        XCTAssertEqual(mockModelManager.generateCallCount, 1)
        XCTAssertTrue(response.text.contains("Mock response"))
    }

    // MARK: - NoemaQuestion Construction Tests

    func testNoemaQuestionIsConstructedCorrectly() async throws {
        // Given: Coordinator with no rules (auto routing)
        let provider = MockPolicyRulesProvider(rules: [])
        let mockModelManager = MockModelManager()
        let coordinator = ExecutionCoordinator(
            modelManager: mockModelManager,
            policyRulesProvider: provider
        )

        // When: Execute request
        let sessionId = UUID()
        let request = NoemaRequest(query: "Test question", sessionId: sessionId)
        let response = try await coordinator.execute(request: request)

        // Then: Execution completes (verifies NoemaQuestion was built correctly)
        XCTAssertEqual(response.sessionId, sessionId)
        XCTAssertEqual(mockModelManager.generateCallCount, 1)
    }

    // MARK: - RuntimeState Construction Tests

    func testRuntimeStateIsBuiltWithDefaults() async throws {
        // Given: Coordinator with no rules
        let provider = MockPolicyRulesProvider(rules: [])
        let mockModelManager = MockModelManager()
        let coordinator = ExecutionCoordinator(
            modelManager: mockModelManager,
            policyRulesProvider: provider
        )

        // When: Execute request
        let request = NoemaRequest(query: "Test")
        let response = try await coordinator.execute(request: request)

        // Then: Execution completes (verifies RuntimeState was built)
        XCTAssertNotNil(response.text)
        XCTAssertEqual(mockModelManager.generateCallCount, 1)
    }

    // MARK: - Routing Decision Tests

    func testEmptyRulesDefaultsToAutoRouting() async throws {
        // Given: No policy rules
        let provider = MockPolicyRulesProvider(rules: [])
        let mockModelManager = MockModelManager()
        let coordinator = ExecutionCoordinator(
            modelManager: mockModelManager,
            policyRulesProvider: provider
        )

        // When: Execute request
        let request = NoemaRequest(query: "Simple question")
        let response = try await coordinator.execute(request: request)

        // Then: Auto routing (local execution) occurs
        XCTAssertEqual(mockModelManager.generateCallCount, 1)
        XCTAssertTrue(response.text.contains("Mock response"))
    }

    func testMultiplePolicyRulesEvaluatedInOrder() async throws {
        // Given: Multiple rules with different priorities
        let lowPriorityRule = PolicyRule(
            name: "Low Priority Warn",
            type: .privacy,
            enabled: true,
            priority: 10,
            conditions: [
                ConditionRule(field: "content", operator: .contains, value: "data")
            ],
            action: .warn(message: "Data detected")
        )

        let highPriorityRule = PolicyRule(
            name: "High Priority Block",
            type: .privacy,
            enabled: true,
            priority: 1,
            conditions: [
                ConditionRule(field: "content", operator: .contains, value: "data")
            ],
            action: .block(reason: "Blocked by high priority")
        )

        let provider = MockPolicyRulesProvider(rules: [lowPriorityRule, highPriorityRule])
        let coordinator = ExecutionCoordinator(policyRulesProvider: provider)

        // When: Execute with content matching both rules
        let request = NoemaRequest(query: "Send my data")
        let response = try await coordinator.execute(request: request)

        // Then: Higher priority rule (block) takes precedence
        XCTAssertTrue(response.text.contains("Blocked by high priority"))
    }

    // MARK: - Disabled Rules Tests

    func testDisabledRulesAreIgnored() async throws {
        // Given: Disabled blocking rule
        let disabledRule = PolicyRule(
            name: "Disabled Block",
            type: .privacy,
            enabled: false,  // Disabled
            priority: 1,
            conditions: [
                ConditionRule(field: "content", operator: .contains, value: "password")
            ],
            action: .block(reason: "Should not trigger")
        )

        let provider = MockPolicyRulesProvider(rules: [disabledRule])
        let mockModelManager = MockModelManager()
        let coordinator = ExecutionCoordinator(
            modelManager: mockModelManager,
            policyRulesProvider: provider
        )

        // When: Execute with content that would match disabled rule
        let request = NoemaRequest(query: "What's my password?")
        let response = try await coordinator.execute(request: request)

        // Then: Execution proceeds (rule is disabled)
        XCTAssertFalse(response.text.contains("blocked"))
        XCTAssertEqual(mockModelManager.generateCallCount, 1)
    }

    // MARK: - Cloud Execution Tests (Phase 5-B)

    func testCloudExecutionReturnsNotImplementedError() async throws {
        // Given: Policy that forces cloud execution
        let forceCloudRule = PolicyRule(
            name: "Force Cloud",
            type: .performance,
            enabled: true,
            priority: 1,
            conditions: [
                ConditionRule(field: "content", operator: .contains, value: "complex")
            ],
            action: .forceCloud
        )

        let provider = MockPolicyRulesProvider(rules: [forceCloudRule])
        let coordinator = ExecutionCoordinator(policyRulesProvider: provider)

        // When: Execute with content matching force-cloud rule
        let request = NoemaRequest(query: "This is a complex task")

        // Then: Cloud execution fails with not implemented error
        // (Phase 5-B: Cloud execution not implemented yet)
        do {
            let response = try await coordinator.execute(request: request)
            // Cloud execution throws, but ExecutionCoordinator might catch and return error response
            XCTAssertTrue(
                response.text.contains("unavailable") ||
                response.text.contains("not implemented") ||
                response.text.contains("Cannot execute")
            )
        } catch RoutingError.networkUnavailable {
            // Expected: Cloud execution not available yet
            XCTAssert(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Integration Tests

    func testFullExecutionFlowWithLogging() async throws {
        // Given: Rule that warns but allows execution
        let warnRule = PolicyRule(
            name: "Warn on Long Query",
            type: .performance,
            enabled: true,
            priority: 1,
            conditions: [
                ConditionRule(field: "content", operator: .contains, value: "explain")
            ],
            action: .warn(message: "Long query detected")
        )

        let provider = MockPolicyRulesProvider(rules: [warnRule])
        let mockModelManager = MockModelManager()
        let coordinator = ExecutionCoordinator(
            modelManager: mockModelManager,
            policyRulesProvider: provider
        )

        // When: Execute request
        let request = NoemaRequest(query: "Please explain quantum physics")
        let response = try await coordinator.execute(request: request)

        // Then: Execution completes with warning (logged)
        XCTAssertEqual(mockModelManager.generateCallCount, 1)
        XCTAssertTrue(response.text.contains("Mock response"))
    }

    func testNoPolicyRulesProviderDefaultsToEmpty() async throws {
        // Given: Coordinator with no PolicyRulesProvider
        let mockModelManager = MockModelManager()
        let coordinator = ExecutionCoordinator(
            modelManager: mockModelManager,
            policyRulesProvider: nil  // No provider
        )

        // When: Execute request
        let request = NoemaRequest(query: "Test question")
        let response = try await coordinator.execute(request: request)

        // Then: Execution proceeds with empty rules
        XCTAssertEqual(mockModelManager.generateCallCount, 1)
        XCTAssertTrue(response.text.contains("Mock response"))
    }
}
