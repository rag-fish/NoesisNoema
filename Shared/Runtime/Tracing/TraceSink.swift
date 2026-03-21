//
//  TraceSink.swift
//  NoesisNoema
//
//  Purpose: Protocol for persistent trace storage
//  License: MIT License
//

import Foundation

/// Protocol for reading and writing execution traces to persistent storage
protocol TraceSink {
    /// Write an execution trace to the sink
    /// - Parameter trace: The execution trace to persist
    func write(trace: ExecutionTrace) async

    /// Read traces from the sink
    /// - Parameter limit: Maximum number of traces to read (most recent)
    /// - Returns: Array of execution traces
    /// - Throws: IO or decoding errors
    func read(limit: Int) async throws -> [ExecutionTrace]
}
