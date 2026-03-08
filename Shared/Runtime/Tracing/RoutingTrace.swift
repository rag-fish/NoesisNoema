//
//  RoutingTrace.swift
//  NoesisNoema
//
//  Purpose: Runtime observability for routing decisions
//  License: MIT License
//

import Foundation

/// Captures routing decision metadata
struct RoutingTrace {
    let ruleId: String
    let decision: RoutingDecision
}
