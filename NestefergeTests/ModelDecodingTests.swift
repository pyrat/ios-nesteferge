import Foundation
import Testing

@testable import Nesteferge

/// Fixtures copied verbatim from nesteferge/API.md so the tests fail if the
/// documented contract and the Swift models drift apart.
@Suite("Model decoding")
struct ModelDecodingTests {

    /// Same configuration as `APIClient`, so date handling is covered too.
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = plain.date(from: raw) ?? withFraction.date(from: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: raw)
            }
            return date
        }
        return decoder
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try makeDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("Health response")
    func health() throws {
        let response = try decode(HealthResponse.self, from: """
        { "status": "ok", "terminals": 205, "routes": 157 }
        """)
        #expect(response.status == "ok")
        #expect(response.terminals == 205)
        #expect(response.routes == 157)
    }

    @Test("Terminals response")
    func terminals() throws {
        let response = try decode(TerminalsResponse.self, from: """
        {
          "terminals": [
            { "id": 13, "name": "Festøya", "lat": 62.37522, "lng": 6.33131, "confidence": 0.9 }
          ]
        }
        """)
        #expect(response.terminals.count == 1)
        #expect(response.terminals[0].name == "Festøya")
        #expect(response.terminals[0].confidence == 0.9)
    }

    @Test("Terminal tolerates a null confidence")
    func terminalNullConfidence() throws {
        let response = try decode(TerminalsResponse.self, from: """
        { "terminals": [ { "id": 1, "name": "X", "lat": 1, "lng": 2, "confidence": null } ] }
        """)
        #expect(response.terminals[0].confidence == nil)
    }

    @Test("Routes response maps snake_case keys")
    func routes() throws {
        let response = try decode(RoutesResponse.self, from: """
        {
          "routes": [
            {
              "id": 154, "county": "Møre og Romsdal", "name": "Festøya–Solavågen",
              "slug": "ferje-1069-festoeya-solavaagen",
              "from_stop": "Festøya", "to_stop": "Solavågen",
              "from_lat": 62.37522, "from_lng": 6.33131,
              "to_lat": 62.41373, "to_lng": 6.32754
            }
          ]
        }
        """)
        let route = try #require(response.routes.first)
        #expect(route.id == 154)
        #expect(route.fromStop == "Festøya")
        #expect(route.toLng == 6.32754)
    }

    @Test("Search response")
    func search() throws {
        let response = try decode(RouteSearchResponse.self, from: """
        {
          "query": { "q": "solav", "limit": 12 },
          "results": [
            {
              "route_id": 154, "route_name": "Festøya–Solavågen",
              "county": "Møre og Romsdal", "slug": "ferje-1069-festoeya-solavaagen",
              "origin": "Solavågen", "destination": "Festøya"
            }
          ]
        }
        """)
        #expect(response.query.limit == 12)
        #expect(response.results.first?.routeID == 154)
        #expect(response.results.first?.origin == "Solavågen")
    }

    @Test("Guess response with null heading fields")
    func guess() throws {
        let response = try decode(GuessResponse.self, from: """
        {
          "query": { "lat": 62.39, "lng": 6.33, "heading": null, "radius_km": 50 },
          "candidates": [
            {
              "route_id": 154, "route_name": "Festøya–Solavågen", "county": "Møre og Romsdal",
              "origin": "Festøya", "destination": "Solavågen",
              "origin_lat": 62.37522, "origin_lng": 6.33131,
              "distance_km": 1.645, "bearing_to_origin": null,
              "heading_offset_deg": null, "score": 0.8719
            }
          ]
        }
        """)
        #expect(response.query.heading == nil)
        #expect(response.query.radiusKm == 50)
        let candidate = try #require(response.candidates.first)
        #expect(candidate.distanceKm == 1.645)
        #expect(candidate.headingOffsetDeg == nil)
        #expect(candidate.selection.routeID == 154)
        #expect(candidate.selection.legDescription == "Festøya → Solavågen")
    }

    @Test("Next departures parses the Oslo offset timestamp")
    func nextDepartures() throws {
        let response = try decode(RouteNextResponse.self, from: """
        {
          "route": { "id": 154, "name": "Festøya–Solavågen", "from_stop": "Festøya", "to_stop": "Solavågen" },
          "origin": "Festøya",
          "departures": [
            {
              "direction": "Festøya->Solavågen", "depart_time": "15:40", "arrive_time": "15:55",
              "day_type": "daily", "remarks": null,
              "depart_at": "2026-09-01T15:40:00+02:00", "seconds_until": 1120
            }
          ]
        }
        """)
        let departure = try #require(response.departures.first)
        #expect(departure.departTime == "15:40")
        #expect(departure.secondsUntil == 1120)
        // 15:40 +02:00 == 13:40 UTC
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 1
        components.hour = 13; components.minute = 40
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(departure.departAt == calendar.date(from: components))
    }

    @Test("Fractional seconds are also accepted")
    func fractionalSeconds() throws {
        let response = try decode(RouteNextResponse.self, from: """
        {
          "route": { "id": 1, "name": "R", "from_stop": null, "to_stop": null },
          "origin": "A",
          "departures": [
            {
              "direction": null, "depart_time": "08:00", "arrive_time": null,
              "day_type": null, "remarks": null,
              "depart_at": "2026-09-01T08:00:00.500+02:00", "seconds_until": 60
            }
          ]
        }
        """)
        #expect(response.departures.count == 1)
    }

    @Test("Error payload")
    func errorPayload() throws {
        let response = try decode(ErrorResponse.self, from: #"{ "detail": "route not found" }"#)
        #expect(response.detail == "route not found")
    }
}
