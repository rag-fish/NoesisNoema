//
//  ExecutionCoordinator.swift
//  NoesisNoema
//
//  Created for EPIC1 Phase 4-A
//  Purpose: Centralize execution entrypoint with dependency injection
//  License: MIT License
//

import Foundation
import OSLog

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
/// Phase 5-B: Full policy-based routing wired
/// EPIC2: Integrated with ConstraintRuntime layer
/// Integrates PolicyEngine + Router without modifying their internals
@MainActor
final class ExecutionCoordinator: ExecutionCoordinating {

    // MARK: - Dependencies

    private let modelManager: ModelManager
    private let policyRulesProvider: PolicyRulesProvider?
    private let constraintRuntime: ConstraintRuntime

    // MARK: - Structured Logging

    private let logger = Logger(subsystem: "NoesisNoema", category: "Execution")

    // MARK: - Initialization

    init(
        modelManager: ModelManager = ModelManager.shared,
        policyRulesProvider: PolicyRulesProvider? = nil,
        constraintRuntime: ConstraintRuntime = ConstraintRuntime(
            constraints: [
                .requiresUserIntent,
                .maxTokens(4096),
                .noToolUse
            ]
        )
    ) {
        self.modelManager = modelManager
        self.policyRulesProvider = policyRulesProvider
        self.constraintRuntime = constraintRuntime
    }

    // MARK: - ExecutionCoordinating

    func execute(request: NoemaRequest) async throws -> NoemaResponse {
        // EPIC2: Execution flow with ConstraintRuntime validation
        // ExecutionCoordinator → ConstraintRuntime.validate → Agent execution

        log("📥 Question received: sessionId=\(request.sessionId)")

        // STEP 0: Constraint validation (EPIC2)
        let constraintResult: ConstraintResult
        do {
            try constraintRuntime.validate(request: request)
            constraintResult = .passed
            log("✅ ConstraintRuntime: validation passed")
        } catch let violation as ConstraintViolation {
            constraintResult = .violated(violation)
            log("❌ ConstraintRuntime: validation failed - \(violation.reason)")

            // Log the failed validation
            let errorResult: Result<NoemaResponse, Error> = .failure(violation)
            constraintRuntime.logExecution(
                request: request,
                constraintResult: constraintResult,
                executionResult: errorResult
            )

            // Return constraint violation error response
            return NoemaResponse(
                text: "❌ Constraint violation: \(violation.reason)",
                sessionId: request.sessionId
            )
        }

        // STEP 1: Build NoemaQuestion from request
        let question = buildNoemaQuestion(from: request)
        log("📝 NoemaQuestion constructed: id=\(question.id), privacy=\(question.privacyLevel)")

        // STEP 2: Build RuntimeState
        let runtimeState = buildRuntimeState()
        log("🔧 RuntimeState: network=\(runtimeState.networkState), localModel=\(runtimeState.localModelCapability.modelName)")

        // STEP 3: Get policy rules
        let rules = policyRulesProvider?.getPolicyRules() ?? []
        log("📋 Loaded \(rules.count) policy rule(s)")

        // STEP 4: Policy evaluation
        let policyResult: PolicyEvaluationResult
        do {
            policyResult = try PolicyEngine.evaluate(
                question: question,
                runtimeState: runtimeState,
                rules: rules
            )
            log("✅ PolicyEngine: action=\(policyResult.effectiveAction), rules=\(policyResult.appliedConstraints.map { $0.uuidString })")
        } catch RoutingError.policyViolation(let reason) {
            log("❌ Policy BLOCKED execution: \(reason)")
            return NoemaResponse(
                text: "❌ Request blocked by policy: \(reason)",
                sessionId: request.sessionId
            )
        } catch {
            log("❌ PolicyEngine error: \(error)")
            throw error
        }

        // STEP 5: Routing decision
        let routingDecision: RoutingDecision
        do {
            routingDecision = try Router.route(
                question: question,
                runtimeState: runtimeState,
                policyResult: policyResult
            )
            log("🚀 Router decision: route=\(routingDecision.routeTarget), model=\(routingDecision.model), reason=\(routingDecision.reason)")
        } catch RoutingError.networkUnavailable {
            log("❌ Routing failed: Network unavailable")
            return NoemaResponse(
                text: "❌ Cannot execute cloud route: Network unavailable",
                sessionId: request.sessionId
            )
        } catch RoutingError.invalidConfiguration(let reason) where reason.contains("local") {
            log("❌ Routing failed: Local model unavailable")
            return NoemaResponse(
                text: "❌ Cannot execute local route: Local model unavailable",
                sessionId: request.sessionId
            )
        } catch {
            log("❌ Routing error: \(error)")
            throw error
        }

        // STEP 6: Handle confirmation requirement
        if routingDecision.requiresConfirmation {
            // TODO: Phase 5-C - Implement confirmation UI
            // Current behavior: Auto-approve (explicit bypass for Phase 5-B)
            logger.warning("⚠️ Confirmation required but bypassed: rule=\(routingDecision.ruleId.rawValue) route=\(routingDecision.routeTarget.rawValue) model=\(routingDecision.model)")
            logger.info("📋 Confirmation UI deferred to Phase 5-C (explicit auto-approval)")
        }

        // STEP 7: Execute based on routing decision
        let responseText: String
        do {
            switch routingDecision.routeTarget {
            case .local:
                log("▶️ Executing LOCAL route with model: \(routingDecision.model)")
                responseText = try await executeLocal(question: request.query, model: routingDecision.model)

            case .cloud:
                log("▶️ Executing CLOUD route with model: \(routingDecision.model)")
                responseText = try await executeCloud(question: request.query, model: routingDecision.model)
            }
        } catch {
            // Handle fallback if allowed
            if routingDecision.fallbackAllowed {
                log("⚠️ Execution failed, attempting fallback")
                responseText = try await executeFallback(question: request.query, originalRoute: routingDecision.routeTarget)
            } else {
                log("❌ Execution failed: \(error)")
                throw error
            }
        }

        log("✅ Execution complete: sessionId=\(request.sessionId)")

        let response = NoemaResponse(
            text: responseText,
            sessionId: request.sessionId
        )

        // EPIC2: Log successful execution
        constraintRuntime.logExecution(
            request: request,
            constraintResult: constraintResult,
            executionResult: .success(response)
        )

        return response
    }

    // MARK: - Private Helpers

    /// Build NoemaQuestion from NoemaRequest
    private func buildNoemaQuestion(from request: NoemaRequest) -> NoemaQuestion {
        return NoemaQuestion(
            id: UUID(),
            content: request.query,
            privacyLevel: .auto,  // Phase 5-B: Default to auto (UI picker deferred)
            intent: nil,           // Phase 5-B: No intent classifier yet
            sessionId: request.sessionId
        )
    }

    /// Build RuntimeState from current environment
    private func buildRuntimeState() -> RuntimeState {
        // Phase 5-B: Stub implementation with safe defaults
        // Network detection and local model introspection deferred to Phase 5-C

        let localModelCapability = LocalModelCapability(
            modelName: modelManager.currentModelID ?? "unknown",
            maxTokens: 8192,  // Safe default
            supportedIntents: [.informational, .analytical, .retrieval],
            available: true   // Assume available (Phase 5-B simplification)
        )

        return RuntimeState(
            localModelCapability: localModelCapability,
            networkState: .online,  // Phase 5-B: Assume online
            tokenThreshold: 4096,
            cloudModelName: "gpt-4"  // Phase 5-B: Hardcoded
        )
    }

    /// Execute local route
    private func executeLocal(question: String, model: String) async throws -> String {
        // Phase 5-B: Delegate to ModelManager (existing local execution)
        return await modelManager.generateAsyncAnswer(question: question)
    }

    /// Execute cloud route
    private func executeCloud(question: String, model: String) async throws -> String {
        // Phase 5-B: Cloud execution not implemented yet
        throw RoutingError.cloudExecutionNotImplemented
    }

    /// Execute fallback (local → cloud or vice versa)
    private func executeFallback(question: String, originalRoute: ExecutionRoute) async throws -> String {
        // Phase 5-B: Fallback logic
        switch originalRoute {
        case .local:
            log("🔄 Fallback: local → cloud")
            return try await executeCloud(question: question, model: "gpt-4")
        case .cloud:
            log("🔄 Fallback: cloud → local")
            return try await executeLocal(question: question, model: "unknown")
        }
    }

    /// Structured logging helper
    private func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}

// MARK: - Additional Routing Error

extension RoutingError {
    static let cloudExecutionNotImplemented = RoutingError.networkUnavailable  // Temporary
}
