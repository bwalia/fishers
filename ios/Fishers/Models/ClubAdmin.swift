import Foundation

/// A member as the roster screen needs them: who, what role, how to reach them.
struct ClubMemberDetail: Codable, Identifiable, Equatable {
    let userId: UUID
    var name: String
    /// One of these is absent: people register with an address or a number.
    var email: String?
    var phone: String?
    var role: ClubRole
    var status: String
    var joinedAt: Date
    var positionRole: String?
    var skillLevel: String?

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case name, email, phone, role, status
        case userId = "user_id"
        case joinedAt = "joined_at"
        case positionRole = "position_role"
        case skillLevel = "skill_level"
    }

    var isActive: Bool { status == "active" }

    /// Whichever way this member can actually be reached.
    var contact: String { email ?? phone ?? "No contact details" }

    /// "Batter · Club standard" under the name.
    var subtitle: String {
        [positionRole, skillLevel].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A link that puts whoever follows it into the club, once they have an
/// account. Single use — the API refuses a second accept.
struct ClubInvite: Codable, Identifiable, Equatable {
    let id: UUID
    let targetType: String
    let targetId: UUID
    let token: String
    var status: String
    var invitedEmail: String?

    enum CodingKeys: String, CodingKey {
        case id, token, status
        case targetType = "target_type"
        case targetId = "target_id"
        case invitedEmail = "invited_email"
    }

    /// The web app resolves this; it is what a secretary actually sends.
    func url(webBase: String) -> URL? {
        URL(string: "\(webBase)/invite/\(token)")
    }
}

/// Something that happened which you need to know about.
struct AppNotification: Codable, Identifiable, Equatable {
    let id: UUID
    let type: String
    let payload: [String: String]
    let sentAt: Date
    let readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, type, payload
        case sentAt = "sent_at"
        case readAt = "read_at"
    }

    var isUnread: Bool { readAt == nil }

    /// One line of plain English. A player is not going to read
    /// `match_terms_proposed`.
    var line: String {
        switch type {
        case "match_terms_proposed":
            let sides = [payload["home_name"], payload["away_name"]]
                .compactMap { $0 }.joined(separator: " v ")
            return sides.isEmpty
                ? "The other captain has proposed the terms. Open the match to agree."
                : "\(sides) — the other captain has proposed the terms. Tap to agree."
        case "match_terms_agreed":
            return "Both captains have agreed the terms. You can do the toss."
        case "match_pick_your_xi":
            let sides = [payload["home_name"], payload["away_name"]]
                .compactMap { $0 }.joined(separator: " v ")
            return sides.isEmpty
                ? "The toss is done. Pick your side."
                : "\(sides) — the toss is done. Pick your side."
        case "invite":
            return "You have a new invite."
        default:
            return type.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// The match this is about, when it is about one.
    var matchId: UUID? { payload["match_id"].flatMap(UUID.init(uuidString:)) }
}

/// A page of anything the API pages.
struct APIPage<T: Codable>: Codable {
    let items: [T]
    let total: Int
    let page: Int
    let perPage: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items, total, page
        case perPage = "per_page"
        case hasMore = "has_more"
    }
}

struct NotificationFeed: Codable, Equatable {
    let unread: Int
    let items: [AppNotification]
}

/// The knobs a club secretary can turn.
struct ClubSettings: Codable, Equatable {
    /// `off` | `suggest` | `auto_publish`
    var selectionAutonomy: String
    var confirmLeadHours: Int
    var dropLeadHours: Int
    var feeChaseAfterHours: Int
    var feeChaseMaxReminders: Int

    enum CodingKeys: String, CodingKey {
        case selectionAutonomy = "selection_autonomy"
        case confirmLeadHours = "confirm_lead_hours"
        case dropLeadHours = "drop_lead_hours"
        case feeChaseAfterHours = "fee_chase_after_hours"
        case feeChaseMaxReminders = "fee_chase_max_reminders"
    }
}

enum SelectionAutonomy: String, CaseIterable, Identifiable {
    case off, suggest, autoPublish = "auto_publish"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .suggest: return "Suggests"
        case .autoPublish: return "Publishes"
        }
    }

    var blurb: String {
        switch self {
        case .off:
            return "The assistant does not pick sides. Captains use the ranking instead."
        case .suggest:
            return "The assistant proposes a side; a captain publishes it."
        case .autoPublish:
            return "The assistant names and announces the side on its own."
        }
    }
}
