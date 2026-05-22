// NoesisNoema - Hybrid Routing Runtime
// ExecutionError - Structured execution errors
// Created: 2026-05-21 (R1: monolith decomposition)
// Updated: 2026-05-22 (R3: privacyViolation — Privacy Step 4.5 enforcement)
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

    /// A privacy-local request was about to be routed off-device.
    ///
    /// Raised by the coordinator's mandatory privacy-enforcement step
    /// (ADR-0008 Decision 4 / execution-flow.md Step 4.5): a request whose
    /// Question carries `privacyLevel == .local` MUST execute on-device with
    /// no cloud fallback. If the routing decision would send it to the
    /// network/agent executor, execution is refused here — never silently
    /// degraded, never routed off-device.
    case privacyViolation(String)

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
        case .privacyViolation(let detail):
            return "Privacy enforcement blocked execution: \(detail)"
        }
    }
}
