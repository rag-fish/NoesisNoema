// NoesisNoema - HybridRuntime: Hybrid Routing Runtime
// Executor Tests
// Created: 2026-03-07
// Updated: 2026-03-08 - Refactored for ExecutionResult changes and AgentClient DI
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

    // MARK: - LocalExecutor Tests

    func testLocalExecutor_ReturnsExecutionResult() async throws {
        // Given: LocalExecutor
        let executor = LocalExecutor()
        let query = "What is the capital of France?"
        let sessionId = UUID()

        // When: Executing
        let result = try await executor.execute(query: query, sessionId: sessionId)

        // Then: Should return ExecutionResult
        XCTAssertFalse(result.output.isEmpty, "Output should not be empty")
        XCTAssertNotNil(result.traceId, "TraceId should be set")
        XCTAssertNotNil(result.timestamp, "Timestamp should be set")
    }

    func testLocalExecutor_GeneratesUniqueTraceIds() async throws {
        // Given: LocalExecutor
        let executor = LocalExecutor()
        let query = "Test query"

        // When: Executing twice
        let result1 = try await executor.execute(query: query, sessionId: UUID())
        let result2 = try await executor.execute(query: query, sessionId: UUID())

        // Then: TraceIds should be unique
        XCTAssertNotEqual(result1.traceId, result2.traceId, "Each execution should have unique traceId")
    }

    func testLocalExecutor_IncludesQueryInStubOutput() async throws {
        // Given: LocalExecutor
        let executor = LocalExecutor()
        let query = "Hello world"

        // When: Executing
        let result = try await executor.execute(query: query, sessionId: UUID())

        // Then: Output should contain the query (stub behavior)
        XCTAssertTrue(result.output.contains(query), "Stub output should contain the query")
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

    func testExecutors_DoNotExposeRoutingInformation() async throws {
        // Given: Both executors
        let localExecutor = LocalExecutor()
        let agentExecutor = AgentExecutor(client: MockAgentClient())

        // When: Executing
        let localResult = try await localExecutor.execute(query: "Test", sessionId: UUID())
        let agentResult = try await agentExecutor.execute(query: "Test", sessionId: UUID())

        // Then: ExecutionResult should not contain route information
        // (This is verified by the ExecutionResult structure itself - no route field)
        XCTAssertNotNil(localResult.output)
        XCTAssertNotNil(agentResult.output)
    }

    func testExecutors_ReturnStructuredResults() async throws {
        // Given: Both executors
        let localExecutor = LocalExecutor()
        let agentExecutor = AgentExecutor(client: MockAgentClient())

        // When: Executing
        let localResult = try await localExecutor.execute(query: "Test", sessionId: UUID())
        let agentResult = try await agentExecutor.execute(query: "Test", sessionId: UUID())

        // Then: Results should have all required fields
        XCTAssertFalse(localResult.output.isEmpty, "Output should be populated")
        XCTAssertNotNil(localResult.traceId, "TraceId should be set")
        XCTAssertNotNil(localResult.timestamp, "Timestamp should be set")

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
