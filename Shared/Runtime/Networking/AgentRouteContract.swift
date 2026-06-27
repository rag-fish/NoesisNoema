// NoesisNoema - noema-agent connection seam
// Route Contract v0 — POST /v1/route
// Created: 2026-06-27
// License: MIT License

import Foundation

/// Request payload for POST /v1/route
struct AgentRouteRequest: Encodable {
    let query: String
    let session_id: String
}

/// Route decision returned by POST /v1/route
///
/// The `route` field is the canonical route identifier returned by noema-agent.
/// Known values as of Route Contract v0:
///   - "local_echo"  → continue existing local RAG execution (the only supported value)
///   - Any other     → log unsupported, fall back to local execution
///
/// Additional fields in the server response are silently ignored (`unknownKeys`
/// decoding strategy handles forward compatibility).
struct AgentRouteDecision: Decodable {
    let route: String

    /// Returns true when the agent selected local-only execution.
    var isLocalEcho: Bool { route == "local_echo" }
}
