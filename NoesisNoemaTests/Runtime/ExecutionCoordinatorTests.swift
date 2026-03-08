// NoesisNoema - HybridRuntime: Hybrid Routing Runtime
// ExecutionCoordinator Tests
// Created: 2026-03-08
// License: MIT License

import XCTest
@testable import NoesisNoema

/// Mock Executors for testing
class MockLocalExecutor: Executor {
    var executeCallCount = 0
    var lastQuery: String?
    var lastSessionId: UUID?
    var mockOutput: String = "[MOCK LOCAL]"
    var shouldThrow: Bool = false

    func execute(query: String, sessionId: UUID) async throws -> ExecutionResult {
        executeCallCount += 1
        lastQuery = query
        lastSessionId = sessionId

        if shouldThrow {
            throw NSError(domain: "MockLocalError", code: 1)
        }

        return ExecutionResult(
            output: "\(mockOutput) \(query)",
            traceId: UUID(),
            timestamp: Date()
        )
    }
}

class MockAgentExecutor: Executor {
    var executeCallCount = 0
    var lastQuery: String?
    var lastSessionId: UUID?
    var mockOutput: String = "[MOCK AGENT]"
    var shouldThrow: Bool = false

    func execute(query: String, sessionId: UUID) async throws -> ExecutionResult {
        executeCallCount += 1
        lastQuery = query
        lastSessionId = sessionId

        if shouldThrow {
            throw NSError(domain: "MockAgentError", code: 1)
        }

        return ExecutionResult(
            output: "\(mockOutput) \(query)",
            traceId: UUID(),
            timestamp: Date()
        )
    }
}

/// Tests for HybridExecutionCoordinator
///
/// These tests verify:
/// - Complete flow: policy → router → executor
/// - Correct executor selection based on route
/// - No fallback logic
/// - No retry logic
/// - Error propagation
final class HybridExecutionCoordinatorTests: XCTestCase {

    var mockLocalExecutor: MockLocalExecutor!
    var mockAgentExecutor: MockAgentExecutor!
    var coordinator: HybridExecutionCoordinator!

    override func setUp() {
        super.setUp()
        mockLocalExecutor = MockLocalExecutor()
        mockAgentExecutor = MockAgentExecutor()
        coordinator = HybridExecutionCoordinator(
            localExecutor: mockLocalExecutor,
            agentExecutor: mockAgentExecutor
        )
    }

    override func tearDown() {
        coordinator = nil
        mockAgentExecutor = nil
        mockLocalExecutor = nil
        super.tearDown()
    }

    // MARK: - Flow Integration Tests

    func testExecutionCoordinator_CompleteFlow() async throws {
        // Given: Simple query that routes to local
        let request = NoemaRequest(query: "Hello")

        // When: Executing
        let result = try await coordinator.execute(request: request)

        // Then: Should complete full flow
        XCTAssertNotNil(result.output)
        XCTAssertNotNil(result.traceId)
        XCTAssertNotNil(result.timestamp)
    }

    // MARK: - Local Route Tests

    func testExecutionCoordinator_LocalRoute_UsesLocalExecutor() async throws {
        // Given: Request that routes to local (short query, no keywords)
        let request = NoemaRequest(query: "Hi")

        // When: Executing
        let result = try await coordinator.execute(request: request)

        // Then: Should use local executor
        XCTAssertEqual(mockLocalExecutor.executeCallCount, 1, "Should call LocalExecutor")
        XCTAssertEqual(mockAgentExecutor.executeCallCount, 0, "Should not call AgentExecutor")
        XCTAssertEqual(mockLocalExecutor.lastQuery, "Hi")
        XCTAssertTrue(result.output.contains("[MOCK LOCAL]"))
    }

    func testExecutionCoordinator_PrivacyQuery_RoutesToLocal() async throws {
        // Given: Privacy-sensitive query
        let request = NoemaRequest(query: "What is my phone number?")

        // When: Executing
        let result = try await coordinator.execute(request: request)

        // Then: Should route to local (privacy stays on device)
        XCTAssertEqual(mockLocalExecutor.executeCallCount, 1, "Privacy query should use LocalExecutor")
        XCTAssertEqual(mockAgentExecutor.executeCallCount, 0, "Privacy query should not use AgentExecutor")
        XCTAssertTrue(result.output.contains("[MOCK LOCAL]"))
    }

    // MARK: - Cloud Route Tests

    func testExecutionCoordinator_CloudRoute_UsesAgentExecutor() async throws {
        // Given: Request that routes to cloud (tool keyword)
        let request = NoemaRequest(query: "Send an email to John")

        // When: Executing
        let result = try await coordinator.execute(request: request)

        // Then: Should use agent executor
        XCTAssertEqual(mockLocalExecutor.executeCallCount, 0, "Should not call LocalExecutor")
        XCTAssertEqual(mockAgentExecutor.executeCallCount, 1, "Should call AgentExecutor")
        XCTAssertEqual(mockAgentExecutor.lastQuery, "Send an email to John")
        XCTAssertTrue(result.output.contains("[MOCK AGENT]"))
    }

    func testExecutionCoordinator_ToolQuery_RoutesToCloud() async throws {
        // Given: Tool-requiring query
        let request = NoemaRequest(query: "Check my calendar")

        // When: Executing
        let result = try await coordinator.execute(request: request)

        // Then: Should route to cloud (tool capabilities needed)
        XCTAssertEqual(mockLocalExecutor.executeCallCount, 0, "Tool query should not use LocalExecutor")
        XCTAssertEqual(mockAgentExecutor.executeCallCount, 1, "Tool query should use AgentExecutor")
        XCTAssertTrue(result.output.contains("[MOCK AGENT]"))
    }

    func testExecutionCoordinator_ComplexQuery_RoutesToCloud() async throws {
        // Given: Long complex query (default to cloud)
        let longQuery = "Tell me about the history of artificial intelligence and its development over the past several decades"
        let request = NoemaRequest(query: longQuery)

        // When: Executing
        let result = try await coordinator.execute(request: request)

        // Then: Should route to cloud (default for complex queries)
        XCTAssertEqual(mockLocalExecutor.executeCallCount, 0, "Complex query should not use LocalExecutor")
        XCTAssertEqual(mockAgentExecutor.executeCallCount, 1, "Complex query should use AgentExecutor")
        XCTAssertTrue(result.output.contains("[MOCK AGENT]"))
    }

    // MARK: - Session ID Propagation Tests

    func testExecutionCoordinator_PropagatesSessionId() async throws {
        // Given: Request with specific session ID
        let sessionId = UUID()
        let request = NoemaRequest(query: "Test", sessionId: sessionId)

        // When: Executing
        _ = try await coordinator.execute(request: request)

        // Then: Should propagate session ID to executor
        XCTAssertEqual(mockLocalExecutor.lastSessionId, sessionId)
    }

    // MARK: - Error Propagation Tests

    func testExecutionCoordinator_PropagatesLocalExecutorErrors() async throws {
        // Given: LocalExecutor configured to throw error
        mockLocalExecutor.shouldThrow = true
        let request = NoemaRequest(query: "Hi")

        // When/Then: Should propagate error
        do {
            _ = try await coordinator.execute(request: request)
            XCTFail("Should have thrown error")
        } catch {
            // Expected error propagation
            XCTAssertNotNil(error)
        }
    }

    func testExecutionCoordinator_PropagatesAgentExecutorErrors() async throws {
        // Given: AgentExecutor configured to throw error
        mockAgentExecutor.shouldThrow = true
        let request = NoemaRequest(query: "Send an email")

        // When/Then: Should propagate error
        do {
            _ = try await coordinator.execute(request: request)
            XCTFail("Should have thrown error")
        } catch {
            // Expected error propagation
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Constitutional Constraint Tests

    func testExecutionCoordinator_ContainsNoFallbackLogic() async throws {
        // Given: LocalExecutor configured to fail
        mockLocalExecutor.shouldThrow = true
        let request = NoemaRequest(query: "Hi")

        // When: Executing fails
        do {
            _ = try await coordinator.execute(request: request)
            XCTFail("Should have thrown error")
        } catch {
            // Expected failure
        }

        // Then: Should not fallback to agent executor
        XCTAssertEqual(mockLocalExecutor.executeCallCount, 1, "Should attempt local once")
        XCTAssertEqual(mockAgentExecutor.executeCallCount, 0, "Should not fallback to agent")
    }

    func testExecutionCoordinator_ContainsNoRetryLogic() async throws {
        // Given: AgentExecutor configured to fail
        mockAgentExecutor.shouldThrow = true
        let request = NoemaRequest(query: "Send an email")

        // When: Executing fails
        do {
            _ = try await coordinator.execute(request: request)
            XCTFail("Should have thrown error")
        } catch {
            // Expected failure
        }

        // Then: Should not retry
        XCTAssertEqual(mockAgentExecutor.executeCallCount, 1, "Should attempt once only (no retry)")
    }

    // MARK: - Routing Decision Tests

    func testExecutionCoordinator_RoutingDecisionMatrix() async throws {
        // Test routing for various query types
        let testCases: [(query: String, expectedExecutor: String)] = [
            ("Hi", "local"),                              // Short query
            ("What is my phone?", "local"),               // Privacy
            ("Send email", "cloud"),                       // Tool
            (String(repeating: "a", count: 150), "cloud") // Complex
        ]

        for (query, expectedExecutor) in testCases {
            // Reset counters
            mockLocalExecutor.executeCallCount = 0
            mockAgentExecutor.executeCallCount = 0

            // Execute
            let request = NoemaRequest(query: query)
            _ = try await coordinator.execute(request: request)

            // Verify correct executor was used
            if expectedExecutor == "local" {
                XCTAssertEqual(mockLocalExecutor.executeCallCount, 1, "Query '\(query)' should use local")
                XCTAssertEqual(mockAgentExecutor.executeCallCount, 0, "Query '\(query)' should not use agent")
            } else {
                XCTAssertEqual(mockLocalExecutor.executeCallCount, 0, "Query '\(query)' should not use local")
                XCTAssertEqual(mockAgentExecutor.executeCallCount, 1, "Query '\(query)' should use agent")
            }
        }
    }

    // MARK: - Integration Tests

    func testExecutionCoordinator_ReturnsStructuredResult() async throws {
        // Given: Simple request
        let request = NoemaRequest(query: "Test")

        // When: Executing
        let result = try await coordinator.execute(request: request)

        // Then: Should return structured ExecutionResult
        XCTAssertFalse(result.output.isEmpty, "Output should not be empty")
        XCTAssertNotNil(result.traceId, "TraceId should be set")
        XCTAssertNotNil(result.timestamp, "Timestamp should be set")
    }

    func testExecutionCoordinator_PassesQueryToExecutor() async throws {
        // Given: Request with specific query
        let query = "What is the capital of France?"
        let request = NoemaRequest(query: query)

        // When: Executing
        _ = try await coordinator.execute(request: request)

        // Then: Should pass query to executor
        XCTAssertEqual(mockLocalExecutor.lastQuery, query)
    }

    func testExecutionCoordinator_GeneratesUniqueTraceIds() async throws {
        // Given: Two requests
        let request1 = NoemaRequest(query: "Test 1")
        let request2 = NoemaRequest(query: "Test 2")

        // When: Executing twice
        let result1 = try await coordinator.execute(request: request1)
        let result2 = try await coordinator.execute(request: request2)

        // Then: TraceIds should be unique
        XCTAssertNotEqual(result1.traceId, result2.traceId, "Each execution should have unique traceId")
    }

    // MARK: - Executor Selection Tests

    func testExecutionCoordinator_SelectsCorrectExecutorForEachQuery() async throws {
        // Privacy query → local
        let privacyRequest = NoemaRequest(query: "My address")
        _ = try await coordinator.execute(request: privacyRequest)
        XCTAssertEqual(mockLocalExecutor.executeCallCount, 1)
        XCTAssertEqual(mockAgentExecutor.executeCallCount, 0)

        // Reset
        mockLocalExecutor.executeCallCount = 0
        mockAgentExecutor.executeCallCount = 0

        // Tool query → cloud
        let toolRequest = NoemaRequest(query: "Send email")
        _ = try await coordinator.execute(request: toolRequest)
        XCTAssertEqual(mockLocalExecutor.executeCallCount, 0)
        XCTAssertEqual(mockAgentExecutor.executeCallCount, 1)
    }
}
