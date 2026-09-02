import Foundation

// Codable mirrors of the schemas in nesteferge/openapi.yaml.
// Every field the spec marks `nullable: true` is modelled as an Optional; fields
// the spec marks required-and-non-null stay non-optional so decoding fails loudly
// if the API contract drifts.

// MARK: - Errors

struct ErrorResponse: Codable, Sendable {
    let detail: String
}

// MARK: - Health

struct HealthResponse: Codable, Sendable {
    let status: String
    let terminals: Int
    let routes: Int
}

// MARK: - Terminals

struct Terminal: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let lat: Double
    let lng: Double
    let confidence: Double?
}

struct TerminalsResponse: Codable, Sendable {
    let terminals: [Terminal]
}

// MARK: - Routes

struct Route: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let county: String?
    let name: String
    let slug: String
    let fromStop: String?
    let toStop: String?
    let fromLat: Double?
    let fromLng: Double?
    let toLat: Double?
    let toLng: Double?

    enum CodingKeys: String, CodingKey {
        case id, county, name, slug
        case fromStop = "from_stop"
        case toStop = "to_stop"
        case fromLat = "from_lat"
        case fromLng = "from_lng"
        case toLat = "to_lat"
        case toLng = "to_lng"
    }
}

struct RoutesResponse: Codable, Sendable {
    let routes: [Route]
}

// MARK: - Search

struct RouteSearchResult: Codable, Sendable, Hashable {
    let routeID: Int
    let routeName: String
    let county: String?
    let slug: String
    let origin: String
    let destination: String

    enum CodingKeys: String, CodingKey {
        case routeID = "route_id"
        case routeName = "route_name"
        case county, slug, origin, destination
    }
}

struct RouteSearchQuery: Codable, Sendable {
    let q: String
    let limit: Int
}

struct RouteSearchResponse: Codable, Sendable {
    let query: RouteSearchQuery
    let results: [RouteSearchResult]
}

// MARK: - Guess

struct GuessCandidate: Codable, Sendable, Hashable {
    let routeID: Int
    let routeName: String
    let county: String?
    let origin: String
    let destination: String?
    let originLat: Double
    let originLng: Double
    let distanceKm: Double
    let bearingToOrigin: Double?
    let headingOffsetDeg: Double?
    let score: Double

    enum CodingKeys: String, CodingKey {
        case routeID = "route_id"
        case routeName = "route_name"
        case county, origin, destination, score
        case originLat = "origin_lat"
        case originLng = "origin_lng"
        case distanceKm = "distance_km"
        case bearingToOrigin = "bearing_to_origin"
        case headingOffsetDeg = "heading_offset_deg"
    }
}

struct GuessQuery: Codable, Sendable {
    let lat: Double
    let lng: Double
    let heading: Double?
    let radiusKm: Double

    enum CodingKeys: String, CodingKey {
        case lat, lng, heading
        case radiusKm = "radius_km"
    }
}

struct GuessResponse: Codable, Sendable {
    let query: GuessQuery
    let candidates: [GuessCandidate]
}

// MARK: - Schedule

struct RouteSummary: Codable, Sendable, Hashable {
    let id: Int
    let name: String
    let fromStop: String?
    let toStop: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case fromStop = "from_stop"
        case toStop = "to_stop"
    }
}

struct UpcomingDeparture: Codable, Sendable, Hashable, Identifiable {
    let departTime: String
    let arriveTime: String?
    let direction: String?
    let dayType: String?
    let remarks: String?
    let departAt: Date
    let secondsUntil: Int

    // `depart_at` is unique per direction/day, so it doubles as a stable list id.
    var id: Date { departAt }

    enum CodingKeys: String, CodingKey {
        case departTime = "depart_time"
        case arriveTime = "arrive_time"
        case direction
        case dayType = "day_type"
        case remarks
        case departAt = "depart_at"
        case secondsUntil = "seconds_until"
    }
}

struct RouteNextResponse: Codable, Sendable {
    let route: RouteSummary
    let origin: String
    let departures: [UpcomingDeparture]
}

// MARK: - Selection

/// A route + origin pair: everything needed to call `/api/routes/{id}/next`.
struct FerrySelection: Codable, Sendable, Hashable {
    let routeID: Int
    let routeName: String
    let origin: String
    let destination: String?

    var legDescription: String {
        guard let destination, !destination.isEmpty else { return origin }
        return "\(origin) → \(destination)"
    }
}

extension GuessCandidate {
    var selection: FerrySelection {
        FerrySelection(routeID: routeID, routeName: routeName, origin: origin, destination: destination)
    }
}

extension RouteSearchResult {
    var selection: FerrySelection {
        FerrySelection(routeID: routeID, routeName: routeName, origin: origin, destination: destination)
    }
}
