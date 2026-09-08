import Foundation

/// A club or team as its QR code identifies it.
///
/// Deliberately thin: a scanned code tells you who you are playing and nothing
/// else — no roster, no fixtures, no contact details.
struct ClubIdentity: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let qrToken: String
    /// `club` or `team`.
    let kind: String
    let clubId: UUID
    let clubName: String
    let sport: String?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, sport
        case qrToken = "qr_token"
        case clubId = "club_id"
        case clubName = "club_name"
    }

    var isTeam: Bool { kind == "team" }

    /// "Hemel Hempstead CC — 2nd XI" when it is a team, just the club otherwise.
    var displayName: String {
        isTeam && clubName != name ? "\(clubName) — \(name)" : name
    }
}

/// A club's own code, with the string that goes into the image.
struct ClubQRCode: Codable, Equatable {
    let identity: ClubIdentity
    let payload: String

    enum CodingKeys: String, CodingKey {
        case payload
    }

    init(from decoder: Decoder) throws {
        identity = try ClubIdentity(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        payload = try c.decode(String.self, forKey: .payload)
    }
}

/// An umpire or scorer appointed to a match. Either may control the scoring.
struct MatchOfficialRow: Codable, Identifiable, Equatable {
    let userId: UUID
    let name: String
    /// `umpire` or `scorer`.
    let role: String

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case name, role
        case userId = "user_id"
    }

    var isUmpire: Bool { role == "umpire" }

    var label: String { isUmpire ? "Umpire" : "Scorer" }
}

/// One change of hands in the scoring book.
struct ScorerHandover: Codable, Identifiable, Equatable {
    let fromName: String?
    let toName: String
    /// `handover` · `override` · `claim`
    let reason: String
    let actedByName: String
    let createdAt: Date

    var id: String { "\(createdAt.timeIntervalSince1970)-\(toName)" }

    enum CodingKeys: String, CodingKey {
        case reason
        case fromName = "from_name"
        case toName = "to_name"
        case actedByName = "acted_by_name"
        case createdAt = "created_at"
    }

    /// "Ravi handed the book to Sam", or the blunter version.
    var summary: String {
        switch reason {
        case "override":
            return "\(actedByName) took the book" + (fromName.map { " from \($0)" } ?? "")
        case "claim":
            return "\(toName) picked up the book"
        default:
            return "\(fromName ?? "Someone") handed the book to \(toName)"
        }
    }

    var isOverride: Bool { reason == "override" }
}

/// What the API's commentary endpoint replies with.
///
/// `line` is optional on purpose: no model configured, or one that contradicted
/// the ball and was thrown away, both come back as nothing — and the caller
/// keeps the line the app already wrote from the log.
struct BallCommentary: Codable, Equatable {
    let line: String?
    let model: String?
}

/// One name a captain may put on the sheet, and where they stand for this
/// fixture: picked, a reserve, available, or just a club member.
struct SquadPlayer: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let standing: String
    let batsLeft: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, standing
        case batsLeft = "bats_left"
    }

    var standingLabel: String {
        switch standing {
        case "selected": return "picked"
        case "reserve": return "reserve"
        case "available": return "available"
        case "unavailable": return "said no"
        default: return "member"
        }
    }
}

struct SideSquad: Codable, Equatable {
    let side: String
    let teamName: String
    /// Null when this side is not a club in Fishers — the scorer names them.
    let clubId: UUID?
    let canPick: Bool
    let submitted: Bool
    let players: [SquadPlayer]

    enum CodingKeys: String, CodingKey {
        case side
        case teamName = "team_name"
        case clubId = "club_id"
        case canPick = "can_pick"
        case submitted, players
    }
}

struct MatchSquads: Codable, Equatable {
    let home: SideSquad
    let away: SideSquad
}
