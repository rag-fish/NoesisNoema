// NoesisNoema - Hybrid Routing Runtime
// Router - Pure decision function
// Created: 2026-03-07
// DEPRECATED: 2026-05-15 (Issue #70)
//   HybridRouter is no longer used in the execution path.
//   All routing decisions now flow through the canonical Router
//   (Shared/Routing/Router.swift), which implements the full 4-step
//   deterministic algorithm with step-level trace support.
//   This file is retained for reference. Do not use in new code.
// License: MIT License

import Foundation

/// - Warning: Deprecated. See file header.
final class HybridRouter {

    @available(*, deprecated, message: "Use Router.route(question:runtimeState:policyResult:) instead.")
    func route(_ policy: PolicyResult) -> ExecutionRoute {
        if policy.toolRequired { return .cloud }
        if policy.privacySensitive { return .local }
        if policy.lowLatencyPreferred { return .local }
        return .cloud
    }
}
