//
//  TraceCollector.swift
//  NoesisNoema
//
//  Purpose: Thread-safe storage and retrieval for execution traces
//  License: MIT License
//

import Foundation

/// Thread-safe collector for execution traces
actor TraceCollector {
    static let shared = TraceCollector()

    private var traces: [ExecutionTrace] = []

    private init() {}

    /// Record a new execution trace
    func record(_ trace: ExecutionTrace) {
        traces.append(trace)
    }

    /// Retrieve all traces
    func getAllTraces() -> [ExecutionTrace] {
        return traces
    }

    /// Retrieve traces by query
    func getTraces(matching query: String) -> [ExecutionTrace] {
        return traces.filter { $0.query.contains(query) }
    }

    /// Retrieve trace by ID
    func getTrace(byId traceId: UUID) -> ExecutionTrace? {
        return traces.first { $0.traceId == traceId }
    }

    /// Get recent traces
    func getRecentTraces(limit: Int = 10) -> [ExecutionTrace] {
        return Array(traces.suffix(limit))
    }

    /// Clear all traces
    func clearAll() {
        traces.removeAll()
    }

    /// Get trace count
    func count() -> Int {
        return traces.count
    }
}
