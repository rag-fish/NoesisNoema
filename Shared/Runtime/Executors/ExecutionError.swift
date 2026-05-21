// NoesisNoema - Hybrid Routing Runtime
// ExecutionError - Structured execution errors
// Created: 2026-05-21 (R1: monolith decomposition)
// License: MIT License

import Foundation

/// Structured execution errors for the execution layer.
///
/// Constitutional Constraint (ADR-0000):
/// - Executors MUST surface failures explicitly via thrown errors.
/// - Executors MUST NOT return placeholder / stub text on failure.
/// - Executors MUST NOT silently fall back to another route.
enum ExecutionError: Error, LocalizedError, Equatable {
    /// The local model could not be resolved or loaded.
    case modelUnavailable(String)

    /// Knowledge retrieval produced no usable context.
    case knowledgeEmpty

    /// The inference call failed.
    case inferenceFailed(String)

    /// Inference returned an empty result.
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let detail):
            return "Local model unavailable: \(detail)"
        case .knowledgeEmpty:
            return "No knowledge context available for this query. Import a RAGpack first."
        case .inferenceFailed(let detail):
            return "Local inference failed: \(detail)"
        case .emptyOutput:
            return "Local inference produced an empty result."
        }
    }
}
