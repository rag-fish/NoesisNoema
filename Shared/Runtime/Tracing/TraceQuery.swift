//
//  TraceQuery.swift
//  NoesisNoema
//
//  Purpose: Query API for execution trace analysis
//  License: MIT License
//

import Foundation

/// Query API for analyzing execution traces from file storage
final class TraceQuery {

    private let sink: TraceSink

    init(sink: TraceSink = FileTraceSink()) {
        self.sink = sink
    }

    /// Get recent traces with limit
    func recent(limit: Int = 10) async -> [ExecutionTrace] {
        do {
            let traces = try await sink.read(limit: limit)
            return traces
        } catch {
            print("TraceQuery read error: \(error)")
            return []
        }
    }

    /// Filter traces by route
    func filterByRoute(route: ExecutionRoute) async -> [ExecutionTrace] {
        do {
            // Read a larger batch to ensure we have enough after filtering
            let allTraces = try await sink.read(limit: 1000)
            return allTraces.filter { $0.route.routeTarget == route }
        } catch {
            print("TraceQuery read error: \(error)")
            return []
        }
    }

    /// Get traces that had errors
    func filterByError() async -> [ExecutionTrace] {
        do {
            // Read a larger batch to ensure we have enough after filtering
            let allTraces = try await sink.read(limit: 1000)
            return allTraces.filter { $0.error != nil }
        } catch {
            print("TraceQuery read error: \(error)")
            return []
        }
    }
}
