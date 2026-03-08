// NoesisNoema - Hybrid Routing Runtime
// LocalExecutor - Local LLM execution
// Created: 2026-03-07
// License: MIT License

import Foundation

/// Local Executor
///
/// Executes queries using local llama.cpp runtime.
///
/// Constitutional Constraints (ADR-0000):
/// - MUST NOT make routing decisions
/// - MUST NOT change execution path
/// - MUST NOT perform silent fallback
/// - MUST NOT contain routing logic
/// - MUST NOT mutate global state
/// - MUST NOT retry automatically
///
/// Note: This is a stub implementation.
/// Full llama.cpp integration to be implemented.
final class LocalExecutor: Executor {

    /// Execute query using local LLM
    ///
    /// Returns stub response for now.
    /// Will integrate llama.cpp runtime.
    ///
    /// - Parameters:
    ///   - query: The user's query text
    ///   - sessionId: Session identifier
    /// - Returns: ExecutionResult with generated output
    /// - Throws: Execution errors (model failure, etc.)
    func execute(
        query: String,
        sessionId: UUID
    ) async throws -> ExecutionResult {

        let traceId = UUID()

        // Stub response
        // TODO: Integrate llama.cpp runtime
        let output = "[LOCAL LLM STUB] \(query)"

        return ExecutionResult(
            output: output,
            traceId: traceId,
            timestamp: Date()
        )
    }
}
