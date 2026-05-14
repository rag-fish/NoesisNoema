//
//  TraceDebugPrinter.swift
//  NoesisNoema
//
//  Purpose: Debug utility for printing execution traces
//  Updated: 2026-05-15 — step-level RoutingStepTrace output (Phase 3, Issue #70)
//  License: MIT License
//

import Foundation

/// Debug printer for execution traces.
///
/// When a trace contains a RoutingStepTrace (i.e. it was captured with
/// RuntimeState.debugMode == true), printTrace() emits step-level output
/// showing which routing step terminated and why.
final class TraceDebugPrinter {

    private let query: TraceQuery
    private let dateFormatter: DateFormatter

    init(query: TraceQuery = TraceQuery()) {
        self.query = query
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss"
    }

    // MARK: - Public API

    /// Print recent traces in readable format
    func printRecentTraces(limit: Int = 10) async {
        let traces = await query.recent(limit: limit)
        print("=== Recent Execution Traces (\(traces.count)) ===\n")
        for trace in traces {
            printTrace(trace)
        }
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
            for trace in localTraces.suffix(5) { printTrace(trace) }
        }
        if !cloudTraces.isEmpty {
            print("\n--- Cloud Traces ---")
            for trace in cloudTraces.suffix(5) { printTrace(trace) }
        }
    }

    // MARK: - Core Print

    /// Print a single trace.
    /// When trace.routingSteps is present, emits step-level routing detail.
    ///
    /// Example output (without step trace):
    ///   [14:32:01] route=local duration=0.003s
    ///   query="What is the capital of France?"
    ///   decision="Token count within threshold, local model capable"
    ///
    /// Example output (with step trace):
    ///   [14:32:01] route=local duration=0.003s
    ///   query="What is the capital of France?"
    ///   [STEP 1 policyEnforcement]  passedThrough — action=allow
    ///   [STEP 2 privacyEnforcement] passedThrough — privacyLevel=auto
    ///   [STEP 3 autoModeLogic]      terminated    — tokens=7≤threshold=4096 localAvail=true intentOK=true → AUTO_LOCAL
    private func printTrace(_ trace: ExecutionTrace) {
        let time = dateFormatter.string(from: trace.timestamp)
        let route = trace.route.routeTarget.rawValue
        let duration = String(format: "%.3f", trace.duration)

        print("[\(time)] route=\(route) duration=\(duration)s")

        // Query preview (truncated; raw content is not logged in full)
        let queryPreview = trace.query.count > 60
            ? String(trace.query.prefix(60)) + "..."
            : trace.query
        print("query=\"\(queryPreview)\"")

        if let steps = trace.routingSteps {
            // Step-level output when debug trace is available
            printRoutingSteps(steps)
        } else {
            // Compact output for production traces (no step trace)
            if let reason = trace.decisionReason {
                print("decision=\"\(reason)\"")
            } else if let routingReason = trace.routing?.decisionReason {
                print("decision=\"\(routingReason)\"")
            }
        }

        if let error = trace.error {
            print("error=\"\(error)\"")
        }

        print()
    }

    // MARK: - Step-Level Output

    /// Emit step-by-step routing detail from a RoutingStepTrace.
    private func printRoutingSteps(_ stepTrace: RoutingStepTrace) {
        let stepWidth = 20  // column width for step name
        let outcomeWidth = 14

        for (index, record) in stepTrace.steps.enumerated() {
            let stepNum = index + 1
            let stepName = record.step.rawValue
            let outcome = record.outcome.rawValue
            let isFinal = record.step == stepTrace.terminatingStep

            // Pad columns for readable alignment
            let stepCol = "STEP \(stepNum) \(stepName)".padding(toLength: stepWidth + 7, withPad: " ", startingAt: 0)
            let outcomeCol = outcome.padding(toLength: outcomeWidth, withPad: " ", startingAt: 0)
            let finalMark = isFinal ? " ◄" : ""

            print("[\(stepCol)] \(outcomeCol)— \(record.detail)\(finalMark)")
        }
    }
}
