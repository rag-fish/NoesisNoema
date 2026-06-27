// NoesisNoema - Hybrid Routing Runtime
// HTTPAgentClient - Concrete HTTP implementation
// Created: 2026-03-08
// Updated: 2026-06-27 — add POST /v1/route support (Issue #120)
// License: MIT License

import Foundation

/// HTTP Agent Client
///
/// Concrete implementation of AgentClient protocol for HTTP communication
/// with noema-agent API.
///
/// Constitutional Constraints (ADR-0000):
/// - AgentClient is a pure I/O component (no business logic)
/// - No routing decisions
/// - No retry logic (errors propagate)
/// - No fallback logic
///
/// This is the network layer that crosses the invocation boundary
/// to communicate with the remote noema-agent runtime.
final class HTTPAgentClient: AgentClient {

    /// noema-agent POST /v1/query endpoint
    private let queryEndpoint: URL

    /// noema-agent POST /v1/route endpoint (Route Contract v0, Issue #120)
    private let routeEndpoint: URL

    /// Initialize with the full query endpoint URL (backward-compatible).
    ///
    /// The route endpoint is derived from the same host:port — e.g. if `endpoint`
    /// is `http://localhost:8080/v1/query` then route is `http://localhost:8080/v1/route`.
    ///
    /// - Parameter endpoint: Full URL to the /v1/query endpoint.
    init(endpoint: String = "http://localhost:8080/v1/query") {
        let qURL = URL(string: endpoint)!
        self.queryEndpoint = qURL
        // Derive /v1/route by climbing two path components and appending the new path.
        let base = qURL.deletingLastPathComponent().deletingLastPathComponent()
        self.routeEndpoint = base
            .appendingPathComponent("v1")
            .appendingPathComponent("route")
    }

    /// Initialize with a base URL. Derives /v1/query and /v1/route automatically.
    ///
    /// Preferred over the legacy `endpoint` init for new call sites.
    ///
    /// - Parameter baseURL: Base URL of the noema-agent instance (e.g. "http://localhost:8080").
    init(baseURL: String) {
        let base = URL(string: baseURL)!
        self.queryEndpoint = base.appendingPathComponent("v1").appendingPathComponent("query")
        self.routeEndpoint = base.appendingPathComponent("v1").appendingPathComponent("route")
    }

    // MARK: - AgentClient

    /// Query the remote agent via POST /v1/query.
    ///
    /// - Parameters:
    ///   - query: The user's query text
    ///   - sessionId: Session identifier for context
    /// - Returns: Response text from the agent
    /// - Throws: URLError for network/HTTP errors
    func query(
        query: String,
        sessionId: UUID
    ) async throws -> String {

        var request = URLRequest(url: queryEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "query": query,
            "session_id": sessionId.uuidString
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Consult the agent for a route decision via POST /v1/route (Route Contract v0).
    ///
    /// Pure I/O — no routing logic, no fallback, no retry. The caller decides
    /// what to do with the returned AgentRouteDecision.
    ///
    /// - Parameters:
    ///   - query: The user's query text
    ///   - sessionId: Session identifier for context
    /// - Returns: AgentRouteDecision containing the route string
    /// - Throws: URLError for network/HTTP errors; DecodingError for malformed JSON
    func requestRoute(
        query: String,
        sessionId: UUID
    ) async throws -> AgentRouteDecision {

        var request = URLRequest(url: routeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = AgentRouteRequest(query: query, session_id: sessionId.uuidString)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(AgentRouteDecision.self, from: data)
    }
}
