// NoesisNoema - Hybrid Routing Runtime
// ExecutionResult data structure
// Created: 2026-03-07
// Updated: 2026-03-08 - Removed route field (routing authority belongs to Router)
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

    /// Unique trace identifier for observability
    let traceId: UUID

    /// Execution timestamp
    let timestamp: Date

    init(
        output: String,
        traceId: UUID,
        timestamp: Date
    ) {
        self.output = output
        self.traceId = traceId
        self.timestamp = timestamp
    }
}
