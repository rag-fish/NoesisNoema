// NoesisNoema is a knowledge graph framework for building AI applications.
// This file contains unit tests for the deterministic Policy Engine.
// EPIC1: Client Authority Hardening (Phase 3) - Section 3.7
// Created: 2026-02-21
// License: MIT License

import XCTest
@testable import NoesisNoema

/// Test suite for Policy Engine determinism and conflict resolution
///
/// Test Requirements (Section 3.7):
/// 1. Deterministic behavior (same inputs → same outputs)
/// 2. Conflict resolution precedence (BLOCK > FORCE_LOCAL > FORCE_CLOUD > REQUIRE_CONFIRMATION > WARN)
/// 3. Multiple rule evaluation (all enabled rules evaluated)
/// 4. No side effects (pure function)
final class PolicyEngineTests: XCTestCase {

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

    /// Create a test runtime state
    private func makeRuntimeState() -> RuntimeState {
        let localCapability = LocalModelCapability(
            modelName: "llama-3.2-8b",
            maxTokens: 4096,
            supportedIntents: [.informational, .retrieval],
            available: true
        )

        return RuntimeState(
            localModelCapability: localCapability,
            networkState: .online,
            tokenThreshold: 4096,
            cloudModelName: "gpt-4"
        )
    }

    /// Create a policy rule with specified parameters
    private func makeRule(
        id: UUID = UUID(),
        name: String = "Test Rule",
        type: ConstraintType = .privacy,
        enabled: Bool = true,
        priority: Int = 1,
        conditions: [ConditionRule],
        action: ConstraintAction
    ) -> PolicyRule {
        PolicyRule(
            id: id,
            name: name,
            type: type,
            enabled: enabled,
            priority: priority,
            conditions: conditions,
            action: action
        )
    }

    // MARK: - Determinism Tests

    /// Test: Identical inputs produce identical outputs
    func testDeterminism_IdenticalInputs_ProducesIdenticalOutputs() throws {
        // Arrange: Create fixed inputs
        let question = makeQuestion(content: "What is the capital of France?")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                conditions: [ConditionRule(field: "content", operator: .contains, value: "capital")],
                action: .warn(message: "Geography question")
            )
        ]

        // Act: Call policy engine twice with identical inputs
        let result1 = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)
        let result2 = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert: Outputs must be identical
        XCTAssertEqual(result1.effectiveAction, result2.effectiveAction)
        XCTAssertEqual(result1.appliedConstraints, result2.appliedConstraints)
        XCTAssertEqual(result1.warnings, result2.warnings)
        XCTAssertEqual(result1.requiresConfirmation, result2.requiresConfirmation)
    }

    /// Test: Multiple invocations with same inputs produce same results
    func testDeterminism_MultipleInvocations_ProducesSameResults() throws {
        // Arrange
        let question = makeQuestion(content: "Sensitive data: SSN 123-45-6789")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                conditions: [ConditionRule(field: "content", operator: .contains, value: "SSN")],
                action: .forceLocal
            )
        ]

        // Act: Call policy engine 10 times
        var results: [PolicyEvaluationResult] = []
        for _ in 0..<10 {
            let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)
            results.append(result)
        }

        // Assert: All results must be identical
        let firstResult = results[0]
        for result in results.dropFirst() {
            XCTAssertEqual(result.effectiveAction, firstResult.effectiveAction)
            XCTAssertEqual(result.appliedConstraints, firstResult.appliedConstraints)
        }
    }

    // MARK: - Conflict Resolution Precedence Tests

    /// Test: BLOCK has highest precedence
    func testPrecedence_BlockAlwaysWins() throws {
        // Arrange: BLOCK + FORCE_LOCAL + WARN
        let question = makeQuestion(content: "SSN 123-45-6789")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                priority: 1,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "SSN")],
                action: .block(reason: "Contains SSN")
            ),
            makeRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                priority: 2,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "SSN")],
                action: .forceLocal
            ),
            makeRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                priority: 3,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "SSN")],
                action: .warn(message: "Sensitive data")
            )
        ]

        // Act & Assert: Should throw policyViolation error
        XCTAssertThrowsError(
            try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)
        ) { error in
            guard let routingError = error as? RoutingError,
                  case .policyViolation(let reason) = routingError else {
                XCTFail("Expected RoutingError.policyViolation, got \(error)")
                return
            }
            XCTAssertEqual(reason, "Contains SSN")
        }
    }

    /// Test: FORCE_LOCAL wins over FORCE_CLOUD (privacy-first)
    func testPrecedence_ForceLocalWinsOverForceCloud() throws {
        // Arrange: FORCE_LOCAL (priority 1) + FORCE_CLOUD (priority 2)
        let question = makeQuestion(content: "test")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                priority: 1,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .forceLocal
            ),
            makeRule(
                priority: 2,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .forceCloud
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert: forceLocal should win
        XCTAssertEqual(result.effectiveAction, .forceLocal)
        XCTAssertEqual(result.appliedConstraints.count, 2)
    }

    /// Test: FORCE_LOCAL wins even if FORCE_CLOUD has higher priority
    func testPrecedence_ForceLocalWinsRegardlessOfPriority() throws {
        // Arrange: FORCE_CLOUD (priority 1) + FORCE_LOCAL (priority 2)
        let question = makeQuestion(content: "test")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                priority: 1,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .forceCloud
            ),
            makeRule(
                priority: 2,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .forceLocal
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert: forceLocal should still win (privacy-first principle)
        XCTAssertEqual(result.effectiveAction, .forceLocal)
    }

    /// Test: REQUIRE_CONFIRMATION aggregates multiple prompts
    func testPrecedence_RequireConfirmationAggregates() throws {
        // Arrange: Multiple confirmation prompts
        let question = makeQuestion(content: "large query")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                priority: 1,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "large")],
                action: .requireConfirmation(prompt: "This is a large query. Continue?")
            ),
            makeRule(
                priority: 2,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "query")],
                action: .requireConfirmation(prompt: "This may take time. Proceed?")
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert: Should require confirmation
        XCTAssertTrue(result.requiresConfirmation)
        XCTAssertEqual(result.effectiveAction, .allow)
    }

    /// Test: WARN aggregates multiple warnings
    func testPrecedence_WarnAggregatesMultiple() throws {
        // Arrange: Multiple warnings
        let question = makeQuestion(content: "test query")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                priority: 1,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .warn(message: "Warning 1")
            ),
            makeRule(
                priority: 2,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "query")],
                action: .warn(message: "Warning 2")
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert: Should have both warnings
        XCTAssertEqual(result.warnings.count, 2)
        XCTAssertTrue(result.warnings.contains("Warning 1"))
        XCTAssertTrue(result.warnings.contains("Warning 2"))
        XCTAssertEqual(result.effectiveAction, .allow)
    }

    /// Test: Combined actions (FORCE_LOCAL + WARN + REQUIRE_CONFIRMATION)
    func testPrecedence_CombinedActions() throws {
        // Arrange: Multiple action types
        let question = makeQuestion(content: "sensitive test")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                priority: 1,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "sensitive")],
                action: .forceLocal
            ),
            makeRule(
                priority: 2,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .warn(message: "Test query")
            ),
            makeRule(
                priority: 3,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "sensitive")],
                action: .requireConfirmation(prompt: "Sensitive data detected")
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert: All actions should be preserved
        XCTAssertEqual(result.effectiveAction, .forceLocal)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.requiresConfirmation)
    }

    // MARK: - Multiple Rule Evaluation Tests

    /// Test: All enabled rules are evaluated
    func testEvaluation_AllEnabledRulesEvaluated() throws {
        // Arrange: 3 enabled rules with different conditions
        let question = makeQuestion(content: "test query data")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                priority: 1,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .warn(message: "Contains test")
            ),
            makeRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                priority: 2,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "query")],
                action: .warn(message: "Contains query")
            ),
            makeRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                priority: 3,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "data")],
                action: .warn(message: "Contains data")
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert: All 3 rules should have been applied
        XCTAssertEqual(result.appliedConstraints.count, 3)
        XCTAssertEqual(result.warnings.count, 3)
    }

    /// Test: Disabled rules are not evaluated
    func testEvaluation_DisabledRulesIgnored() throws {
        // Arrange: 1 enabled, 2 disabled
        let question = makeQuestion(content: "test")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                enabled: true,
                priority: 1,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .warn(message: "Enabled")
            ),
            makeRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                enabled: false,
                priority: 2,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .warn(message: "Disabled 1")
            ),
            makeRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                enabled: false,
                priority: 3,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .warn(message: "Disabled 2")
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert: Only enabled rule should be applied
        XCTAssertEqual(result.appliedConstraints.count, 1)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings[0], "Enabled")
    }

    /// Test: Rules are evaluated in priority order
    func testEvaluation_PriorityOrderRespected() throws {
        // Arrange: Rules with different priorities
        let question = makeQuestion(content: "test")
        let state = makeRuntimeState()

        // Use fixed UUIDs to ensure deterministic ordering
        let uuid1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let uuid2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let uuid3 = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

        let rules = [
            makeRule(
                id: uuid3,
                priority: 3,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .warn(message: "Priority 3")
            ),
            makeRule(
                id: uuid1,
                priority: 1,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .warn(message: "Priority 1")
            ),
            makeRule(
                id: uuid2,
                priority: 2,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .warn(message: "Priority 2")
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert: Applied constraints should be in priority order
        XCTAssertEqual(result.appliedConstraints, [uuid1, uuid2, uuid3])
        XCTAssertEqual(result.warnings, ["Priority 1", "Priority 2", "Priority 3"])
    }

    /// Test: Same priority uses UUID ordering
    func testEvaluation_SamePriority_UsesUUIDOrdering() throws {
        // Arrange: Rules with same priority but different UUIDs
        let question = makeQuestion(content: "test")
        let state = makeRuntimeState()

        let uuidA = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000000")!
        let uuidZ = UUID(uuidString: "zzzzzzzz-0000-0000-0000-000000000000")!

        let rules = [
            makeRule(
                id: uuidZ,
                priority: 1,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .warn(message: "UUID Z")
            ),
            makeRule(
                id: uuidA,
                priority: 1,
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .warn(message: "UUID A")
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert: Should be ordered by UUID (A before Z)
        XCTAssertEqual(result.appliedConstraints, [uuidA, uuidZ])
        XCTAssertEqual(result.warnings, ["UUID A", "UUID Z"])
    }

    // MARK: - Condition Evaluation Tests

    /// Test: String contains operator (case-insensitive)
    func testCondition_Contains_CaseInsensitive() throws {
        // Arrange
        let question = makeQuestion(content: "This contains SENSITIVE data")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                conditions: [ConditionRule(field: "content", operator: .contains, value: "sensitive")],
                action: .warn(message: "Matched")
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert
        XCTAssertEqual(result.warnings.count, 1)
    }

    /// Test: String contains with OR patterns
    func testCondition_Contains_ORPatterns() throws {
        // Arrange
        let question = makeQuestion(content: "My password is secret")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                conditions: [ConditionRule(field: "content", operator: .contains, value: "SSN|password|credit card")],
                action: .block(reason: "Sensitive data")
            )
        ]

        // Act & Assert
        XCTAssertThrowsError(
            try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)
        )
    }

    /// Test: Token count exceeds operator
    func testCondition_TokenCount_Exceeds() throws {
        // Arrange: Large content (>5000 tokens)
        let largeContent = String(repeating: "word ", count: 6000) // ~1500 tokens
        let question = makeQuestion(content: largeContent)
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                conditions: [ConditionRule(field: "token_count", operator: .exceeds, value: "1000")],
                action: .warn(message: "Large query")
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert
        XCTAssertEqual(result.warnings.count, 1)
    }

    /// Test: Intent equals operator
    func testCondition_Intent_Equals() throws {
        // Arrange
        let question = makeQuestion(intent: .analytical)
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                conditions: [ConditionRule(field: "intent", operator: .equals, value: "analytical")],
                action: .forceCloud
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert
        XCTAssertEqual(result.effectiveAction, .forceCloud)
    }

    /// Test: Multiple conditions (AND logic)
    func testCondition_MultipleConditions_ANDLogic() throws {
        // Arrange: All conditions must match
        let question = makeQuestion(content: "test query", privacyLevel: .auto)
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                conditions: [
                    ConditionRule(field: "content", operator: .contains, value: "test"),
                    ConditionRule(field: "privacy_level", operator: .equals, value: "auto")
                ],
                action: .warn(message: "Matched both")
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert
        XCTAssertEqual(result.warnings.count, 1)
    }

    /// Test: Multiple conditions where one fails (no match)
    func testCondition_MultipleConditions_OneFails() throws {
        // Arrange: Second condition fails
        let question = makeQuestion(content: "test query", privacyLevel: .local)
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                conditions: [
                    ConditionRule(field: "content", operator: .contains, value: "test"),
                    ConditionRule(field: "privacy_level", operator: .equals, value: "auto")
                ],
                action: .warn(message: "Should not match")
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert: No warnings because second condition failed
        XCTAssertEqual(result.warnings.count, 0)
    }

    // MARK: - No Side Effects Tests

    /// Test: Policy engine produces no side effects
    func testPurity_NoSideEffects() throws {
        // Arrange
        let question = makeQuestion(content: "test")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                conditions: [ConditionRule(field: "content", operator: .contains, value: "test")],
                action: .warn(message: "Test")
            )
        ]

        // Act: Call multiple times
        for _ in 0..<100 {
            let _ = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)
        }

        // Assert: No exceptions means no side effects caused issues
        // If there were side effects (global state mutation), behavior would diverge
        let finalResult = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)
        XCTAssertEqual(finalResult.warnings.count, 1)
    }

    /// Test: Empty rules return allow
    func testPurity_EmptyRules_ReturnsAllow() throws {
        // Arrange: No rules
        let question = makeQuestion()
        let state = makeRuntimeState()
        let rules: [PolicyRule] = []

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert
        XCTAssertEqual(result.effectiveAction, .allow)
        XCTAssertEqual(result.appliedConstraints.count, 0)
        XCTAssertEqual(result.warnings.count, 0)
        XCTAssertFalse(result.requiresConfirmation)
    }

    /// Test: No matching rules return allow
    func testPurity_NoMatchingRules_ReturnsAllow() throws {
        // Arrange: Rules that don't match
        let question = makeQuestion(content: "hello")
        let state = makeRuntimeState()
        let rules = [
            makeRule(
                conditions: [ConditionRule(field: "content", operator: .contains, value: "goodbye")],
                action: .warn(message: "Should not match")
            )
        ]

        // Act
        let result = try PolicyEngine.evaluate(question: question, runtimeState: state, rules: rules)

        // Assert
        XCTAssertEqual(result.effectiveAction, .allow)
        XCTAssertEqual(result.appliedConstraints.count, 0)
    }
}
