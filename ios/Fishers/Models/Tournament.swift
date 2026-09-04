import Foundation

enum TournamentFormat: String, Codable, CaseIterable {
    case none
    case roundRobin = "round_robin"
    case groupsKnockout = "groups_knockout"
    case knockout
    case ladder

    var label: String {
        switch self {
        case .none: return "No structure"
        case .roundRobin: return "Round robin"
        case .groupsKnockout: return "Groups + knockout"
        case .knockout: return "Straight knockout"
        case .ladder: return "Ladder"
        }
    }
}

struct FixtureBlock: Codable, Identifiable, Hashable {
    let id: UUID
    let clubId: UUID
    let teamId: UUID?
    var name: String
    /// `block` | `tour` | `tournament` | `season`
    var kind: String
    var startsOn: String?
    var endsOn: String?

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case clubId = "club_id"
        case teamId = "team_id"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
    }

    var systemImage: String {
        switch kind {
        case "tournament": return "trophy.fill"
        case "tour": return "bus.fill"
        case "season": return "calendar"
        default: return "square.stack.3d.up.fill"
        }
    }
}

struct TournamentEntrant: Codable, Identifiable, Equatable {
    let id: UUID
    let blockId: UUID
    var name: String
    var seed: Int?
    var groupLabel: String?
    var contactName: String?
    var contactEmail: String?
    var withdrawn: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, seed, withdrawn
        case blockId = "block_id"
        case groupLabel = "group_label"
        case contactName = "contact_name"
        case contactEmail = "contact_email"
    }
}

/// One fixture in a running tournament, as the app lists it.
struct ScheduleRow: Codable, Identifiable, Equatable {
    let eventId: UUID
    let title: String
    let startsAt: Date
    let courtLabel: String?
    /// `group` | `knockout`
    let stage: String?
    let round: Int?
    let groupLabel: String?
    let homeName: String?
    let awayName: String?
    let homeScore: Int?
    let awayScore: Int?
    let homeResult: String?
    let status: String

    var id: UUID { eventId }

    enum CodingKeys: String, CodingKey {
        case title, stage, round, status
        case eventId = "event_id"
        case startsAt = "starts_at"
        case courtLabel = "court_label"
        case groupLabel = "group_label"
        case homeName = "home_name"
        case awayName = "away_name"
        case homeScore = "home_score"
        case awayScore = "away_score"
        case homeResult = "home_result"
    }

    var isPlayed: Bool { homeResult != nil }

    var scoreLine: String? {
        guard let homeScore, let awayScore else { return nil }
        return "\(homeScore) – \(awayScore)"
    }

    var fixtureLine: String {
        "\(homeName ?? "TBC") v \(awayName ?? "TBC")"
    }
}

struct Standing: Codable, Identifiable, Equatable {
    let entrantId: UUID
    let name: String
    let groupLabel: String?
    let played: Int
    let won: Int
    let lost: Int
    let drawn: Int
    let noResult: Int
    let points: Int
    let scored: Int
    let conceded: Int

    var id: UUID { entrantId }

    enum CodingKeys: String, CodingKey {
        case name, played, won, lost, drawn, points, scored, conceded
        case entrantId = "entrant_id"
        case groupLabel = "group_label"
        case noResult = "no_result"
    }

    var difference: Int { scored - conceded }
}

struct EventTicket: Codable, Identifiable, Equatable {
    let id: UUID
    let eventId: UUID
    let userId: UUID
    let name: String?
    var guests: Int
    var guestNames: String?
    var amountCents: Int
    var currency: String
    /// `reserved` | `paid` | `cancelled`
    var status: String
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, guests, currency, status, notes
        case eventId = "event_id"
        case userId = "user_id"
        case guestNames = "guest_names"
        case amountCents = "amount_cents"
    }

    var isPaid: Bool { status == "paid" }
    var places: Int { 1 + guests }
}

struct TicketSummary: Codable, Equatable {
    let eventId: UUID
    let title: String
    let ticketCapacity: Int?
    let ticketPriceCents: Int?
    let bookings: Int
    let headcount: Int
    let collectedCents: Int
    let outstandingCents: Int

    enum CodingKeys: String, CodingKey {
        case title, bookings, headcount
        case eventId = "event_id"
        case ticketCapacity = "ticket_capacity"
        case ticketPriceCents = "ticket_price_cents"
        case collectedCents = "collected_cents"
        case outstandingCents = "outstanding_cents"
    }

    var placesLeft: Int? {
        ticketCapacity.map { max(0, $0 - headcount) }
    }
}

struct TicketBooking: Codable, Equatable {
    let summary: TicketSummary
    let tickets: [EventTicket]
}
