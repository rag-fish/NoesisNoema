//
//  ExecutionTrace.swift
//  NoesisNoema
//
//  Purpose: Runtime observability for execution pipeline
//  License: MIT License
//

import Foundation

/// Captures runtime metadata for each execution
struct ExecutionTrace: Codable {
    let traceId: UUID
    let query: String
    let route: RoutingDecision
    let policy: PolicyTrace?
    let routing: RoutingTrace?
    let executor: String
    let duration: TimeInterval
    let timestamp: Date
    let decisionReason: String?
    let error: String?
}
