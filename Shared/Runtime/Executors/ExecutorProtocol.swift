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

    /// Execute a query with session memory (ADR-0009).
    ///
    /// History is prompt-construction input only — it MUST NOT influence
    /// routing, privacy, or retrieval (ADR-0009 Decision 4). Order is
    /// chronological (oldest → newest); the caller pre-applies the 3-turn
    /// AND 45-minute caps. Empty `history` ⇒ behaves identically to the
    /// stateless overload (ADR-0009 Decision 2).
    ///
    /// A default implementation is provided that drops `history` and calls
    /// the stateless overload — so existing executors (e.g. AgentExecutor)
    /// keep their current behaviour with no changes required. The local
    /// path overrides this to thread history into the prompt.
    func execute(
        query: String,
        sessionId: UUID,
        history: [ConversationTurn]
    ) async throws -> ExecutionResult
}

extension Executor {
    /// Default: ignore history and fall through to the stateless overload.
    /// This keeps `AgentExecutor` and test mocks source-compatible — session
    /// memory is a local-generation concern in this ADR (ADR-0009 §4 keeps
    /// memory out of routing/retrieval; the remote path is unchanged).
    func execute(
        query: String,
        sessionId: UUID,
        history: [ConversationTurn]
    ) async throws -> ExecutionResult {
        try await execute(query: query, sessionId: sessionId)
    }
}
