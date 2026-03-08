// NoesisNoema - Hybrid Routing Runtime
// Router - Pure decision function
// Created: 2026-03-07
// License: MIT License

import Foundation

/// Deterministic Router
///
/// Constitutional Constraints (ADR-0000):
/// 1. MUST be side-effect free (no I/O, no logging, no state mutation)
/// 2. MUST be deterministic (same input → same output)
/// 3. MUST NOT contain randomness or time-based branching
/// 4. MUST NOT execute tasks (only makes routing decisions)
/// 5. MUST execute client-side only (never server-side)
///
/// The Router converts PolicyResult signals into ExecutionRoute decisions.
/// It is a pure transformation function with zero side effects.
///
/// Routing Rules (Priority Order):
/// 1. If toolRequired → .cloud (tools need cloud capabilities)
/// 2. Else if privacySensitive → .local (privacy stays local)
/// 3. Else if lowLatencyPreferred → .local (fast queries stay local)
/// 4. Else → .cloud (default to cloud for complex queries)
final class HybridRouter {

    /// Route a policy evaluation result to an execution target
    ///
    /// This is a pure function with zero side effects.
    /// Given identical PolicyResult input, it always produces the same ExecutionRoute.
    ///
    /// - Parameter policy: The PolicyResult from HybridPolicyEngine
    /// - Returns: ExecutionRoute decision (.local or .cloud)
    func route(_ policy: PolicyResult) -> ExecutionRoute {
        // Rule 1: Tool requirements need cloud agent capabilities
        if policy.toolRequired {
            return .cloud
        }

        // Rule 2: Privacy-sensitive data stays on device
        if policy.privacySensitive {
            return .local
        }

        // Rule 3: Low-latency queries use local LLM
        if policy.lowLatencyPreferred {
            return .local
        }

        // Rule 4: Default to cloud for complex queries
        return .cloud
    }
}
