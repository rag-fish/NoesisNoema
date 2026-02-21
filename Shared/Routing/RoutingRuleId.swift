// NoesisNoema is a knowledge graph framework for building AI applications.
// This file defines the RoutingRuleId enum for deterministic routing decisions.
// EPIC1: Client Authority Hardening (Phase 2)
// Created: 2026-02-21
// License: MIT License

import Foundation

/// Strongly-typed routing rule identifiers
/// Each rule ID maps to a specific decision path and is logged in RoutingDecision.ruleId
enum RoutingRuleId: String, Codable {
    case POLICY_BLOCK            // Policy engine blocked execution
    case POLICY_FORCE_LOCAL      // Policy engine forced local route
    case POLICY_FORCE_CLOUD      // Policy engine forced cloud route
    case PRIVACY_LOCAL           // User set privacy_level == .local
    case PRIVACY_CLOUD           // User set privacy_level == .cloud
    case AUTO_LOCAL              // Auto mode selected local (within threshold)
    case AUTO_CLOUD              // Auto mode selected cloud (exceeds threshold)
    case LOCAL_FAILURE_FALLBACK  // Fallback from local to cloud after failure
    case NETWORK_UNAVAILABLE     // Cloud route blocked due to network
}

extension RoutingRuleId {
    /// Human-readable description for UI display and log inspection
    var humanReadableDescription: String {
        switch self {
        case .POLICY_BLOCK:
            return "Execution blocked by policy constraint"
        case .POLICY_FORCE_LOCAL:
            return "Policy constraint forced local execution"
        case .POLICY_FORCE_CLOUD:
            return "Policy constraint forced cloud execution"
        case .PRIVACY_LOCAL:
            return "User requested local-only execution (privacy constraint)"
        case .PRIVACY_CLOUD:
            return "User requested cloud execution"
        case .AUTO_LOCAL:
            return "Auto mode: token count within local threshold"
        case .AUTO_CLOUD:
            return "Auto mode: token count exceeds local threshold or local model unavailable"
        case .LOCAL_FAILURE_FALLBACK:
            return "Local execution failed; fallback to cloud (user confirmed)"
        case .NETWORK_UNAVAILABLE:
            return "Cloud execution unavailable: no network connectivity"
        }
    }
}
