// NoesisNoema is a knowledge graph framework for building AI applications.
// Phase 1 of EPIC4 #68 PolicyEngine extensibility.
//
// This test asserts that PolicyRule.evaluate(question:runtimeState:)
// (the new protocol-based path landed in Phase 1) produces the same
// per-rule match/no-match decision as the legacy PolicyEngine path
// (the switch chain that still lives in PolicyEngine.swift) for every
// fixture below.
//
// Phase 1's success criterion is exactly this: the new path is
// behaviourally indistinguishable from the legacy path on the existing
// surface. Phase 2 deletes the legacy path; if any divergence existed
// at that point, this test would already be red and the deletion would
// be unsafe. Hence the test is the gate, not the convenience.
//
// License: MIT License

import XCTest
@testable import NoesisNoema

/// Parity test between the legacy PolicyEngine evaluation path and the
/// new PolicyRule.evaluate(...) path introduced in Phase 1.
///
/// We do not call PolicyEngine.evaluate(...) here because that function
/// also exercises sort + conflict resolution; we want a focused test on
/// the per-rule match decision. Each fixture is a single rule plus a
/// question; we assert the legacy and new evaluators agree on whether
/// the rule matches.
final class ConditionEvaluatorParityTests: XCTestCase {

    // MARK: - Fixture helpers (style-aligned with PolicyEngineTests.swift)

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

    private func makeRule(
        conditions: [ConditionRule],
        action: ConstraintAction = .warn(message: "parity")
    ) -> PolicyRule {
        PolicyRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000aa")!,
            name: "parity-rule",
            type: .privacy,
            enabled: true,
            priority: 1,
            conditions: conditions,
            action: action
        )
    }

    /// Run the rule through both the legacy PolicyEngine path and the
    /// new PolicyRule.evaluate path, and assert they agree on whether
    /// the rule matched.
    ///
    /// We use the legacy path indirectly: PolicyEngine.evaluate with a
    /// `.warn` action returns a result whose appliedConstraints is
    /// non-empty iff the rule matched. The new path is queried directly.
    private func assertParity(
        rule: PolicyRule,
        question: NoemaQuestion,
        state: RuntimeState,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let legacyMatched: Bool
        do {
            let result = try PolicyEngine.evaluate(
                question: question,
                runtimeState: state,
                rules: [rule]
            )
            legacyMatched = !result.appliedConstraints.isEmpty
        } catch {
            // A throw here would only happen for .block actions, which
            // we do not use as the action for parity-test rules above.
            XCTFail("Unexpected throw from legacy path: \(error)", file: file, line: line)
            return
        }

        let newMatched = rule.evaluate(question: question, runtimeState: state)

        XCTAssertEqual(
            legacyMatched,
            newMatched,
            "Parity violation: legacy=\(legacyMatched) new=\(newMatched)",
            file: file,
            line: line
        )
    }

    // MARK: - Content field

    func testParity_Content_Contains_Match() {
        let q = makeQuestion(content: "This contains SENSITIVE data")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .contains, value: "sensitive")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_Contains_CaseInsensitive() {
        let q = makeQuestion(content: "lowercase only")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .contains, value: "LOWERCASE")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_Contains_NoMatch() {
        let q = makeQuestion(content: "hello")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .contains, value: "goodbye")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_Contains_PipeSeparatedOR_Match() {
        let q = makeQuestion(content: "My password is secret")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .contains, value: "SSN|password|credit card")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_Contains_PipeSeparatedOR_NoneMatch() {
        let q = makeQuestion(content: "ordinary message")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .contains, value: "SSN|password|credit card")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_NotContains() {
        let q = makeQuestion(content: "hello world")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .notContains, value: "goodbye")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_Equals_CaseInsensitive() {
        let q = makeQuestion(content: "Hello")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .equals, value: "hello")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_NotEquals() {
        let q = makeQuestion(content: "Hello")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .notEquals, value: "world")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    // MARK: - token_count field

    func testParity_TokenCount_Exceeds_Match() {
        let big = String(repeating: "word ", count: 6000) // ~7500 chars / 4 ≈ 1875 tokens
        let q = makeQuestion(content: big)
        let r = makeRule(conditions: [
            ConditionRule(field: "token_count", operator: .exceeds, value: "1000")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_TokenCount_Exceeds_NoMatch() {
        let q = makeQuestion(content: "short")
        let r = makeRule(conditions: [
            ConditionRule(field: "token_count", operator: .exceeds, value: "1000")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_TokenCount_LessThan() {
        let q = makeQuestion(content: "short")
        let r = makeRule(conditions: [
            ConditionRule(field: "token_count", operator: .lessThan, value: "1000")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_TokenCount_NonIntegerValue_DoesNotMatch() {
        // PolicyEngine.evaluateNumericCondition: Int(condition.value) returns
        // nil, falls through to `return false`. We want parity: new path also
        // returns false (toEvaluator returns nil -> rule.evaluate returns false).
        let q = makeQuestion(content: "short")
        let r = makeRule(conditions: [
            ConditionRule(field: "token_count", operator: .exceeds, value: "not a number")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_TokenCount_StringOperator_DoesNotMatch() {
        // .contains on token_count is a malformed rule. Legacy hits the
        // `default: return false` in evaluateNumericCondition. New path
        // returns false via toEvaluator -> nil.
        let q = makeQuestion(content: "anything")
        let r = makeRule(conditions: [
            ConditionRule(field: "token_count", operator: .contains, value: "100")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    // MARK: - intent field

    func testParity_Intent_Equals_Match() {
        let q = makeQuestion(intent: .analytical)
        let r = makeRule(conditions: [
            ConditionRule(field: "intent", operator: .equals, value: "analytical")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Intent_Nil_DoesNotMatch() {
        // question.intent is nil. Legacy: `guard let intent = ... else { return false }`.
        // New: IntentCondition.evaluate same guard.
        let q = makeQuestion(intent: nil)
        let r = makeRule(conditions: [
            ConditionRule(field: "intent", operator: .equals, value: "analytical")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Intent_NumericOperator_DoesNotMatch() {
        // .exceeds on intent is malformed. Legacy hits default in
        // evaluateStringCondition. New path returns false via toEvaluator.
        let q = makeQuestion(intent: .analytical)
        let r = makeRule(conditions: [
            ConditionRule(field: "intent", operator: .exceeds, value: "1")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    // MARK: - privacy_level field

    func testParity_PrivacyLevel_Equals_Match() {
        let q = makeQuestion(privacyLevel: .auto)
        let r = makeRule(conditions: [
            ConditionRule(field: "privacy_level", operator: .equals, value: "auto")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_PrivacyLevel_Equals_NoMatch() {
        let q = makeQuestion(privacyLevel: .local)
        let r = makeRule(conditions: [
            ConditionRule(field: "privacy_level", operator: .equals, value: "auto")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    // MARK: - Unknown field

    func testParity_UnknownField_DoesNotMatch() {
        // Legacy: `default: return false`. New: toEvaluator returns nil ->
        // rule.evaluate returns false.
        let q = makeQuestion(content: "anything")
        let r = makeRule(conditions: [
            ConditionRule(field: "future_unimplemented_field", operator: .contains, value: "x")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    // MARK: - Multiple conditions (AND logic)

    func testParity_MultipleConditions_AllMatch() {
        let q = makeQuestion(content: "test query", privacyLevel: .auto)
        let r = makeRule(conditions: [
            ConditionRule(field: "content",       operator: .contains, value: "test"),
            ConditionRule(field: "privacy_level", operator: .equals,   value: "auto")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_MultipleConditions_OneFails() {
        let q = makeQuestion(content: "test query", privacyLevel: .local)
        let r = makeRule(conditions: [
            ConditionRule(field: "content",       operator: .contains, value: "test"),
            ConditionRule(field: "privacy_level", operator: .equals,   value: "auto")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_MultipleConditions_OneIsUnknownField() {
        // Even if other conditions match, an unknown field should drop
        // the whole rule (AND logic + per-condition false).
        let q = makeQuestion(content: "test query")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .contains, value: "test"),
            ConditionRule(field: "future",  operator: .contains, value: "x")
        ])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }

    // MARK: - Empty conditions

    func testParity_EmptyConditions_Matches() {
        // PolicyEngine.evaluateConditions: allSatisfy on empty list is true.
        // PolicyRule.evaluate: same (loop body never executes; returns true).
        let q = makeQuestion(content: "anything")
        let r = makeRule(conditions: [])
        assertParity(rule: r, question: q, state: makeRuntimeState())
    }
}
