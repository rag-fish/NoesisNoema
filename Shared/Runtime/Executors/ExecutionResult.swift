// NoesisNoema - Hybrid Routing Runtime
// ExecutionResult data structure
// Created: 2026-03-07
// Updated: 2026-03-08 - Removed route field (routing authority belongs to Router)
// Updated: 2026-05-22 - R2 (ADR-0008): added sources (retrieved chunks / citations)
// License: MIT License

import Foundation

/// Structured execution result
///
/// This structure captures the outcome of execution.
/// It is an immutable, deterministic container.
///
/// Constitutional Constraint (ADR-0000):
/// - This is a pure data structure with no behavior
/// - Executors produce this as output
/// - All fields are immutable
/// - Does NOT contain routing information (routing authority belongs to Router)
struct ExecutionResult: Equatable {
    /// The generated output text
    let output: String

    /// Retrieved knowledge chunks that grounded this result (citations).
    ///
    /// Populated by `LocalExecutor` from RAG retrieval so callers receive
    /// citations through the return value instead of reading `ModelManager`'s
    /// mutable state as a side effect (ADR-0008 R2). Empty for the remote/agent
    /// path — remote citations are a later task. Defaults to `[]` so existing
    /// call sites remain source-compatible.
    let sources: [Chunk]

    /// Unique trace identifier for observability
    let traceId: UUID

    /// Execution timestamp
    let timestamp: Date

    init(
        output: String,
        sources: [Chunk] = [],
        traceId: UUID,
        timestamp: Date
    ) {
        self.output = output
        self.sources = sources
        self.traceId = traceId
        self.timestamp = timestamp
    }
}
