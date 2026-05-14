// NoesisNoema - Hybrid Routing Runtime
// ExecutionCoordinator - Orchestrates full runtime flow
// Created: 2026-03-08
// Updated: 2026-05-15 — unified onto Router.swift + PolicyEngine.swift (Issue #70)
//   HybridPolicyEngine and HybridRouter are now deprecated.
//   All routing decisions flow through the canonical Router and PolicyEngine.
// License: MIT License

import Foundation

/// Hybrid Execution Coordinator
///
/// Orchestrates the complete hybrid routing runtime flow:
/// 1. Evaluate policy signals via PolicyEngine (canonical)
/// 2. Determine routing decision via Router (canonical)
/// 3. Select appropriate executor
/// 4. Execute query
/// 5. Record ExecutionTrace (with RoutingStepTrace when debugMode == true)
///
/// Constitutional Constraints (ADR-0000):
/// - Owns routing orchestration
/// - Executors remain pure execution components
/// - No fallback logic
/// - No retry logic
/// - No silent error recovery
final class HybridExecutionCoordinator: ExecutionCoordinating {

    /// Local executor (on-device)
    private let localExecutor: Executor

    /// Agent executor (cloud)
    private let agentExecutor: Executor

    /// Policy rules provider
    private let rulesProvider: PolicyRulesProvider

    /// Initialize with executors and optional rules provider
    init(
        localExecutor: Executor = LocalExecutor(),
        agentExecutor: Executor = AgentExecutor(client: HTTPAgentClient()),
        rulesProvider: PolicyRulesProvider = PolicyRulesProvider()
    ) {
        self.localExecutor = localExecutor
        self.agentExecutor = agentExecutor
        self.rulesProvider = rulesProvider
    }

    /// Execute a request through the hybrid runtime
    ///
    /// Flow:
    /// 1. Build NoemaQuestion from NoemaRequest
    /// 2. Build RuntimeState from current environment
    /// 3. PolicyEngine evaluates question → PolicyEvaluationResult
    /// 4. Router determines route → RoutingDecision (+ RoutingStepTrace if debugMode)
    /// 5. Select executor based on routeTarget
    /// 6. Execute query → ExecutionResult
    /// 7. Record ExecutionTrace via TraceCollector
    ///
    /// - Parameter request: The NoemaRequest to execute
    /// - Returns: NoemaResponse with output and session ID
    /// - Throws: Execution errors (network, model failure, policy violation, etc.)
    func execute(request: NoemaRequest) async throws -> NoemaResponse {
        let traceId = UUID()
        let executionStart = Date()

        // Step 1: Build RuntimeState
        // RuntimeState is the single source of truth for routing environment.
        // debugMode is read from environment/config; false by default.
        let runtimeState = buildRuntimeState()

        // Step 2: Build NoemaQuestion from NoemaRequest.
        // Routing signals (toolRequired, privacySensitive, lowLatencyPreferred)
        // are derived here from the request content, then stored on the question.
        // This replaces the role HybridPolicyEngine previously played.
        let question = buildQuestion(from: request)

        // Step 3: Evaluate policy rules via canonical PolicyEngine
        let policyStart = Date()
        let rules = await rulesProvider.loadRules()
        let policyResult = try PolicyEngine.evaluate(
            question: question,
            runtimeState: runtimeState,
            rules: rules
        )
        let policyDuration = Date().timeIntervalSince(policyStart)

        let policyTrace = PolicyTrace(
            evaluatedRules: rules.map { $0.id.uuidString },
            constraintTriggered: !policyResult.appliedConstraints.isEmpty,
            duration: policyDuration,
            triggeredRules: policyResult.appliedConstraints.map { $0.uuidString }
        )

        // Step 4: Route via canonical Router
        let routingStart = Date()
        let routingDecision: RoutingDecision
        var routingStepTrace: RoutingStepTrace? = nil

        if runtimeState.debugMode {
            // Debug path: capture step-level trace alongside the decision.
            // routeWithTrace() is pure — no logs, no I/O, no state mutation.
            let result = try Router.routeWithTrace(
                question: question,
                runtimeState: runtimeState,
                policyResult: policyResult
            )
            routingDecision = result.decision
            routingStepTrace = result.trace
        } else {
            // Production path: decision only.
            routingDecision = try Router.route(
                question: question,
                runtimeState: runtimeState,
                policyResult: policyResult
            )
        }
        let routingDuration = Date().timeIntervalSince(routingStart)

        let routingTrace = RoutingTrace(
            ruleId: routingDecision.ruleId.rawValue,
            decision: routingDecision,
            duration: routingDuration,
            decisionReason: routingDecision.reason
        )

        // Step 5: Select executor
        let executor: Executor = routingDecision.routeTarget == .local
            ? localExecutor
            : agentExecutor

        // Step 6: Execute
        var executionError: String? = nil
        let result: ExecutionResult
        do {
            result = try await executor.execute(
                query: request.query,
                sessionId: request.sessionId
            )
        } catch {
            executionError = error.localizedDescription
            throw error
        }

        let totalDuration = Date().timeIntervalSince(executionStart)

        // Step 7: Record trace
        let executionTrace = ExecutionTrace(
            traceId: traceId,
            query: request.query,
            route: routingDecision,
            policy: policyTrace,
            routing: routingTrace,
            routingSteps: routingStepTrace,
            executor: routingDecision.routeTarget == .local ? "LocalExecutor" : "AgentExecutor",
            duration: totalDuration,
            timestamp: executionStart,
            decisionReason: routingDecision.reason,
            error: executionError
        )
        await TraceCollector.shared.record(executionTrace)

        return NoemaResponse(
            text: result.output,
            sessionId: request.sessionId
        )
    }

    // MARK: - Private Helpers

    /// Build a NoemaQuestion from a NoemaRequest.
    /// Derives routing signals from request content using keyword heuristics.
    /// These signals are stored on the question as first-class fields.
    private func buildQuestion(from request: NoemaRequest) -> NoemaQuestion {
        let query = request.query.lowercased()

        let toolKeywords = [
            "calendar", "email", "contacts", "tool", "agent",
            "schedule", "meeting", "appointment", "remind", "notification"
        ]
        let privacyKeywords = [
            "address", "phone", "email", "passport", "personal",
            "ssn", "social security", "credit card", "password",
            "bank", "account", "salary", "medical", "health"
        ]

        let toolRequired = toolKeywords.contains { query.contains($0) }
        let privacySensitive = privacyKeywords.contains { query.contains($0) }
        let lowLatencyPreferred = query.count < 100

        return NoemaQuestion(
            content: request.query,
            privacyLevel: .auto,
            sessionId: request.sessionId,
            toolRequired: toolRequired,
            privacySensitive: privacySensitive,
            lowLatencyPreferred: lowLatencyPreferred
        )
    }

    /// Build a RuntimeState reflecting the current device environment.
    /// In production this would read from a live state provider.
    private func buildRuntimeState() -> RuntimeState {
        RuntimeState(
            localModelCapability: LocalModelCapability(
                modelName: "llama-3.2-8b",
                maxTokens: 4096,
                supportedIntents: [.informational, .retrieval],
                available: true
            ),
            networkState: .online,
            tokenThreshold: 4096,
            cloudModelName: "gpt-4",
            debugMode: false
        )
    }
}
