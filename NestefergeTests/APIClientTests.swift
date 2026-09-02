import Foundation
import Testing

@testable import Nesteferge

/// Intercepts requests so the API contract can be exercised without a server.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _lastRequest: URLRequest?

    static var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return _lastRequest
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        handler = nil
        _lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._lastRequest = request
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("API client", .serialized)
struct APIClientTests {

    private let baseURL = URL(string: "http://localhost:8000")!

    private func makeClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(session: URLSession(configuration: configuration))
    }

    private func respond(status: Int = 200, json: String) {
        StubURLProtocol.handler = { _ in (status, Data(json.utf8)) }
    }

    // MARK: - Request construction

    @Test("Guess request encodes coordinates, heading and radius")
    func guessQuery() async throws {
        defer { StubURLProtocol.reset() }
        respond(json: #"{ "query": { "lat": 1, "lng": 2, "heading": null, "radius_km": 600 }, "candidates": [] }"#)

        _ = try await makeClient().guess(baseURL: baseURL, lat: 62.375221, lng: 6.331314, heading: 91.28)

        let url = try #require(StubURLProtocol.lastRequest?.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query)
        #expect(url.path == "/api/guess")
        #expect(query.contains("lat=62.375221"))
        #expect(query.contains("lng=6.331314"))
        #expect(query.contains("heading=91.3"))
        #expect(query.contains("radius=600.0"))
    }

    @Test("Heading is omitted entirely when unavailable")
    func guessWithoutHeading() async throws {
        defer { StubURLProtocol.reset() }
        respond(json: #"{ "query": { "lat": 1, "lng": 2, "heading": null, "radius_km": 600 }, "candidates": [] }"#)

        _ = try await makeClient().guess(baseURL: baseURL, lat: 1, lng: 2, heading: nil)

        let query = URLComponents(url: StubURLProtocol.lastRequest!.url!, resolvingAgainstBaseURL: false)?.query ?? ""
        #expect(!query.contains("heading"))
    }

    @Test("Next-departures request puts the route id in the path and origin in the query")
    func nextDeparturesPath() async throws {
        defer { StubURLProtocol.reset() }
        respond(json: """
        { "route": { "id": 154, "name": "R", "from_stop": null, "to_stop": null },
          "origin": "Festøya", "departures": [] }
        """)

        _ = try await makeClient().nextDepartures(baseURL: baseURL, routeID: 154, origin: "Festøya", count: 4)

        let url = try #require(StubURLProtocol.lastRequest?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/api/routes/154/next")
        #expect(components.queryItems?.contains(URLQueryItem(name: "origin", value: "Festøya")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "count", value: "4")) == true)
    }

    @Test("A base URL with a trailing slash does not produce a double slash")
    func trailingSlashBaseURL() async throws {
        defer { StubURLProtocol.reset() }
        respond(json: #"{ "status": "ok", "terminals": 1, "routes": 1 }"#)

        _ = try await makeClient().health(baseURL: URL(string: "http://localhost:8000/")!)

        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/health")
    }

    // MARK: - Error mapping

    @Test("404 surfaces the server's detail message")
    func notFound() async {
        defer { StubURLProtocol.reset() }
        respond(status: 404, json: #"{ "detail": "route not found" }"#)

        await #expect(throws: APIError.notFound("route not found")) {
            try await makeClient().nextDepartures(baseURL: baseURL, routeID: 9999, origin: "X")
        }
    }

    @Test("422 surfaces the validation detail")
    func validation() async {
        defer { StubURLProtocol.reset() }
        respond(status: 422, json: #"{ "detail": "out of range: limit" }"#)

        await #expect(throws: APIError.validation("out of range: limit")) {
            try await makeClient().searchRoutes(baseURL: baseURL, query: "solav", limit: 99)
        }
    }

    @Test("Other statuses keep the status code")
    func serverError() async {
        defer { StubURLProtocol.reset() }
        respond(status: 500, json: #"{ "detail": "boom" }"#)

        await #expect(throws: APIError.http(500, "boom")) {
            try await makeClient().health(baseURL: baseURL)
        }
    }

    @Test("Malformed JSON is reported as a decoding failure, not a crash")
    func malformedBody() async {
        defer { StubURLProtocol.reset() }
        respond(json: "{ not json")

        await #expect(throws: (any Error).self) {
            try await makeClient().health(baseURL: baseURL)
        }
    }

    // MARK: - Happy path

    @Test("Search results decode end to end")
    func searchDecodes() async throws {
        defer { StubURLProtocol.reset() }
        respond(json: """
        { "query": { "q": "solav", "limit": 12 },
          "results": [ { "route_id": 154, "route_name": "Festøya–Solavågen", "county": null,
                         "slug": "s", "origin": "Solavågen", "destination": "Festøya" } ] }
        """)

        let response = try await makeClient().searchRoutes(baseURL: baseURL, query: "solav")
        #expect(response.results.count == 1)
        #expect(response.results[0].county == nil)
        #expect(response.results[0].selection.legDescription == "Solavågen → Festøya")
    }
}
