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
/// Phase 4-B: PolicyRulesStore injected but not used yet
/// Future phases: Will integrate Router + PolicyEngine
@MainActor
final class ExecutionCoordinator: ExecutionCoordinating {

    // MARK: - Dependencies

    private let modelManager: ModelManager
    private let policyRulesProvider: PolicyRulesProvider?  // Phase 4-B: Injected but not used

    // MARK: - Initialization

    init(
        modelManager: ModelManager = ModelManager.shared,
        policyRulesProvider: PolicyRulesProvider? = nil  // Optional for Phase 4-B
    ) {
        self.modelManager = modelManager
        self.policyRulesProvider = policyRulesProvider
    }

    // MARK: - ExecutionCoordinating

    func execute(request: NoemaRequest) async throws -> NoemaResponse {
        // Phase 4-B: PolicyRulesProvider injected but not used yet
        // Integration deferred to Phase 5
        // let rules = policyRulesProvider?.getPolicyRules() ?? []
        // let policyResult = try PolicyEngine.evaluate(question, state, rules)
        // let routingDecision = try Router.route(question, state, policyResult)

        // Phase 4-A/4-B: Direct delegation to existing ModelManager
        // Preserves current behavior exactly

        let responseText = await modelManager.generateAsyncAnswer(question: request.query)

        return NoemaResponse(
            text: responseText,
            sessionId: request.sessionId
        )
    }
}
