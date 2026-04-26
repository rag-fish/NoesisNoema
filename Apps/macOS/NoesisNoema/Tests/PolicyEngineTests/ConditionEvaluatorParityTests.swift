// NoesisNoema is a knowledge graph framework for building AI applications.
// EPIC4 #68 PolicyEngine extensibility.
//
// History:
//   - Phase 1 introduced this test as a parity gate. It compared the
//     legacy PolicyEngine switch chain against the new
//     PolicyRule.evaluate(...) path, asserting they produced identical
//     match decisions across the fixtures below.
//   - Phase 2 deleted the legacy path. The two paths were behaviourally
//     equivalent at that point (this test was green at merge time),
//     making the deletion safe.
//   - Post-Phase 2, this test is no longer comparing two paths — there
//     is only one path. Each fixture now exercises that single path
//     and asserts the expected match/no-match decision encoded in the
//     test name. The test continues to serve as a regression detector
//     for the per-condition decisions that the legacy switch used to
//     enforce, particularly the `default: return false` cases.
//
// What each test name encodes:
//   - "*_Match" — the rule SHOULD match this question.
//   - "*_NoMatch" — the rule should NOT match this question.
//   - "*_DoesNotMatch" — historically a `default: return false` case
//     in the legacy engine; should not match (asserted explicitly).
//
// License: MIT License

import XCTest
@testable import NoesisNoema

/// Per-condition match-decision regression tests for the
/// PolicyRule.evaluate(...) path.
///
/// We do not call PolicyEngine.evaluate(...) here because that function
/// also exercises sort + conflict resolution; we want a focused test on
/// the per-rule match decision. Each fixture is a single rule plus a
/// question; we assert via PolicyEngine that the rule produces the
/// expected match outcome.
///
/// See file header for the historical context: this test started life
/// as a parity gate between the legacy PolicyEngine switch chain and
/// the new ConditionEvaluator-based path. Phase 2 removed the legacy
/// path; this test is preserved as a regression detector.
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

    /// Run the rule through the (now sole) PolicyEngine path, and assert
    /// the per-rule match outcome. We use PolicyEngine.evaluate with a
    /// `.warn` action: appliedConstraints is non-empty iff the rule
    /// matched.
    ///
    /// `expected` encodes the historical decision the legacy switch
    /// chain produced for this fixture; preserving that decision is
    /// the regression contract.
    private func assertMatchDecision(
        rule: PolicyRule,
        question: NoemaQuestion,
        state: RuntimeState,
        expected: Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            let result = try PolicyEngine.evaluate(
                question: question,
                runtimeState: state,
                rules: [rule]
            )
            let matched = !result.appliedConstraints.isEmpty
            XCTAssertEqual(
                matched,
                expected,
                "Match decision regression: matched=\(matched) expected=\(expected)",
                file: file,
                line: line
            )
        } catch {
            // A throw would only happen for .block actions, which we do
            // not use as the action for these regression rules.
            XCTFail("Unexpected throw from engine: \(error)", file: file, line: line)
        }
    }

    // Convenience wrappers that read better at call sites than passing
    // a raw `expected:` everywhere. Each call site already states the
    // expected outcome in its test name; these helpers make that
    // contract explicit.
    private func assertMatches(rule: PolicyRule, question: NoemaQuestion, state: RuntimeState,
                               file: StaticString = #file, line: UInt = #line) {
        assertMatchDecision(rule: rule, question: question, state: state,
                            expected: true, file: file, line: line)
    }
    private func assertDoesNotMatch(rule: PolicyRule, question: NoemaQuestion, state: RuntimeState,
                                    file: StaticString = #file, line: UInt = #line) {
        assertMatchDecision(rule: rule, question: question, state: state,
                            expected: false, file: file, line: line)
    }

    // MARK: - Content field

    func testParity_Content_Contains_Match() {
        let q = makeQuestion(content: "This contains SENSITIVE data")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .contains, value: "sensitive")
        ])
        assertMatches(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_Contains_CaseInsensitive() {
        let q = makeQuestion(content: "lowercase only")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .contains, value: "LOWERCASE")
        ])
        assertMatches(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_Contains_NoMatch() {
        let q = makeQuestion(content: "hello")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .contains, value: "goodbye")
        ])
        assertDoesNotMatch(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_Contains_PipeSeparatedOR_Match() {
        let q = makeQuestion(content: "My password is secret")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .contains, value: "SSN|password|credit card")
        ])
        assertMatches(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_Contains_PipeSeparatedOR_NoneMatch() {
        let q = makeQuestion(content: "ordinary message")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .contains, value: "SSN|password|credit card")
        ])
        assertDoesNotMatch(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_NotContains() {
        let q = makeQuestion(content: "hello world")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .notContains, value: "goodbye")
        ])
        assertMatches(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_Equals_CaseInsensitive() {
        let q = makeQuestion(content: "Hello")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .equals, value: "hello")
        ])
        assertMatches(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Content_NotEquals() {
        let q = makeQuestion(content: "Hello")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .notEquals, value: "world")
        ])
        assertMatches(rule: r, question: q, state: makeRuntimeState())
    }

    // MARK: - token_count field

    func testParity_TokenCount_Exceeds_Match() {
        let big = String(repeating: "word ", count: 6000) // ~7500 chars / 4 ≈ 1875 tokens
        let q = makeQuestion(content: big)
        let r = makeRule(conditions: [
            ConditionRule(field: "token_count", operator: .exceeds, value: "1000")
        ])
        assertMatches(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_TokenCount_Exceeds_NoMatch() {
        let q = makeQuestion(content: "short")
        let r = makeRule(conditions: [
            ConditionRule(field: "token_count", operator: .exceeds, value: "1000")
        ])
        assertDoesNotMatch(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_TokenCount_LessThan() {
        let q = makeQuestion(content: "short")
        let r = makeRule(conditions: [
            ConditionRule(field: "token_count", operator: .lessThan, value: "1000")
        ])
        assertMatches(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_TokenCount_NonIntegerValue_DoesNotMatch() {
        // Historical legacy semantic: Int(condition.value) returns nil
        // and the rule does not match. Preserved by ConditionRule.toEvaluator
        // returning nil for non-integer numeric values.
        let q = makeQuestion(content: "short")
        let r = makeRule(conditions: [
            ConditionRule(field: "token_count", operator: .exceeds, value: "not a number")
        ])
        assertDoesNotMatch(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_TokenCount_StringOperator_DoesNotMatch() {
        // Historical legacy semantic: .contains on token_count is
        // malformed and the rule does not match. Preserved by the
        // numeric/string operator gating in toEvaluator.
        let q = makeQuestion(content: "anything")
        let r = makeRule(conditions: [
            ConditionRule(field: "token_count", operator: .contains, value: "100")
        ])
        assertDoesNotMatch(rule: r, question: q, state: makeRuntimeState())
    }

    // MARK: - intent field

    func testParity_Intent_Equals_Match() {
        let q = makeQuestion(intent: .analytical)
        let r = makeRule(conditions: [
            ConditionRule(field: "intent", operator: .equals, value: "analytical")
        ])
        assertMatches(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Intent_Nil_DoesNotMatch() {
        // Historical legacy semantic: `guard let intent = ... else { return false }`.
        // Preserved by IntentCondition.evaluate's same guard.
        let q = makeQuestion(intent: nil)
        let r = makeRule(conditions: [
            ConditionRule(field: "intent", operator: .equals, value: "analytical")
        ])
        assertDoesNotMatch(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_Intent_NumericOperator_DoesNotMatch() {
        // Historical legacy semantic: numeric operator on string field
        // hit the inner switch's `default: return false`. Preserved by
        // toEvaluator returning nil.
        let q = makeQuestion(intent: .analytical)
        let r = makeRule(conditions: [
            ConditionRule(field: "intent", operator: .exceeds, value: "1")
        ])
        assertDoesNotMatch(rule: r, question: q, state: makeRuntimeState())
    }

    // MARK: - privacy_level field

    func testParity_PrivacyLevel_Equals_Match() {
        let q = makeQuestion(privacyLevel: .auto)
        let r = makeRule(conditions: [
            ConditionRule(field: "privacy_level", operator: .equals, value: "auto")
        ])
        assertMatches(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_PrivacyLevel_Equals_NoMatch() {
        let q = makeQuestion(privacyLevel: .local)
        let r = makeRule(conditions: [
            ConditionRule(field: "privacy_level", operator: .equals, value: "auto")
        ])
        assertDoesNotMatch(rule: r, question: q, state: makeRuntimeState())
    }

    // MARK: - Unknown field

    func testParity_UnknownField_DoesNotMatch() {
        // Historical legacy semantic: outer `default: return false` for
        // unknown field name. Preserved by toEvaluator returning nil.
        let q = makeQuestion(content: "anything")
        let r = makeRule(conditions: [
            ConditionRule(field: "future_unimplemented_field", operator: .contains, value: "x")
        ])
        assertDoesNotMatch(rule: r, question: q, state: makeRuntimeState())
    }

    // MARK: - Multiple conditions (AND logic)

    func testParity_MultipleConditions_AllMatch() {
        let q = makeQuestion(content: "test query", privacyLevel: .auto)
        let r = makeRule(conditions: [
            ConditionRule(field: "content",       operator: .contains, value: "test"),
            ConditionRule(field: "privacy_level", operator: .equals,   value: "auto")
        ])
        assertMatches(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_MultipleConditions_OneFails() {
        let q = makeQuestion(content: "test query", privacyLevel: .local)
        let r = makeRule(conditions: [
            ConditionRule(field: "content",       operator: .contains, value: "test"),
            ConditionRule(field: "privacy_level", operator: .equals,   value: "auto")
        ])
        assertDoesNotMatch(rule: r, question: q, state: makeRuntimeState())
    }

    func testParity_MultipleConditions_OneIsUnknownField() {
        // Even if other conditions match, an unknown field should drop
        // the whole rule (AND logic + per-condition false).
        let q = makeQuestion(content: "test query")
        let r = makeRule(conditions: [
            ConditionRule(field: "content", operator: .contains, value: "test"),
            ConditionRule(field: "future",  operator: .contains, value: "x")
        ])
        assertDoesNotMatch(rule: r, question: q, state: makeRuntimeState())
    }

    // MARK: - Empty conditions

    func testParity_EmptyConditions_Matches() {
        // Historical legacy semantic: allSatisfy on empty list is true.
        // PolicyRule.evaluate: same (loop body never executes; returns true).
        let q = makeQuestion(content: "anything")
        let r = makeRule(conditions: [])
        assertMatches(rule: r, question: q, state: makeRuntimeState())
    }
}
