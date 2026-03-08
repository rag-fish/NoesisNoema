//
//  ExecutionTrace.swift
//  NoesisNoema
//
//  Purpose: Runtime observability for execution pipeline
//  License: MIT License
//

import Foundation

/// Captures runtime metadata for each execution
struct ExecutionTrace {
    let traceId: UUID
    let query: String
    let route: RoutingDecision
    let executor: String
    let duration: TimeInterval
    let timestamp: Date
}
