// NoesisNoema - Hybrid Routing Runtime
// HTTPAgentClient - Concrete HTTP implementation
// Created: 2026-03-08
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

    /// Agent endpoint URL
    private let endpoint: URL

    /// Initialize with agent endpoint
    /// - Parameter endpoint: The noema-agent API endpoint URL (default: localhost:8080)
    init(endpoint: String = "http://localhost:8080/v1/query") {
        self.endpoint = URL(string: endpoint)!
    }

    /// Query the remote agent
    ///
    /// Sends HTTP POST request to noema-agent with JSON payload.
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

        // Build HTTP POST request
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build JSON payload
        let payload: [String: Any] = [
            "query": query,
            "session_id": sessionId.uuidString
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Execute HTTP request
        let (data, response) = try await URLSession.shared.data(for: request)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Parse response as string
        return String(data: data, encoding: .utf8) ?? ""
    }
}
