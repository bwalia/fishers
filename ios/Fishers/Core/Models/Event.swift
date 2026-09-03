import Foundation

enum EventSubtype: String, Codable, CaseIterable {
    case nets
    case friendly
    case leagueMatch = "league_match"
    case social
    case generic

    var label: String {
        switch self {
        case .nets: return "Nets"
        case .friendly: return "Friendly"
        case .leagueMatch: return "League Match"
        case .social: return "Social"
        case .generic: return "Session"
        }
    }

    var isGame: Bool { self == .friendly || self == .leagueMatch }

    var systemImage: String {
        switch self {
        case .nets: return "figure.cricket"
        case .friendly, .leagueMatch: return "trophy"
        case .social: return "cup.and.saucer"
        case .generic: return "calendar"
        }
    }
}

enum EventStatus: String, Codable {
    case scheduled
    case cancelled
    case completed
}

struct Event: Codable, Identifiable, Hashable {
    var id: UUID
    var clubId: UUID
    var teamId: UUID?
    var sport: String
    var eventSubtype: EventSubtype
    var title: String
    var venueId: UUID?
    var venue: Venue?
    var startAt: Date
    var endAt: Date
    var recurrenceRule: String?
    var capacity: Int?
    var feeAmount: Int?
    var currency: String?
    var status: EventStatus
    // Cricket nets extras
    var laneCount: Int?
    var maxPerLane: Int?
    var bowlingMachine: Bool?
    // Cricket game extras
    var format: String?
    var opposition: String?
    var homeOrAway: String?

    var dayKey: String { DayFormatter.string(from: startAt) }
    var hasFee: Bool { (feeAmount ?? 0) > 0 }
    var isCricket: Bool { sport.lowercased() == "cricket" }
}

struct MatchResult: Codable, Hashable {
    var eventId: UUID
    var format: String?
    var opposition: String?
    var homeOrAway: String?
    var scorecardJson: String?
    var createdAt: Date?
}

enum RSVPStatus: String, Codable, CaseIterable {
    case going
    case maybe
    case notGoing = "not_going"

    var label: String {
        switch self {
        case .going: return "Going"
        case .maybe: return "Maybe"
        case .notGoing: return "Not going"
        }
    }

    var systemImage: String {
        switch self {
        case .going: return "checkmark.circle.fill"
        case .maybe: return "questionmark.circle.fill"
        case .notGoing: return "xmark.circle.fill"
        }
    }
}

struct Attendee: Codable, Identifiable, Hashable {
    var user: User
    var status: RSVPStatus
    var hasPaid: Bool

    var id: UUID { user.id }
}

enum InviteStatus: String, Codable {
    case pending
    case going
    case maybe
    case notGoing = "not_going"
}

struct EventInvite: Codable, Identifiable, Hashable {
    var id: UUID
    var eventId: UUID
    var userId: UUID
    var invitedBy: UUID
    var status: InviteStatus
    var respondedAt: Date?
    var event: Event?
    var inviter: User?
}
