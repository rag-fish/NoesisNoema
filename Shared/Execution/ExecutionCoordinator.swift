//
//  ExecutionCoordinator.swift
//  NoesisNoema
//
//  Created for EPIC1 Phase 4-A
//  Purpose: Centralize execution entrypoint with dependency injection
//  License: MIT License
//

import Foundation

// MARK: - Request/Response Models

/// Request object for execution
struct NoemaRequest {
    let query: String
    let sessionId: UUID

    init(query: String, sessionId: UUID = UUID()) {
        self.query = query
        self.sessionId = sessionId
    }
}

/// Response object from execution
struct NoemaResponse {
    let text: String
    let sessionId: UUID

    init(text: String, sessionId: UUID) {
        self.text = text
        self.sessionId = sessionId
    }
}

// MARK: - Protocol

/// Protocol for execution coordination
/// Enables dependency injection and testability
protocol ExecutionCoordinating {
    /// Execute a request and return a response
    /// - Parameter request: The execution request
    /// - Returns: The execution response
    func execute(request: NoemaRequest) async throws -> NoemaResponse
}

// MARK: - Implementation

/// Centralized execution coordinator
/// Phase 4-A: Delegates to ModelManager (existing behavior)
/// Future phases: Will integrate Router + PolicyEngine
@MainActor
final class ExecutionCoordinator: ExecutionCoordinating {

    // MARK: - Dependencies

    private let modelManager: ModelManager

    // MARK: - Initialization

    init(modelManager: ModelManager = ModelManager.shared) {
        self.modelManager = modelManager
    }

    // MARK: - ExecutionCoordinating

    func execute(request: NoemaRequest) async throws -> NoemaResponse {
        // Phase 4-A: Direct delegation to existing ModelManager
        // No Router, no PolicyEngine integration yet
        // This preserves current behavior exactly

        let responseText = await modelManager.generateAsyncAnswer(question: request.query)

        return NoemaResponse(
            text: responseText,
            sessionId: request.sessionId
        )
    }
}
