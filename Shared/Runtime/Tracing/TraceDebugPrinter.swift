//
//  TraceDebugPrinter.swift
//  NoesisNoema
//
//  Purpose: Debug utility for printing execution traces
//  License: MIT License
//

import Foundation

/// Debug printer for execution traces
final class TraceDebugPrinter {

    private let query: TraceQuery
    private let dateFormatter: DateFormatter

    init(query: TraceQuery = TraceQuery()) {
        self.query = query
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss"
    }

    /// Print recent traces in readable format
    func printRecentTraces(limit: Int = 10) async {
        let traces = await query.recent(limit: limit)

        print("=== Recent Execution Traces (\(traces.count)) ===\n")

        for trace in traces {
            printTrace(trace)
        }
    }

    /// Print a single trace in readable format
    private func printTrace(_ trace: ExecutionTrace) {
        let time = dateFormatter.string(from: trace.timestamp)
        let route = trace.route.routeTarget.rawValue
        let duration = String(format: "%.2f", trace.duration)

        print("[\(time)] route=\(route) duration=\(duration)s")

        // Print query (truncate if too long)
        let queryPreview = trace.query.count > 60
            ? String(trace.query.prefix(60)) + "..."
            : trace.query
        print("query=\"\(queryPreview)\"")

        // Print decision reason
        if let reason = trace.decisionReason {
            print("decision=\"\(reason)\"")
        } else if let routingReason = trace.routing?.decisionReason {
            print("decision=\"\(routingReason)\"")
        }

        // Print error if present
        if let error = trace.error {
            print("error=\"\(error)\"")
        }

        print()
    }

    /// Print error traces only
    func printErrorTraces() async {
        let traces = await query.filterByError()

        print("=== Error Traces (\(traces.count)) ===\n")

        for trace in traces {
            printTrace(trace)
        }
    }

    /// Print traces grouped by route
    func printTracesByRoute() async {
        let localTraces = await query.filterByRoute(route: .local)
        let cloudTraces = await query.filterByRoute(route: .cloud)

        print("=== Traces by Route ===\n")
        print("Local: \(localTraces.count)")
        print("Cloud: \(cloudTraces.count)")

        if !localTraces.isEmpty {
            print("\n--- Local Traces ---")
            for trace in localTraces.suffix(5) {
                printTrace(trace)
            }
        }

        if !cloudTraces.isEmpty {
            print("\n--- Cloud Traces ---")
            for trace in cloudTraces.suffix(5) {
                printTrace(trace)
            }
        }
    }
}
