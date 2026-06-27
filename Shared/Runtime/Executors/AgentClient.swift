// NoesisNoema - Hybrid Routing Runtime
// AgentClient Protocol
// Created: 2026-03-08
// License: MIT License

import Foundation

/// Agent Client protocol for remote agent communication
///
/// This protocol defines the interface for communicating with noema-agent API.
/// The actual HTTP implementation to be provided separately.
///
/// Constitutional Constraints (ADR-0000):
/// - AgentClient is a pure I/O component (no business logic)
/// - No routing decisions
/// - No retry logic (errors propagate)
/// - No fallback logic
///
/// Protocol definition only.
/// Concrete implementation in Networking/AgentClient.swift
protocol AgentClient {
    /// Query the remote agent (existing v1/query endpoint).
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

    /// Consult the agent for a route decision (Route Contract v0, POST /v1/route).
    ///
    /// This is the connection seam for Issue #120. The caller must decide what
    /// to do with the result; this method is pure I/O — no routing logic.
    ///
    /// - Parameters:
    ///   - query: The user's query text
    ///   - sessionId: Session identifier for context
    /// - Returns: AgentRouteDecision containing the route string
    /// - Throws: Network errors, HTTP errors, JSON decoding errors
    func requestRoute(
        query: String,
        sessionId: UUID
    ) async throws -> AgentRouteDecision
}
