// NoesisNoema - Hybrid Routing Runtime
// ExecutionCoordinator - Orchestrates full runtime flow
// Created: 2026-03-08
// Updated: 2026-05-15 — unified onto Router.swift + PolicyEngine.swift (Issue #70)
// Updated: 2026-05-15 — human override mechanism (Issue #69)
// License: MIT License

import Foundation

/// Hybrid Execution Coordinator
///
/// Orchestrates the complete hybrid routing runtime flow:
/// 1. Build NoemaQuestion from NoemaRequest
/// 2. Build RuntimeState (with overrideMode injected from call site)
/// 3. PolicyEngine evaluates question → PolicyEvaluationResult
/// 4. applyOverride() replaces effectiveAction when overrideMode != .none
/// 5. Router determines route → RoutingDecision (+ RoutingStepTrace if debugMode)
/// 6. Select appropriate executor
/// 7. Execute query
/// 8. Record ExecutionTrace via TraceCollector
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
        rulesProvider: PolicyRulesProvider = DefaultPolicyRulesProvider()
    ) {
        self.localExecutor = localExecutor
        self.agentExecutor = agentExecutor
        self.rulesProvider = rulesProvider
    }

    /// Execute a request through the hybrid runtime (`ExecutionCoordinating`).
    ///
    /// This is the protocol entry point. It forwards to
    /// `execute(request:overrideMode:)` with `.none`, preserving normal policy
    /// evaluation and routing. Callers holding a concrete
    /// `HybridExecutionCoordinator` can invoke the override-aware overload
    /// directly to express a human-initiated routing override (Issue #69).
    func execute(request: NoemaRequest) async throws -> NoemaResponse {
        try await execute(request: request, overrideMode: .none)
    }

    /// Execute a request through the hybrid runtime.
    ///
    /// - Parameters:
    ///   - request: The NoemaRequest to execute.
    ///   - overrideMode: Human-initiated routing override. Default .none preserves
    ///     normal policy evaluation and routing. When set to .forceLocal or
    ///     .forceRemote, applyOverride() replaces the PolicyEngine result before
    ///     Router is called. This is runtime control metadata, not request content,
    ///     which is why it lives here rather than on NoemaRequest.
    /// - Returns: NoemaResponse with output and session ID
    /// - Throws: Execution errors (network, model failure, policy violation, etc.)
    func execute(
        request: NoemaRequest,
        overrideMode: HumanOverrideMode = .none
    ) async throws -> NoemaResponse {
        let traceId = UUID()
        let executionStart = Date()

        // Step 1: Build RuntimeState.
        // overrideMode is injected from the call site here — the Coordinator
        // never decides the override autonomously.
        let runtimeState = buildRuntimeState(overrideMode: overrideMode)

        // Step 2: Build NoemaQuestion from NoemaRequest.
        let question = buildQuestion(from: request)

        // Step 3: Evaluate policy rules via canonical PolicyEngine.
        let policyStart = Date()
        let rules = await rulesProvider.loadRules()
        let basePolicyResult = try PolicyEngine.evaluate(
            question: question,
            runtimeState: runtimeState,
            rules: rules
        )
        let policyDuration = Date().timeIntervalSince(policyStart)

        // Step 4: Apply human override.
        // When overrideMode != .none, the human's intent supersedes PolicyEngine.
        // The override is expressed as a PolicyEvaluationResult so Router
        // processes it through STEP 1 unchanged — no new routing logic needed.
        let policyResult = applyOverride(basePolicyResult, override: overrideMode)

        let policyTrace = PolicyTrace(
            evaluatedRules: rules.map { $0.id.uuidString },
            constraintTriggered: !policyResult.appliedConstraints.isEmpty,
            duration: policyDuration,
            triggeredRules: policyResult.appliedConstraints.map { $0.uuidString }
        )

        // Step 5: Route via canonical Router.
        let routingStart = Date()
        let routingDecision: RoutingDecision
        var routingStepTrace: RoutingStepTrace? = nil

        if runtimeState.debugMode {
            let result = try Router.routeWithTrace(
                question: question,
                runtimeState: runtimeState,
                policyResult: policyResult
            )
            routingDecision = result.decision
            routingStepTrace = result.trace
        } else {
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

        // Step 6: Select executor.
        let executor: Executor = routingDecision.routeTarget == .local
            ? localExecutor
            : agentExecutor

        // Step 7: Execute.
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

        // Step 8: Record trace.
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

    /// Apply a human override on top of the PolicyEngine result.
    ///
    /// When overrideMode is .none, returns base unchanged.
    /// When .forceLocal / .forceRemote, replaces effectiveAction with the
    /// corresponding PolicyAction. Existing appliedConstraints and warnings
    /// are preserved for traceability. requiresConfirmation is cleared
    /// (the human has already expressed explicit intent).
    ///
    /// This is a pure function — no I/O, no state mutation.
    private func applyOverride(
        _ base: PolicyEvaluationResult,
        override mode: HumanOverrideMode
    ) -> PolicyEvaluationResult {
        switch mode {
        case .none:
            return base
        case .forceLocal:
            return PolicyEvaluationResult(
                effectiveAction: .forceLocal,
                appliedConstraints: base.appliedConstraints,
                warnings: base.warnings,
                requiresConfirmation: false
            )
        case .forceRemote:
            // .forceRemote (user-facing) maps to .forceCloud (internal PolicyAction)
            return PolicyEvaluationResult(
                effectiveAction: .forceCloud,
                appliedConstraints: base.appliedConstraints,
                warnings: base.warnings,
                requiresConfirmation: false
            )
        }
    }

    /// Build a NoemaQuestion from a NoemaRequest.
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
    /// overrideMode is passed in from the call site — never set autonomously.
    private func buildRuntimeState(overrideMode: HumanOverrideMode) -> RuntimeState {
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
            debugMode: false,
            overrideMode: overrideMode
        )
    }
}
