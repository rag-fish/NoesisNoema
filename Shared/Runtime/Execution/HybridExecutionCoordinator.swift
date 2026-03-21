// NoesisNoema - Hybrid Routing Runtime
// ExecutionCoordinator - Orchestrates full runtime flow
// Created: 2026-03-08
// License: MIT License

import Foundation

/// Hybrid Execution Coordinator
///
/// Orchestrates the complete hybrid routing runtime flow:
/// 1. Evaluate policy signals
/// 2. Determine routing decision
/// 3. Select appropriate executor
/// 4. Execute query
///
/// Constitutional Constraints (ADR-0000):
/// - Owns routing orchestration
/// - Executors remain pure execution components
/// - No fallback logic
/// - No retry logic
/// - No silent error recovery
///
/// This is the integration point for all hybrid runtime components.
final class HybridExecutionCoordinator: ExecutionCoordinating {

    /// Policy evaluation engine
    private let policyEngine = HybridPolicyEngine()

    /// Routing decision function
    private let router = HybridRouter()

    /// Local executor (on-device)
    private let localExecutor: Executor

    /// Agent executor (cloud)
    private let agentExecutor: Executor

    /// Initialize with executors
    ///
    /// - Parameters:
    ///   - localExecutor: Executor for local execution (default: LocalExecutor)
    ///   - agentExecutor: Executor for remote execution (default: AgentExecutor with HTTPAgentClient)
    init(
        localExecutor: Executor = LocalExecutor(),
        agentExecutor: Executor = AgentExecutor(client: HTTPAgentClient())
    ) {
        self.localExecutor = localExecutor
        self.agentExecutor = agentExecutor
    }

    /// Execute a request through the hybrid runtime
    ///
    /// Flow:
    /// 1. PolicyEngine evaluates request → PolicyResult
    /// 2. Router determines route → ExecutionRoute
    /// 3. Select executor based on route
    /// 4. Execute query → ExecutionResult
    ///
    /// - Parameter request: The NoemaRequest to execute
    /// - Returns: NoemaResponse with output and session ID
    /// - Throws: Execution errors (network, model failure, etc.)
    func execute(request: NoemaRequest) async throws -> NoemaResponse {
        let traceId = UUID()
        let executionStart = Date()

        // Step 1: Evaluate policy signals
        let policyStart = Date()
        let policy = policyEngine.evaluate(request)
        let policyDuration = Date().timeIntervalSince(policyStart)

        let policyTrace = PolicyTrace(
            evaluatedRules: ["tool_detection", "privacy_detection", "latency_preference"],
            constraintTriggered: policy.toolRequired || policy.privacySensitive,
            duration: policyDuration
        )

        // Step 2: Determine routing decision
        let routingStart = Date()
        let route = router.route(policy)
        let routingDuration = Date().timeIntervalSince(routingStart)

        // Create routing decision for trace
        let routingDecision = RoutingDecision(
            routeTarget: route,
            model: route == .local ? "local-llm" : "cloud-agent",
            reason: determineRoutingReason(policy: policy, route: route),
            ruleId: determineRuleId(policy: policy, route: route),
            fallbackAllowed: false,
            requiresConfirmation: false,
            confidence: 1.0
        )

        let routingTrace = RoutingTrace(
            ruleId: routingDecision.ruleId.rawValue,
            decision: routingDecision,
            duration: routingDuration
        )

        // Step 3: Select executor based on route
        let executor: Executor = route == .local
            ? localExecutor
            : agentExecutor

        // Step 4: Execute query
        let result = try await executor.execute(
            query: request.query,
            sessionId: request.sessionId
        )

        // Calculate total duration
        let totalDuration = Date().timeIntervalSince(executionStart)

        // Create and record execution trace
        let executionTrace = ExecutionTrace(
            traceId: traceId,
            query: request.query,
            route: routingDecision,
            policy: policyTrace,
            routing: routingTrace,
            executor: route == .local ? "LocalExecutor" : "AgentExecutor",
            duration: totalDuration,
            timestamp: executionStart
        )

        await TraceCollector.shared.record(executionTrace)

        // Step 5: Convert to NoemaResponse
        return NoemaResponse(
            text: result.output,
            sessionId: request.sessionId
        )
    }

    /// Determine routing reason based on policy signals
    private func determineRoutingReason(policy: PolicyResult, route: ExecutionRoute) -> String {
        if policy.toolRequired {
            return "Tool/function calling required (cloud)"
        } else if policy.privacySensitive {
            return "Privacy-sensitive data detected (local)"
        } else if policy.lowLatencyPreferred {
            return "Low-latency preference (local)"
        } else {
            return "Complex query routed to cloud"
        }
    }

    /// Determine rule ID based on policy signals
    private func determineRuleId(policy: PolicyResult, route: ExecutionRoute) -> RoutingRuleId {
        if policy.toolRequired {
            return .POLICY_FORCE_CLOUD
        } else if policy.privacySensitive {
            return .POLICY_FORCE_LOCAL
        } else if policy.lowLatencyPreferred {
            return .AUTO_LOCAL
        } else {
            return .AUTO_CLOUD
        }
    }
}
