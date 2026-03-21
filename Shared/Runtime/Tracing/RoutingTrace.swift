//
//  RoutingTrace.swift
//  NoesisNoema
//
//  Purpose: Runtime observability for routing decisions
//  License: MIT License
//

import Foundation

/// Captures routing decision metadata
struct RoutingTrace: Codable {
    let ruleId: String
    let decision: RoutingDecision
    let duration: TimeInterval
}
