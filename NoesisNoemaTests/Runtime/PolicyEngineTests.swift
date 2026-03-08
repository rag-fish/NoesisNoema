// NoesisNoema - HybridRuntime: Hybrid Routing Runtime
// PolicyEngine Tests
// Created: 2026-03-07
// License: MIT License

import XCTest
@testable import NoesisNoema

/// Tests for HybridPolicyEngine determinism and purity
///
/// These tests verify constitutional constraints (ADR-0000):
/// - Side-effect freedom (run twice, compare results)
/// - Determinism (same input → same output)
/// - No randomness or time-based branching
final class HybridPolicyEngineTests: XCTestCase {

    var policyEngine: HybridPolicyEngine!

    override func setUp() {
        super.setUp()
        policyEngine = HybridPolicyEngine()
    }

    override func tearDown() {
        policyEngine = nil
        super.tearDown()
    }

    // MARK: - Determinism Tests

    func testDeterminism_SameInputProducesSameOutput() {
        // Given: A request with specific content
        let request = NoemaRequest(query: "Show me my calendar for today")

        // When: Evaluating the same request twice
        let result1 = policyEngine.evaluate(request)
        let result2 = policyEngine.evaluate(request)

        // Then: Results must be identical (proves determinism)
        XCTAssertEqual(result1, result2, "PolicyEngine must be deterministic")
    }

    func testDeterminism_MultipleEvaluationsProduceSameResults() {
        // Given: A request
        let request = NoemaRequest(query: "What is my email address?")

        // When: Evaluating 10 times
        let results = (0..<10).map { _ in policyEngine.evaluate(request) }

        // Then: All results must be identical
        let firstResult = results[0]
        for result in results {
            XCTAssertEqual(result, firstResult, "All evaluations must produce identical results")
        }
    }

    // MARK: - Tool Detection Tests

    func testToolRequired_DetectsCalendarKeyword() {
        // Given: Request with "calendar" keyword
        let request = NoemaRequest(query: "Show me my calendar")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: toolRequired should be true
        XCTAssertTrue(result.toolRequired, "Should detect 'calendar' as tool keyword")
    }

    func testToolRequired_DetectsEmailKeyword() {
        // Given: Request with "email" keyword
        let request = NoemaRequest(query: "Send an email to John")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: toolRequired should be true
        XCTAssertTrue(result.toolRequired, "Should detect 'email' as tool keyword")
    }

    func testToolRequired_DetectsContactsKeyword() {
        // Given: Request with "contacts" keyword
        let request = NoemaRequest(query: "Show my contacts list")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: toolRequired should be true
        XCTAssertTrue(result.toolRequired, "Should detect 'contacts' as tool keyword")
    }

    func testToolRequired_DetectsAgentKeyword() {
        // Given: Request with "agent" keyword
        let request = NoemaRequest(query: "Use an agent to help me")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: toolRequired should be true
        XCTAssertTrue(result.toolRequired, "Should detect 'agent' as tool keyword")
    }

    func testToolRequired_NoToolKeywords() {
        // Given: Request without tool keywords
        let request = NoemaRequest(query: "What is the weather today?")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: toolRequired should be false
        XCTAssertFalse(result.toolRequired, "Should not detect tool requirement for general query")
    }

    // MARK: - Privacy Detection Tests

    func testPrivacySensitive_DetectsAddressKeyword() {
        // Given: Request with "address" keyword
        let request = NoemaRequest(query: "What is my home address?")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: privacySensitive should be true
        XCTAssertTrue(result.privacySensitive, "Should detect 'address' as privacy keyword")
    }

    func testPrivacySensitive_DetectsPhoneKeyword() {
        // Given: Request with "phone" keyword
        let request = NoemaRequest(query: "Store my phone number")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: privacySensitive should be true
        XCTAssertTrue(result.privacySensitive, "Should detect 'phone' as privacy keyword")
    }

    func testPrivacySensitive_DetectsPassportKeyword() {
        // Given: Request with "passport" keyword
        let request = NoemaRequest(query: "My passport number is...")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: privacySensitive should be true
        XCTAssertTrue(result.privacySensitive, "Should detect 'passport' as privacy keyword")
    }

    func testPrivacySensitive_DetectsPersonalKeyword() {
        // Given: Request with "personal" keyword
        let request = NoemaRequest(query: "Here is my personal information")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: privacySensitive should be true
        XCTAssertTrue(result.privacySensitive, "Should detect 'personal' as privacy keyword")
    }

    func testPrivacySensitive_NoPrivacyKeywords() {
        // Given: Request without privacy keywords
        let request = NoemaRequest(query: "What is the capital of France?")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: privacySensitive should be false
        XCTAssertFalse(result.privacySensitive, "Should not detect privacy sensitivity for general query")
    }

    // MARK: - Latency Preference Tests

    func testLowLatencyPreferred_ShortQuery() {
        // Given: Short query (< 100 characters)
        let request = NoemaRequest(query: "Hello")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: lowLatencyPreferred should be true
        XCTAssertTrue(result.lowLatencyPreferred, "Short queries should prefer low latency")
    }

    func testLowLatencyPreferred_LongQuery() {
        // Given: Long query (>= 100 characters)
        let longQuery = String(repeating: "a", count: 150)
        let request = NoemaRequest(query: longQuery)

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: lowLatencyPreferred should be false
        XCTAssertFalse(result.lowLatencyPreferred, "Long queries should not prefer low latency")
    }

    // MARK: - Combined Signal Tests

    func testCombinedSignals_ToolAndPrivacy() {
        // Given: Request with both tool and privacy keywords
        let request = NoemaRequest(query: "Send an email with my phone number")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: Both signals should be true
        XCTAssertTrue(result.toolRequired, "Should detect tool requirement")
        XCTAssertTrue(result.privacySensitive, "Should detect privacy sensitivity")
    }

    func testCombinedSignals_AllSignals() {
        // Given: Short request with tool and privacy keywords
        let request = NoemaRequest(query: "email my address")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: All signals should be true
        XCTAssertTrue(result.toolRequired, "Should detect tool requirement")
        XCTAssertTrue(result.privacySensitive, "Should detect privacy sensitivity")
        XCTAssertTrue(result.lowLatencyPreferred, "Should prefer low latency")
    }

    func testCombinedSignals_NoSignals() {
        // Given: Long general query without keywords
        let longQuery = "Tell me about the history of artificial intelligence and its development over the past several decades"
        let request = NoemaRequest(query: longQuery)

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: No signals should be true
        XCTAssertFalse(result.toolRequired, "Should not detect tool requirement")
        XCTAssertFalse(result.privacySensitive, "Should not detect privacy sensitivity")
        XCTAssertFalse(result.lowLatencyPreferred, "Should not prefer low latency")
    }

    // MARK: - Case Insensitivity Tests

    func testCaseInsensitivity_UpperCase() {
        // Given: Request with uppercase keywords
        let request = NoemaRequest(query: "SHOW MY EMAIL ADDRESS")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: Should detect keywords regardless of case
        XCTAssertTrue(result.toolRequired, "Should detect keywords case-insensitively")
        XCTAssertTrue(result.privacySensitive, "Should detect keywords case-insensitively")
    }

    func testCaseInsensitivity_MixedCase() {
        // Given: Request with mixed case keywords
        let request = NoemaRequest(query: "Send me an Email with my PhOnE number")

        // When: Evaluating
        let result = policyEngine.evaluate(request)

        // Then: Should detect keywords regardless of case
        XCTAssertTrue(result.toolRequired, "Should detect keywords case-insensitively")
        XCTAssertTrue(result.privacySensitive, "Should detect keywords case-insensitively")
    }
}
