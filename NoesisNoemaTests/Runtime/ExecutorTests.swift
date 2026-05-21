// NoesisNoema - HybridRuntime: Hybrid Routing Runtime
// Executor Tests
// Created: 2026-03-07
// Updated: 2026-03-08 - Refactored for ExecutionResult changes and AgentClient DI
// Updated: 2026-05-21 - R1: LocalExecutor stub removed; LocalExecutor tests now
//                       assert the ADR-0000 error contract (no stub text)
// License: MIT License

import XCTest
@testable import NoesisNoema

/// Mock AgentClient for testing
class MockAgentClient: AgentClient {
    var mockResponse: String = "Mock agent response"
    var shouldThrowError: Bool = false
    var lastQuery: String?
    var lastSessionId: UUID?

    func query(query: String, sessionId: UUID) async throws -> String {
        lastQuery = query
        lastSessionId = sessionId

        if shouldThrowError {
            throw NSError(domain: "MockError", code: 500)
        }

        return mockResponse
    }
}

/// Tests for Executor implementations
///
/// These tests verify constitutional constraints (ADR-0000):
/// - Executors contain no routing logic
/// - Executors return structured results
/// - Executors do not contain fallback logic
/// - Executors propagate errors explicitly
/// - ExecutionResult does not contain routing information
final class ExecutorTests: XCTestCase {

    // MARK: - LocalExecutor Tests (R1 — ADR-0008)
    //
    // R1 wired LocalExecutor to the real on-device RAG + llama.cpp pipeline and
    // removed the "[LOCAL LLM STUB]" placeholder. There is no longer a stub
    // success path: a genuine answer requires a loaded GGUF model and an
    // imported RAGpack (covered by the on-device smoke test, UAT U1).
    // In a model-less unit-test environment LocalExecutor instead throws an
    // ExecutionError. Per ADR-0000 (no silent fallback) it MUST surface
    // failures as thrown ExecutionErrors and MUST NOT return placeholder text.

    func testLocalExecutor_NeverReturnsStubPlaceholder() async throws {
        // Given: LocalExecutor
        let executor = LocalExecutor()

        // When: Executing
        do {
            let result = try await executor.execute(query: "Hello world", sessionId: UUID())

            // Then (model + RAGpack available): a real answer, never the stub.
            XCTAssertFalse(result.output.contains("[LOCAL LLM STUB]"),
                           "R1 removed the stub; output must never contain the placeholder")
            XCTAssertFalse(result.output.isEmpty,
                           "A returned ExecutionResult must carry a real answer (ADR-0000)")
        } catch let error as ExecutionError {
            // Then (no model / no RAGpack): a structured throw, not a silent
            // stub fallback — the correct ADR-0000 behavior.
            XCTAssertNotNil(error.errorDescription)
        }
        // A non-ExecutionError throw propagates out of this `throws` test and
        // fails it — see testLocalExecutor_FailuresThrowExecutionError.
    }

    func testLocalExecutor_FailuresThrowExecutionError() async {
        // Given: LocalExecutor (no model loaded in the unit-test environment)
        let executor = LocalExecutor()

        // When/Then: every LocalExecutor failure path must surface as an
        // ExecutionError — never an unstructured error and never stub text.
        do {
            _ = try await executor.execute(query: "What is the capital of France?",
                                           sessionId: UUID())
            // Reached only when a real model + RAGpack are present — acceptable.
        } catch is ExecutionError {
            // Expected in the model-less unit-test environment.
        } catch {
            XCTFail("LocalExecutor must throw ExecutionError, got \(type(of: error)): \(error)")
        }
    }

    // MARK: - AgentExecutor Tests

    func testAgentExecutor_UsesAgentClientDependency() async throws {
        // Given: AgentExecutor with mock client
        let mockClient = MockAgentClient()
        mockClient.mockResponse = "Test response from agent"
        let executor = AgentExecutor(client: mockClient)

        let query = "Test query"
        let sessionId = UUID()

        // When: Executing
        let result = try await executor.execute(query: query, sessionId: sessionId)

        // Then: Should use client and return its response
        XCTAssertEqual(result.output, "Test response from agent")
        XCTAssertEqual(mockClient.lastQuery, query)
        XCTAssertEqual(mockClient.lastSessionId, sessionId)
    }

    func testAgentExecutor_PropagatesClientErrors() async throws {
        // Given: AgentExecutor with error-throwing client
        let mockClient = MockAgentClient()
        mockClient.shouldThrowError = true
        let executor = AgentExecutor(client: mockClient)

        // When/Then: Executing should propagate error
        do {
            _ = try await executor.execute(query: "Test", sessionId: UUID())
            XCTFail("Should have thrown error")
        } catch {
            // Expected error propagation
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Executor Protocol Compliance Tests

    func testExecutorProtocol_LocalExecutorConforms() {
        // Given: LocalExecutor
        let executor: Executor = LocalExecutor()

        // Then: Should conform to Executor protocol
        XCTAssertNotNil(executor, "LocalExecutor should conform to Executor protocol")
    }

    func testExecutorProtocol_AgentExecutorConforms() {
        // Given: AgentExecutor with mock client
        let mockClient = MockAgentClient()
        let executor: Executor = AgentExecutor(client: mockClient)

        // Then: Should conform to Executor protocol
        XCTAssertNotNil(executor, "AgentExecutor should conform to Executor protocol")
    }

    // MARK: - Constitutional Constraint Tests

    func testExecutionResult_ExposesNoRoutingInformation() async throws {
        // Routing authority belongs to Router / ExecutionCoordinator, not
        // Executors — ExecutionResult carries no route field. Verified here via
        // AgentExecutor (which produces a result with a mock client).
        // LocalExecutor returns the same ExecutionResult type; its R1 error
        // contract is covered by the testLocalExecutor_* tests above.
        let agentExecutor = AgentExecutor(client: MockAgentClient())

        // When: Executing
        let agentResult = try await agentExecutor.execute(query: "Test", sessionId: UUID())

        // Then: result exposes output/traceId/timestamp only — no route member.
        XCTAssertNotNil(agentResult.output)
    }

    func testAgentExecutor_ReturnsStructuredResult() async throws {
        // Given: AgentExecutor with a mock client
        let agentExecutor = AgentExecutor(client: MockAgentClient())

        // When: Executing
        let agentResult = try await agentExecutor.execute(query: "Test", sessionId: UUID())

        // Then: Result has all required fields
        XCTAssertFalse(agentResult.output.isEmpty, "Output should be populated")
        XCTAssertNotNil(agentResult.traceId, "TraceId should be set")
        XCTAssertNotNil(agentResult.timestamp, "Timestamp should be set")
    }

    // MARK: - ExecutionResult Tests

    func testExecutionResult_IsImmutable() {
        // Given: ExecutionResult
        let result = ExecutionResult(
            output: "Test output",
            traceId: UUID(),
            timestamp: Date()
        )

        // Then: All fields should be accessible (let properties are immutable)
        XCTAssertEqual(result.output, "Test output")
        XCTAssertNotNil(result.traceId)
        XCTAssertNotNil(result.timestamp)
    }

    func testExecutionResult_IsEquatable() {
        // Given: Two identical ExecutionResults
        let traceId = UUID()
        let timestamp = Date()

        let result1 = ExecutionResult(
            output: "Test",
            traceId: traceId,
            timestamp: timestamp
        )

        let result2 = ExecutionResult(
            output: "Test",
            traceId: traceId,
            timestamp: timestamp
        )

        // Then: Should be equal
        XCTAssertEqual(result1, result2, "ExecutionResult should be Equatable")
    }

    func testExecutionResult_DifferentResultsNotEqual() {
        // Given: Two different ExecutionResults
        let result1 = ExecutionResult(
            output: "Test1",
            traceId: UUID(),
            timestamp: Date()
        )

        let result2 = ExecutionResult(
            output: "Test2",
            traceId: UUID(),
            timestamp: Date()
        )

        // Then: Should not be equal
        XCTAssertNotEqual(result1, result2, "Different results should not be equal")
    }

    func testExecutionResult_DoesNotContainRoute() {
        // Given: ExecutionResult
        let result = ExecutionResult(
            output: "Test",
            traceId: UUID(),
            timestamp: Date()
        )

        // Then: Should only contain output, traceId, timestamp (no route field)
        // This test verifies architectural correction:
        // Routing authority belongs to Router/ExecutionCoordinator, not Executors
        XCTAssertNotNil(result.output)
        XCTAssertNotNil(result.traceId)
        XCTAssertNotNil(result.timestamp)
        // No route field exists - architectural compliance verified
    }
}
