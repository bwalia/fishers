import Foundation

struct PublicUser: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var email: String
    var phone: String?
    var avatarUrl: String?
    var sportsPlayed: [String]
    var positionRole: String?
    var skillLevel: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone
        case avatarUrl = "avatar_url"
        case sportsPlayed = "sports_played"
        case positionRole = "position_role"
        case skillLevel = "skill_level"
    }
}

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let user: PublicUser

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct Club: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var sportTypes: [String]
    var visibility: String
    var ownerId: UUID
    var description: String?
    var isInformalGroup: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, visibility, description
        case sportTypes = "sport_types"
        case ownerId = "owner_id"
        case isInformalGroup = "is_informal_group"
    }
}

struct Team: Codable, Identifiable, Hashable {
    let id: UUID
    let clubId: UUID
    let sport: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case id, sport, name
        case clubId = "club_id"
    }
}

struct Venue: Codable, Identifiable {
    let id: UUID
    let clubId: UUID
    var name: String
    var address: String?
    var lat: Double?
    var lng: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, address, lat, lng
        case clubId = "club_id"
    }
}

enum EventSubtype: String, Codable, CaseIterable {
    case nets, friendly, leagueMatch = "league_match"
    case tournament, social, training, generic
}

struct Event: Codable, Identifiable, Hashable {
    let id: UUID
    let clubId: UUID
    var teamId: UUID?
    var sport: String
    var eventSubtype: String
    var title: String
    var venueId: UUID?
    var startAt: Date
    var endAt: Date
    var capacity: Int?
    var feeAmountCents: Int?
    var feeCurrency: String
    var status: String
    var metadata: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case id, sport, title, capacity, status, metadata
        case clubId = "club_id"
        case teamId = "team_id"
        case eventSubtype = "event_subtype"
        case venueId = "venue_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case feeAmountCents = "fee_amount_cents"
        case feeCurrency = "fee_currency"
    }
}

enum AvailabilityStatus: String, Codable, CaseIterable {
    case available, unavailable, maybe

    var colorName: String {
        switch self {
        case .available: return "available"
        case .unavailable: return "unavailable"
        case .maybe: return "maybe"
        }
    }

    var label: String {
        switch self {
        case .available: return "Available"
        case .unavailable: return "Unavailable"
        case .maybe: return "Maybe"
        }
    }

    func next() -> AvailabilityStatus {
        switch self {
        case .available: return .maybe
        case .maybe: return .unavailable
        case .unavailable: return .available
        }
    }
}

struct Availability: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let date: String
    var status: AvailabilityStatus
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id, date, status, note
        case userId = "user_id"
    }
}

enum RsvpStatus: String, Codable {
    case going, notGoing = "not_going", maybe, invited
}

struct AttendeeSummary: Codable, Identifiable {
    var id: UUID { userId }
    let userId: UUID
    let name: String
    let status: RsvpStatus
    let availability: AvailabilityStatus?
    let paid: Bool

    enum CodingKeys: String, CodingKey {
        case name, status, availability, paid
        case userId = "user_id"
    }
}

struct Product: Codable, Identifiable, Hashable {
    let id: UUID
    let clubId: UUID
    var name: String
    var description: String?
    var priceCents: Int
    var currency: String
    var category: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, currency, category
        case clubId = "club_id"
        case priceCents = "price_cents"
    }

    var priceLabel: String {
        let amount = Double(priceCents) / 100.0
        return String(format: "£%.2f", amount)
    }
}

struct Order: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let clubId: UUID
    var eventId: UUID?
    var status: String
    var totalAmountCents: Int
    var currency: String

    enum CodingKeys: String, CodingKey {
        case id, status, currency
        case userId = "user_id"
        case clubId = "club_id"
        case eventId = "event_id"
        case totalAmountCents = "total_amount_cents"
    }
}

/// Lightweight JSON value for event metadata.
enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
