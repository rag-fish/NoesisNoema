// NoesisNoema - Hybrid Routing Runtime
// ExecutionCoordinator - Orchestrates full runtime flow
// Created: 2026-03-08
// Updated: 2026-05-15 — unified onto Router.swift + PolicyEngine.swift (Issue #70)
// Updated: 2026-05-15 — human override mechanism (Issue #69)
// Updated: 2026-06-27 — optional noema-agent route consultation seam (Issue #120)
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
        #if DEBUG
        print("🧠 [SESSION-MEM/COORD] request.history.count=\(request.history.count)")
        #endif
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

        // Step 5.5: Optional agent route consultation (Issue #120).
        //
        // When enableRemoteRouting is true, consult noema-agent POST /v1/route
        // and log the decision. The result is advisory only — execution always
        // proceeds via local RAG regardless of what the agent returns.
        // Errors are swallowed here so a network failure NEVER blocks the user.
        if AppSettings.shared.enableRemoteRouting {
            await consultAgentRoute(query: request.query, sessionId: request.sessionId)
        }

        // Step 6: Select executor.
        let executor: Executor = routingDecision.routeTarget == .local
            ? localExecutor
            : agentExecutor

        // Step 6.5: Privacy enforcement — MANDATORY and non-bypassable.
        // ADR-0008 Decision 4 / execution-flow.md Step 4.5.
        //
        // This ENFORCES the routing decision; it does not re-decide. For a
        // privacy-local request the Router already returns routeTarget=.local,
        // fallbackAllowed=false (Router STEP 2). But Router STEP 1 (policy)
        // runs *before* STEP 2 — a policy .forceCloud or a human .forceRemote
        // override can yield routeTarget=.cloud even for a Question whose
        // privacyLevel is .local. The spec makes privacy non-bypassable, so a
        // privacy-local request that did not route on-device is refused here:
        // it can never reach agentExecutor (the only network-capable executor).
        let privacyVerdict = Self.evaluatePrivacyStep45(
            privacyLevel: question.privacyLevel,
            routingDecision: routingDecision
        )
        let privacyEnforced = (privacyVerdict == .satisfied)
        if case .violated(let violation) = privacyVerdict {
            // Log the enforcement with traceId via the standard trace path,
            // then throw — the agent/network executor is never invoked.
            let violationTrace = ExecutionTrace(
                traceId: traceId,
                query: request.query,
                route: routingDecision,
                policy: policyTrace,
                routing: routingTrace,
                routingSteps: routingStepTrace,
                executor: "PrivacyGuard",
                duration: Date().timeIntervalSince(executionStart),
                timestamp: executionStart,
                decisionReason: routingDecision.reason,
                error: violation,
                privacyEnforced: true
            )
            await TraceCollector.shared.record(violationTrace)

            // ADR-0000: structured throw — never silently degrade, never fall
            // through to the agent executor.
            throw ExecutionError.privacyViolation(violation)
        }

        // Step 7: Execute.
        // ADR-0009 §5: history is carried explicitly via the request and passed
        // to the executor. Routing/policy/privacy above this point have ALREADY
        // run on the current query alone (ADR-0009 §4 — history is generation-
        // only). The remote/AgentExecutor path ignores history via the default
        // protocol overload; only LocalExecutor consumes it.
        var executionError: String? = nil
        let result: ExecutionResult
        do {
            #if DEBUG
            print("🧠 [SESSION-MEM/COORD] dispatching to executor; passing history.count=\(request.history.count)")
            #endif
            result = try await executor.execute(
                query: request.query,
                sessionId: request.sessionId,
                history: request.history
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
            error: executionError,
            privacyEnforced: privacyEnforced
        )
        await TraceCollector.shared.record(executionTrace)

        // R2 (ADR-0008): propagate retrieval citations from the executor's
        // ExecutionResult into the response so the UI no longer reads them from
        // ModelManager's mutable state. Local path carries real chunks; the
        // remote/agent path carries [] (remote citations are a later task).
        return NoemaResponse(
            text: result.output,
            sources: result.sources,
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

    // MARK: - Agent Route Consultation (Issue #120)

    /// Consult noema-agent for a route decision via POST /v1/route.
    ///
    /// Advisory only — execution always falls through to local RAG.
    /// Errors are caught and logged so the user is never blocked.
    ///
    /// Logging contract (never logs query content):
    ///   - route selected
    ///   - source (agent / fallback)
    ///   - fallback reason (when applicable)
    private func consultAgentRoute(query: String, sessionId: UUID) async {
        guard ConnectivityGuard.canPerformRemoteCall() else {
            print("🔀 [AGENT-ROUTE] skipped: app is in offline mode; source=local; fallback=offline-mode")
            #if DEBUG
            Task { @MainActor in DebugRouteState.shared.update(route: "skipped", source: "offline") }
            #endif
            return
        }

        let baseURL = AppSettings.shared.agentBaseURL
        let client = HTTPAgentClient(baseURL: baseURL)

        do {
            let decision = try await client.requestRoute(query: query, sessionId: sessionId)
            let route = decision.route

            if decision.isLocalEcho {
                print("🔀 [AGENT-ROUTE] route=\(route); source=agent; continuing local execution")
            } else {
                print("🔀 [AGENT-ROUTE] route=\(route) is unsupported; source=agent; fallback=local (remote inference not yet wired)")
            }

            #if DEBUG
            Task { @MainActor in DebugRouteState.shared.update(route: route, source: "agent") }
            #endif

        } catch {
            print("🔀 [AGENT-ROUTE] route consultation failed; source=local; fallback=network-error: \(error.localizedDescription)")
            #if DEBUG
            Task { @MainActor in DebugRouteState.shared.update(route: "error", source: "local-fallback") }
            #endif
        }
    }

    // MARK: - Privacy Enforcement (ADR-0008 Decision 4 / execution-flow.md Step 4.5)

    /// Verdict of the mandatory privacy-enforcement check.
    enum PrivacyEnforcementVerdict: Equatable {
        /// The request is not privacy-local; Step 4.5 imposes no constraint.
        case notApplicable
        /// The request is privacy-local and routed on-device with no cloud
        /// fallback — the local-only invariant holds.
        case satisfied
        /// The request is privacy-local but would route off-device (or would
        /// permit cloud fallback). Execution must be refused. The associated
        /// value is a human-readable description for the error and the trace.
        case violated(String)
    }

    /// Evaluate Privacy Step 4.5 for a routed request.
    ///
    /// Pure function — no I/O, no state — so the enforcement rule is
    /// deterministic and unit-testable in isolation. It ENFORCES the routing
    /// decision; it does not re-decide.
    ///
    /// The authoritative trigger is the Question object's `privacyLevel` (the
    /// spec keys off it). `.PRIVACY_LOCAL` — the Router's corresponding ruleId
    /// — is OR-ed in as defense-in-depth.
    ///
    /// A privacy-local request is `satisfied` only when it routes on-device
    /// (`routeTarget == .local`) with no cloud fallback (`fallbackAllowed ==
    /// false`); any other outcome is `violated`.
    static func evaluatePrivacyStep45(
        privacyLevel: PrivacyLevel,
        routingDecision: RoutingDecision
    ) -> PrivacyEnforcementVerdict {
        let privacyLocal = privacyLevel == .local
            || routingDecision.ruleId == .PRIVACY_LOCAL
        guard privacyLocal else { return .notApplicable }

        guard routingDecision.routeTarget == .local
            && routingDecision.fallbackAllowed == false
        else {
            return .violated(
                "privacy_level=local but routeTarget="
                + "\(routingDecision.routeTarget.rawValue), fallbackAllowed="
                + "\(routingDecision.fallbackAllowed) (ruleId="
                + "\(routingDecision.ruleId.rawValue)). A local-only request must "
                + "execute on-device with no cloud fallback; refusing to proceed."
            )
        }
        return .satisfied
    }
}
