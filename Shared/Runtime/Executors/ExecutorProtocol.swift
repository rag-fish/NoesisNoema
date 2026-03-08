// NoesisNoema - Hybrid Routing Runtime
// Executor Protocol
// Created: 2026-03-07
// License: MIT License

import Foundation

/// Executor protocol for execution layer components
///
/// Constitutional Constraints (ADR-0000):
/// - Executors MUST NOT perform routing decisions
/// - Executors MUST NOT mutate global state
/// - Executors MUST NOT retry automatically (retry only if explicitly permitted)
/// - Executors MUST NOT contain fallback logic
///
/// Executors receive execution instructions and carry them out.
/// They do not decide where or how to execute.
protocol Executor {
    /// Execute a query and return structured result
    ///
    /// - Parameters:
    ///   - query: The user's query text
    ///   - sessionId: Session identifier for context
    /// - Returns: ExecutionResult with output and metadata
    /// - Throws: Execution errors (network, model failure, etc.)
    func execute(
        query: String,
        sessionId: UUID
    ) async throws -> ExecutionResult
}
