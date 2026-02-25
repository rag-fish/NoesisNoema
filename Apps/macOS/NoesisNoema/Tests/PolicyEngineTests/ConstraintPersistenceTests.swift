//
//  ConstraintPersistenceTests.swift
//  NoesisNoema
//
//  Created for EPIC1 Phase 4-B
//  Purpose: Unit tests for constraint persistence layer
//  License: MIT License
//

import XCTest
@testable import NoesisNoema

@MainActor
final class ConstraintPersistenceTests: XCTestCase {

    var tempDirectory: URL!
    var testFileURL: URL!

    override func setUp() async throws {
        // Create temporary directory for tests
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        testFileURL = tempDirectory.appendingPathComponent("test-constraints.json")
    }

    override func tearDown() async throws {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - EditablePolicyRule Tests

    func testEditablePolicyRuleToPolicyRuleConversion() throws {
        // Given: An editable policy rule
        let editable = EditablePolicyRule(
            id: UUID(),
            name: "Test Constraint",
            type: .privacy,
            enabled: true,
            priority: 1,
            conditions: [
                EditableConditionRule(field: "content", operator: .contains, value: "test")
            ],
            action: .block(reason: "Test reason")
        )

        // When: Converting to PolicyRule
        let policyRule = editable.toPolicyRule()

        // Then: All properties match
        XCTAssertEqual(policyRule.id, editable.id)
        XCTAssertEqual(policyRule.name, editable.name)
        XCTAssertEqual(policyRule.type, editable.type)
        XCTAssertEqual(policyRule.enabled, editable.enabled)
        XCTAssertEqual(policyRule.priority, editable.priority)
        XCTAssertEqual(policyRule.conditions.count, 1)
        if case .block(let reason) = policyRule.action {
            XCTAssertEqual(reason, "Test reason")
        } else {
            XCTFail("Expected block action")
        }
    }

    func testPolicyRuleToEditablePolicyRuleConversion() throws {
        // Given: A policy rule
        let policyRule = PolicyRule(
            id: UUID(),
            name: "Test Constraint",
            type: .cost,
            enabled: false,
            priority: 5,
            conditions: [
                ConditionRule(field: "token_count", operator: .exceeds, value: "5000")
            ],
            action: .warn(message: "Large query")
        )

        // When: Converting to EditablePolicyRule
        let editable = EditablePolicyRule(from: policyRule)

        // Then: All properties match
        XCTAssertEqual(editable.id, policyRule.id)
        XCTAssertEqual(editable.name, policyRule.name)
        XCTAssertEqual(editable.type, policyRule.type)
        XCTAssertEqual(editable.enabled, policyRule.enabled)
        XCTAssertEqual(editable.priority, policyRule.priority)
        XCTAssertEqual(editable.conditions.count, 1)
        if case .warn(let message) = editable.action {
            XCTAssertEqual(message, "Large query")
        } else {
            XCTFail("Expected warn action")
        }
    }

    // MARK: - ConstraintStore Tests

    func testConstraintStoreLoadReturnsEmptyArrayWhenFileDoesNotExist() throws {
        // Given: ConstraintStore with non-existent file
        let store = ConstraintStore(fileURL: testFileURL)

        // When: Loading constraints
        let rules = try store.load()

        // Then: Returns empty array (no error)
        XCTAssertEqual(rules.count, 0)
    }

    func testConstraintStoreSaveAndLoad() throws {
        // Given: ConstraintStore and test rules
        let store = ConstraintStore(fileURL: testFileURL)
        let testRule = PolicyRule(
            name: "Test Rule",
            type: .privacy,
            enabled: true,
            priority: 1,
            conditions: [
                ConditionRule(field: "content", operator: .contains, value: "test")
            ],
            action: .forceLocal
        )

        // When: Saving and loading
        try store.save([testRule])
        let loadedRules = try store.load()

        // Then: Loaded rules match saved rules
        XCTAssertEqual(loadedRules.count, 1)
        XCTAssertEqual(loadedRules[0].name, testRule.name)
        XCTAssertEqual(loadedRules[0].type, testRule.type)
        XCTAssertEqual(loadedRules[0].priority, testRule.priority)
    }

    func testConstraintStoreGracefullyHandlesMalformedJSON() throws {
        // Given: Malformed JSON file
        let malformedJSON = "{broken json".data(using: .utf8)!
        try malformedJSON.write(to: testFileURL)

        let store = ConstraintStore(fileURL: testFileURL)

        // When: Loading constraints
        let rules = try store.load()

        // Then: Returns empty array (graceful degradation)
        XCTAssertEqual(rules.count, 0)
    }

    // MARK: - PolicyRulesStore Tests

    func testPolicyRulesStoreLoadsRulesOnInit() async throws {
        // Given: ConstraintStore with test data
        let testRule = PolicyRule(
            name: "Test Rule",
            type: .privacy,
            enabled: true,
            priority: 1,
            conditions: [
                ConditionRule(field: "content", operator: .contains, value: "test")
            ],
            action: .forceLocal
        )
        let constraintStore = ConstraintStore(fileURL: testFileURL)
        try constraintStore.save([testRule])

        // When: Creating PolicyRulesStore
        let policyStore = PolicyRulesStore(constraintStore: constraintStore)

        // Then: Rules are loaded and cached
        let rules = policyStore.getPolicyRules()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].name, testRule.name)
    }

    func testPolicyRulesStoreReturnsEmptyArrayWhenNoRulesExist() async throws {
        // Given: Empty constraint store
        let constraintStore = ConstraintStore(fileURL: testFileURL)

        // When: Creating PolicyRulesStore
        let policyStore = PolicyRulesStore(constraintStore: constraintStore)

        // Then: Returns empty array (no crash)
        let rules = policyStore.getPolicyRules()
        XCTAssertEqual(rules.count, 0)
    }

    func testPolicyRulesStoreReturnsValueCopiesNotReferences() async throws {
        // Given: PolicyRulesStore with cached rules
        let testRule = PolicyRule(
            name: "Test Rule",
            type: .privacy,
            enabled: true,
            priority: 1,
            conditions: [
                ConditionRule(field: "content", operator: .contains, value: "test")
            ],
            action: .forceLocal
        )
        let constraintStore = ConstraintStore(fileURL: testFileURL)
        try constraintStore.save([testRule])
        let policyStore = PolicyRulesStore(constraintStore: constraintStore)

        // When: Getting rules twice
        let rules1 = policyStore.getPolicyRules()
        let rules2 = policyStore.getPolicyRules()

        // Then: Both arrays have same values (PolicyRule is struct, so copies)
        XCTAssertEqual(rules1.count, rules2.count)
        XCTAssertEqual(rules1[0].id, rules2[0].id)
        // PolicyRule is value type, so this verifies immutability
    }
}
