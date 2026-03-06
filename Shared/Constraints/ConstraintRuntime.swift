//
//  ConstraintRuntime.swift
//  NoesisNoema
//
//  Created for EPIC2 Phase 1
//  Purpose: Runtime layer for validating execution constraints
//  License: MIT License
//

import Foundation
import OSLog

/// Runtime execution result for logging
enum ConstraintResult: Equatable {
    case passed
    case violated(ConstraintViolation)

    static func == (lhs: ConstraintResult, rhs: ConstraintResult) -> Bool {
        switch (lhs, rhs) {
        case (.passed, .passed):
            return true
        case (.violated(let lv), .violated(let rv)):
            return lv.reason == rv.reason
        default:
            return false
        }
    }

    var description: String {
        switch self {
        case .passed:
            return "passed"
        case .violated(let violation):
            return "violated: \(violation.reason)"
        }
    }
}

/// Execution log entry for in-memory tracking
struct ExecutionLogEntry {
    let request: NoemaRequest
    let constraintResult: ConstraintResult
    let executionResult: Result<NoemaResponse, Error>
    let timestamp: Date

    var description: String {
        let executionStatus = switch executionResult {
        case .success: "success"
        case .failure(let error): "failure: \(error.localizedDescription)"
        }
        return "[\(timestamp)] sessionId=\(request.sessionId) constraint=\(constraintResult.description) execution=\(executionStatus)"
    }
}

/// Constraint runtime layer for validating execution requests
final class ConstraintRuntime {

    // MARK: - Properties

    private let constraints: [ExecutionConstraint]
    private let logger = Logger(subsystem: "NoesisNoema", category: "ConstraintRuntime")

    // In-memory execution log (non-persistent)
    private var executionLog: [ExecutionLogEntry] = []
    private let logLock = NSLock()

    // MARK: - Initialization

    init(constraints: [ExecutionConstraint] = []) {
        self.constraints = constraints
    }

    // MARK: - Public API

    /// Validate a request against configured constraints
    /// - Parameter request: The NoemaRequest to validate
    /// - Throws: ConstraintViolation if any constraint fails
    func validate(request: NoemaRequest) throws {
        logger.info("🔍 Validating request: sessionId=\(request.sessionId.uuidString)")

        for constraint in constraints {
            try validateConstraint(constraint, against: request)
        }

        logger.info("✅ Validation passed for sessionId=\(request.sessionId.uuidString)")
    }

    /// Log an execution entry (in-memory only)
    /// - Parameters:
    ///   - request: The original request
    ///   - constraintResult: Result of constraint validation
    ///   - executionResult: Result of execution
    func logExecution(
        request: NoemaRequest,
        constraintResult: ConstraintResult,
        executionResult: Result<NoemaResponse, Error>
    ) {
        let entry = ExecutionLogEntry(
            request: request,
            constraintResult: constraintResult,
            executionResult: executionResult,
            timestamp: Date()
        )

        logLock.lock()
        executionLog.append(entry)
        logLock.unlock()

        logger.debug("📝 Logged execution: \(entry.description)")
    }

    /// Get execution log entries (for debugging/monitoring)
    func getExecutionLog() -> [ExecutionLogEntry] {
        logLock.lock()
        defer { logLock.unlock() }
        return executionLog
    }

    /// Clear execution log
    func clearLog() {
        logLock.lock()
        executionLog.removeAll()
        logLock.unlock()
        logger.debug("🗑️ Execution log cleared")
    }

    // MARK: - Private Helpers

    private func validateConstraint(_ constraint: ExecutionConstraint, against request: NoemaRequest) throws {
        switch constraint {
        case .requiresUserIntent:
            // Check if the request query is empty or trivial
            let trimmedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedQuery.isEmpty {
                throw ConstraintViolation(
                    constraint: constraint,
                    reason: "Request query is empty - user intent required"
                )
            }

        case .maxTokens(let maxTokens):
            // NOTE:
            // Token estimation is approximate (1 token ≈ 4 characters).
            // This will be replaced with tokenizer-based counting in later phases.
            let estimatedTokens = request.query.count / 4
            if estimatedTokens > maxTokens {
                throw ConstraintViolation(
                    constraint: constraint,
                    reason: "Request exceeds max tokens: \(estimatedTokens) > \(maxTokens)"
                )
            }

        case .noToolUse:
            // Check for tool-related keywords in query
            let toolKeywords = ["tool", "function", "execute", "run command"]
            let lowercasedQuery = request.query.lowercased()

            for keyword in toolKeywords {
                if lowercasedQuery.contains(keyword) {
                    throw ConstraintViolation(
                        constraint: constraint,
                        reason: "Request may involve tool use (keyword: '\(keyword)') - not allowed by constraint"
                    )
                }
            }
        }
    }
}
