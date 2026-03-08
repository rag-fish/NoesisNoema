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

        // Step 1: Evaluate policy signals
        let policy = policyEngine.evaluate(request)

        // Step 2: Determine routing decision
        let route = router.route(policy)

        // Step 3: Select executor based on route
        let executor: Executor = route == .local
            ? localExecutor
            : agentExecutor

        // Step 4: Execute query
        let result = try await executor.execute(
            query: request.query,
            sessionId: request.sessionId
        )

        // Step 5: Convert to NoemaResponse
        return NoemaResponse(
            text: result.output,
            sessionId: request.sessionId
        )
    }
}
