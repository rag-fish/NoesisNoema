// NoesisNoema - Hybrid Routing Runtime
// AgentExecutor - Remote agent execution
// Created: 2026-03-07
// Updated: 2026-03-08 - Refactored to use AgentClient dependency injection
// License: MIT License

import Foundation

/// Agent Executor
///
/// Executes queries via remote noema-agent API using AgentClient.
///
/// Constitutional Constraints (ADR-0000):
/// - MUST NOT make routing decisions
/// - MUST NOT change execution path
/// - MUST NOT perform silent fallback
/// - MUST NOT contain routing logic
/// - MUST NOT mutate global state
/// - MUST NOT retry automatically (errors must propagate)
///
/// Architectural Refinement (2026-03-08):
/// - AgentExecutor delegates HTTP communication to AgentClient
/// - Routing authority removed from ExecutionResult
/// - Separation: Executor (orchestration) vs Client (I/O)
final class AgentExecutor: Executor {

    /// Agent client for HTTP communication
    private let client: AgentClient

    /// Initialize with agent client
    /// - Parameter client: The AgentClient implementation for network communication
    init(client: AgentClient) {
        self.client = client
    }

    /// Execute query via remote agent
    ///
    /// - Parameters:
    ///   - query: The user's query text
    ///   - sessionId: Session identifier
    /// - Returns: ExecutionResult with agent response
    /// - Throws: Network errors, HTTP errors, parsing errors
    func execute(
        query: String,
        sessionId: UUID
    ) async throws -> ExecutionResult {

        let traceId = UUID()

        // Delegate to AgentClient for HTTP communication
        let response = try await client.query(
            query: query,
            sessionId: sessionId
        )

        return ExecutionResult(
            output: response,
            traceId: traceId,
            timestamp: Date()
        )
    }
}
