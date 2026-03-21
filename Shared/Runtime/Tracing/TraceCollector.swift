//
//  TraceCollector.swift
//  NoesisNoema
//
//  Purpose: Write-only collector for execution traces
//  License: MIT License
//

import Foundation

/// Write-only collector for execution traces
/// Note: For querying traces, use TraceQuery which reads from file
actor TraceCollector {
    static let shared = TraceCollector()

    private let sink: TraceSink = FileTraceSink()

    private init() {}

    /// Record a new execution trace (writes to file)
    func record(_ trace: ExecutionTrace) async {
        await sink.write(trace: trace)
    }
}
