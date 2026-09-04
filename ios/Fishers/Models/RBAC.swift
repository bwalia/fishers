import Foundation

/// Club / team role — matches backend `user_role` / RBAC matrix.
enum ClubRole: String, Codable {
    case superAdmin = "super_admin"
    case clubAdmin = "club_admin" // Club secretary
    case teamCaptain = "team_captain"
    case member
    case guest

    var displayName: String {
        switch self {
        case .superAdmin: return "Super admin"
        case .clubAdmin: return "Club secretary"
        case .teamCaptain: return "Team captain"
        case .member: return "Member"
        case .guest: return "Guest"
        }
    }

    var isSecretary: Bool { self == .clubAdmin || self == .superAdmin }
    var isCaptain: Bool { self == .teamCaptain || isSecretary }
    var canInviteToPlay: Bool { isCaptain }
    var canManageMembers: Bool { isSecretary }
    var canManageSelection: Bool { isCaptain }
}

struct ClubRoleInfo: Codable {
    let role: ClubRole
    let displayName: String
    let isSecretary: Bool
    let isCaptain: Bool
    let canInviteToPlay: Bool
    let permissions: [String]

    enum CodingKeys: String, CodingKey {
        case role, permissions
        case displayName = "display_name"
        case isSecretary = "is_secretary"
        case isCaptain = "is_captain"
        case canInviteToPlay = "can_invite_to_play"
    }
}
