import Foundation

/// Errors surfaced by `APIClient`, already reduced to something presentable.
enum APIError: LocalizedError, Equatable {
    case badURL
    case notFound(String)
    case validation(String)
    case http(Int, String?)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return String(localized: "error.badURL", defaultValue: "The API address is not valid.")
        case let .notFound(detail), let .validation(detail):
            return detail
        case let .http(status, detail):
            if let detail, !detail.isEmpty { return detail }
            return String(
                format: String(localized: "error.requestFailed", defaultValue: "Request failed (%d)"),
                status
            )
        case let .decoding(message):
            return String(
                format: String(localized: "error.badResponse", defaultValue: "Unexpected response from the server. (%@)"),
                message
            )
        case let .transport(message):
            return message
        }
    }
}

/// Query parameter value; keeps call sites free of manual string conversion.
enum QueryValue {
    case string(String)
    case int(Int)
    case double(Double, decimals: Int)

    var encoded: String {
        switch self {
        case let .string(value): return value
        case let .int(value): return String(value)
        case let .double(value, decimals): return String(format: "%.\(decimals)f", value)
        }
    }
}

/// Parses the RFC3339 timestamps the API emits, e.g. `2026-09-01T15:40:00+02:00`.
///
/// Some deployments include fractional seconds, so both shapes are tried.
/// `ISO8601DateFormatter` is documented as thread-safe for parsing, and these two
/// instances are never mutated after init, hence the `@unchecked Sendable`.
private struct ISO8601DateParser: @unchecked Sendable {
    private let plain: ISO8601DateFormatter
    private let withFractionalSeconds: ISO8601DateFormatter

    init() {
        plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func date(from string: String) -> Date? {
        plain.date(from: string) ?? withFractionalSeconds.date(from: string)
    }
}

/// Thin async wrapper over the read-only Nesteferge HTTP API.
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session

        let decoder = JSONDecoder()
        let parser = ISO8601DateParser()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parser.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported date format: \(raw)"
                )
            }
            return date
        }
        self.decoder = decoder
    }

    // MARK: - Endpoints

    func health(baseURL: URL) async throws -> HealthResponse {
        try await get(baseURL: baseURL, path: "/api/health")
    }

    func terminals(baseURL: URL) async throws -> TerminalsResponse {
        try await get(baseURL: baseURL, path: "/api/terminals")
    }

    func routes(baseURL: URL) async throws -> RoutesResponse {
        try await get(baseURL: baseURL, path: "/api/routes")
    }

    func searchRoutes(baseURL: URL, query: String, limit: Int = 12) async throws -> RouteSearchResponse {
        try await get(
            baseURL: baseURL,
            path: "/api/routes/search",
            query: ["q": .string(query), "limit": .int(limit)]
        )
    }

    func guess(
        baseURL: URL,
        lat: Double,
        lng: Double,
        heading: Double?,
        radiusKm: Double = 600
    ) async throws -> GuessResponse {
        var params: [String: QueryValue] = [
            "lat": .double(lat, decimals: 6),
            "lng": .double(lng, decimals: 6),
            "radius": .double(radiusKm, decimals: 1),
        ]
        if let heading {
            params["heading"] = .double(heading, decimals: 1)
        }
        return try await get(baseURL: baseURL, path: "/api/guess", query: params)
    }

    func nextDepartures(
        baseURL: URL,
        routeID: Int,
        origin: String,
        count: Int = 4
    ) async throws -> RouteNextResponse {
        try await get(
            baseURL: baseURL,
            path: "/api/routes/\(routeID)/next",
            query: ["origin": .string(origin), "count": .int(count)]
        )
    }

    // MARK: - Transport

    private func get<T: Decodable>(
        baseURL: URL,
        path: String,
        query: [String: QueryValue] = [:]
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        components.path = components.path.hasSuffix("/")
            ? String(components.path.dropLast()) + path
            : components.path + path
        if !query.isEmpty {
            // Sorted so requests are deterministic and cache/test friendly.
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value.encoded) }
        }
        guard let url = components.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(String(localized: "error.noResponse", defaultValue: "No response from the server."))
        }

        guard (200..<300).contains(http.statusCode) else {
            let detail = try? decoder.decode(ErrorResponse.self, from: data).detail
            switch http.statusCode {
            case 404:
                throw APIError.notFound(detail ?? String(localized: "error.notFound", defaultValue: "Not found."))
            case 422:
                throw APIError.validation(detail ?? String(localized: "error.invalidRequest", defaultValue: "Invalid request."))
            default:
                throw APIError.http(http.statusCode, detail)
            }
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }
}
