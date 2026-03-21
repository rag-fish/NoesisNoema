//
//  PolicyTrace.swift
//  NoesisNoema
//
//  Purpose: Runtime observability for policy evaluation
//  License: MIT License
//

import Foundation

/// Captures policy evaluation metadata
struct PolicyTrace: Codable {
    let evaluatedRules: [String]
    let constraintTriggered: Bool
    let duration: TimeInterval
    let triggeredRules: [String]
}
