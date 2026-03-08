// NoesisNoema - Hybrid Routing Runtime
// PolicyResult data structure
// Created: 2026-03-07
// License: MIT License

import Foundation

/// Policy evaluation result containing routing signals
///
/// This structure captures the outcome of policy evaluation.
/// It contains signals (not decisions) that inform the Router.
///
/// Constitutional Constraint (ADR-0000):
/// - This is a pure data structure with no behavior
/// - It represents signals, not routing decisions
/// - PolicyEngine produces this; Router consumes it
struct PolicyResult: Equatable {
    /// Does the request require tool/function calling capabilities?
    let toolRequired: Bool

    /// Does the request contain privacy-sensitive information?
    let privacySensitive: Bool

    /// Is low-latency response time preferred?
    let lowLatencyPreferred: Bool

    init(
        toolRequired: Bool,
        privacySensitive: Bool,
        lowLatencyPreferred: Bool
    ) {
        self.toolRequired = toolRequired
        self.privacySensitive = privacySensitive
        self.lowLatencyPreferred = lowLatencyPreferred
    }
}
