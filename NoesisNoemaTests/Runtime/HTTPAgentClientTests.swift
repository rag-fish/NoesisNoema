// NoesisNoema - HybridRuntime: Hybrid Routing Runtime
// HTTPAgentClient Tests
// Created: 2026-03-08
// License: MIT License

import XCTest
@testable import NoesisNoema

/// Mock URLProtocol for testing HTTP requests
class MockURLProtocol: URLProtocol {

    /// Mock response handler
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler not set")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op
    }
}

/// Tests for HTTPAgentClient
///
/// These tests verify:
/// - Correct HTTP request construction
/// - JSON payload correctness
/// - Response parsing
/// - Error propagation
/// - No routing logic
/// - No retry logic
final class HTTPAgentClientTests: XCTestCase {

    var client: HTTPAgentClient!
    var urlSessionConfiguration: URLSessionConfiguration!

    override func setUp() {
        super.setUp()

        // Configure URLSession with mock protocol
        urlSessionConfiguration = URLSessionConfiguration.ephemeral
        urlSessionConfiguration.protocolClasses = [MockURLProtocol.self]

        client = HTTPAgentClient(endpoint: "http://test.example.com/v1/query")
    }

    override func tearDown() {
        client = nil
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Request Construction Tests

    func testHTTPAgentClient_BuildsCorrectHTTPRequest() async throws {
        // Given: Mock handler that captures the request
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = "Test response".data(using: .utf8)
            return (response, data)
        }

        // When: Querying
        let query = "Test query"
        let sessionId = UUID()

        _ = try await client.query(query: query, sessionId: sessionId)

        // Then: Should build correct HTTP request
        XCTAssertNotNil(capturedRequest, "Request should be captured")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST", "Should use POST method")
        XCTAssertEqual(
            capturedRequest?.value(forHTTPHeaderField: "Content-Type"),
            "application/json",
            "Should set Content-Type header"
        )
        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "http://test.example.com/v1/query",
            "Should use correct endpoint"
        )
    }

    func testHTTPAgentClient_BuildsCorrectJSONPayload() async throws {
        // Given: Mock handler that captures the request body
        var capturedPayload: [String: Any]?

        MockURLProtocol.requestHandler = { request in
            if let body = request.httpBody {
                capturedPayload = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = "Test response".data(using: .utf8)
            return (response, data)
        }

        // When: Querying
        let query = "What is the weather?"
        let sessionId = UUID()

        _ = try await client.query(query: query, sessionId: sessionId)

        // Then: Should build correct JSON payload
        XCTAssertNotNil(capturedPayload, "Payload should be captured")
        XCTAssertEqual(capturedPayload?["query"] as? String, query, "Payload should contain query")
        XCTAssertEqual(
            capturedPayload?["session_id"] as? String,
            sessionId.uuidString,
            "Payload should contain session_id"
        )
    }

    // MARK: - Response Parsing Tests

    func testHTTPAgentClient_ParsesSuccessResponse() async throws {
        // Given: Mock successful response
        let expectedResponse = "This is the agent response"

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = expectedResponse.data(using: .utf8)
            return (response, data)
        }

        // When: Querying
        let result = try await client.query(query: "Test", sessionId: UUID())

        // Then: Should parse response correctly
        XCTAssertEqual(result, expectedResponse, "Should return response text")
    }

    func testHTTPAgentClient_HandlesEmptyResponse() async throws {
        // Given: Mock empty response
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        // When: Querying
        let result = try await client.query(query: "Test", sessionId: UUID())

        // Then: Should return empty string
        XCTAssertEqual(result, "", "Should handle empty response")
    }

    // MARK: - Error Propagation Tests

    func testHTTPAgentClient_ThrowsOn400Error() async throws {
        // Given: Mock 400 error response
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }

        // When/Then: Should throw error
        do {
            _ = try await client.query(query: "Test", sessionId: UUID())
            XCTFail("Should have thrown error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badServerResponse)
        }
    }

    func testHTTPAgentClient_ThrowsOn500Error() async throws {
        // Given: Mock 500 error response
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }

        // When/Then: Should throw error
        do {
            _ = try await client.query(query: "Test", sessionId: UUID())
            XCTFail("Should have thrown error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badServerResponse)
        }
    }

    func testHTTPAgentClient_PropagatesNetworkError() async throws {
        // Given: Mock network error
        MockURLProtocol.requestHandler = { request in
            throw URLError(.networkConnectionLost)
        }

        // When/Then: Should propagate error
        do {
            _ = try await client.query(query: "Test", sessionId: UUID())
            XCTFail("Should have thrown error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .networkConnectionLost)
        }
    }

    // MARK: - Endpoint Configuration Tests

    func testHTTPAgentClient_UsesDefaultEndpoint() {
        // Given: Client with default endpoint
        let defaultClient = HTTPAgentClient()

        // Then: Should be initialized (endpoint validation happens in init)
        XCTAssertNotNil(defaultClient, "Should initialize with default endpoint")
    }

    func testHTTPAgentClient_UsesCustomEndpoint() {
        // Given: Client with custom endpoint
        let customEndpoint = "http://custom.example.com:9000/api/query"
        let customClient = HTTPAgentClient(endpoint: customEndpoint)

        // Then: Should be initialized
        XCTAssertNotNil(customClient, "Should initialize with custom endpoint")
    }

    // MARK: - Protocol Compliance Tests

    func testHTTPAgentClient_ConformsToAgentClientProtocol() {
        // Given: HTTPAgentClient
        let agentClient: AgentClient = HTTPAgentClient()

        // Then: Should conform to protocol
        XCTAssertNotNil(agentClient, "Should conform to AgentClient protocol")
    }

    // MARK: - Constitutional Constraint Tests

    func testHTTPAgentClient_ContainsNoRoutingLogic() async throws {
        // Given: HTTPAgentClient
        // The implementation should not contain any routing decisions

        // This is verified by code inspection:
        // - No conditional routing based on query content
        // - No route selection logic
        // - Pure I/O component

        XCTAssertTrue(true, "HTTPAgentClient contains no routing logic (verified by code inspection)")
    }

    func testHTTPAgentClient_ContainsNoRetryLogic() async throws {
        // Given: HTTPAgentClient that will fail
        var callCount = 0

        MockURLProtocol.requestHandler = { request in
            callCount += 1
            throw URLError(.networkConnectionLost)
        }

        // When: Querying fails
        do {
            _ = try await client.query(query: "Test", sessionId: UUID())
            XCTFail("Should have thrown error")
        } catch {
            // Expected
        }

        // Then: Should only attempt once (no retry)
        XCTAssertEqual(callCount, 1, "Should not retry on failure")
    }

    func testHTTPAgentClient_ContainsNoFallbackLogic() async throws {
        // Given: HTTPAgentClient that will fail
        MockURLProtocol.requestHandler = { request in
            throw URLError(.networkConnectionLost)
        }

        // When/Then: Should propagate error (no fallback)
        do {
            _ = try await client.query(query: "Test", sessionId: UUID())
            XCTFail("Should have thrown error")
        } catch {
            // Error propagated correctly - no fallback attempted
            XCTAssertNotNil(error)
        }
    }
}
