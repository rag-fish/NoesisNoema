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
/// Phase2 Note: This is a stub implementation.
/// Phase3 will integrate actual llama.cpp runtime.
final class LocalExecutor: Executor {

    /// Execute query using local LLM
    ///
    /// Phase2: Returns stub response
    /// Phase3: Will integrate llama.cpp
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

        // Phase2 stub response
        // Phase3 TODO: Integrate llama.cpp runtime
        let output = "[LOCAL LLM STUB] \(query)"

        return ExecutionResult(
            output: output,
            traceId: traceId,
            timestamp: Date()
        )
    }
}
