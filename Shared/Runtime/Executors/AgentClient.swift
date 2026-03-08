// NoesisNoema - Hybrid Routing Runtime
// AgentClient Protocol
// Created: 2026-03-08
// License: MIT License

import Foundation

/// Agent Client protocol for remote agent communication
///
/// This protocol defines the interface for communicating with noema-agent API.
/// The actual HTTP implementation will be provided in Phase3.
///
/// Constitutional Constraints (ADR-0000):
/// - AgentClient is a pure I/O component (no business logic)
/// - No routing decisions
/// - No retry logic (errors propagate)
/// - No fallback logic
///
/// Phase2: Protocol definition only
/// Phase3: Concrete implementation in Networking/AgentClient.swift
protocol AgentClient {
    /// Query the remote agent
    ///
    /// - Parameters:
    ///   - query: The user's query text
    ///   - sessionId: Session identifier for context
    /// - Returns: Response text from the agent
    /// - Throws: Network errors, HTTP errors, parsing errors
    func query(
        query: String,
        sessionId: UUID
    ) async throws -> String
}
