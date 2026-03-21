//
//  TraceSink.swift
//  NoesisNoema
//
//  Purpose: Protocol for persistent trace storage
//  License: MIT License
//

import Foundation

/// Protocol for writing execution traces to persistent storage
protocol TraceSink {
    /// Write an execution trace to the sink
    /// - Parameter trace: The execution trace to persist
    func write(trace: ExecutionTrace) async
}
