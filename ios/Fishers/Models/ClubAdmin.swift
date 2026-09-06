import Foundation

/// A member as the roster screen needs them: who, what role, how to reach them.
struct ClubMemberDetail: Codable, Identifiable, Equatable {
    let userId: UUID
    var name: String
    var email: String
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

    /// "Batter · Club standard" under the name.
    var subtitle: String {
        [positionRole, skillLevel].compactMap { $0 }.joined(separator: " · ")
    }
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
