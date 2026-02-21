// NoesisNoema is a knowledge graph framework for building AI applications.
// This file defines routing errors.
// EPIC1: Client Authority Hardening (Phase 2)
// Created: 2026-02-21
// License: MIT License

import Foundation

/// Errors that can occur during routing
enum RoutingError: Error, Equatable {
    case networkUnavailable
    case policyViolation(reason: String)
    case invalidConfiguration(reason: String)

    var localizedDescription: String {
        switch self {
        case .networkUnavailable:
            return "Network is unavailable for cloud execution"
        case .policyViolation(let reason):
            return "Policy violation: \(reason)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        }
    }
}
