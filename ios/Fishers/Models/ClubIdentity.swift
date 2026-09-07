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
