import Foundation

/// Club / team role — matches backend `user_role` / RBAC matrix.
enum ClubRole: String, Codable {
    case superAdmin = "super_admin"
    case clubAdmin = "club_admin" // Club secretary
    case teamCaptain = "team_captain"
    case teamViceCaptain = "team_vice_captain"
    case member
    case guest

    var displayName: String {
        switch self {
        case .superAdmin: return "Super admin"
        case .clubAdmin: return "Club secretary"
        case .teamCaptain: return "Team captain"
        case .teamViceCaptain: return "Vice captain"
        case .member: return "Member"
        case .guest: return "Guest"
        }
    }

    /// Short form for a badge.
    var shortLabel: String {
        switch self {
        case .superAdmin: return "ADMIN"
        case .clubAdmin: return "SEC"
        case .teamCaptain: return "CAPT"
        case .teamViceCaptain: return "VICE"
        case .member: return "MEMBER"
        case .guest: return "GUEST"
        }
    }

    /// What the role actually lets someone do, in the words the app uses.
    var responsibilities: String {
        switch self {
        case .superAdmin:
            return "Platform administration."
        case .clubAdmin:
            return "Everything: the roster, roles, teams, venues, fixtures, selection, fees and scoring."
        case .teamCaptain:
            return "Create fixtures, invite players, pick and publish the squad, score matches."
        case .teamViceCaptain:
            return "Help with selection, invite players to a fixture, score matches."
        case .member:
            return "Mark availability, RSVP, chat, the shop."
        case .guest:
            return "The same as a member, for a one-off invitee."
        }
    }

    /// The roles a secretary can hand out, strongest first.
    static let appointable: [ClubRole] = [
        .clubAdmin, .teamCaptain, .teamViceCaptain, .member, .guest,
    ]

    /// The order the roster groups people in.
    static let rosterOrder: [ClubRole] = [
        .superAdmin, .clubAdmin, .teamCaptain, .teamViceCaptain, .member, .guest,
    ]

    var isSecretary: Bool { self == .clubAdmin || self == .superAdmin }
    var isCaptain: Bool {
        self == .teamCaptain || self == .teamViceCaptain || isSecretary
    }
    var canInviteToPlay: Bool { isCaptain }
    var canScoreMatch: Bool { isCaptain }
    var canManageMembers: Bool { isSecretary }
    var canManageSelection: Bool { isCaptain }
}

struct ClubRoleInfo: Codable {
    let role: ClubRole
    let displayName: String
    let isSecretary: Bool
    let isCaptain: Bool
    let canInviteToPlay: Bool
    let canScoreMatch: Bool
    let permissions: [String]

    enum CodingKeys: String, CodingKey {
        case role, permissions
        case displayName = "display_name"
        case isSecretary = "is_secretary"
        case isCaptain = "is_captain"
        case canInviteToPlay = "can_invite_to_play"
        case canScoreMatch = "can_score_match"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(ClubRole.self, forKey: .role)
        displayName = try c.decode(String.self, forKey: .displayName)
        isSecretary = try c.decode(Bool.self, forKey: .isSecretary)
        isCaptain = try c.decode(Bool.self, forKey: .isCaptain)
        canInviteToPlay = try c.decode(Bool.self, forKey: .canInviteToPlay)
        permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        if let flagged = try c.decodeIfPresent(Bool.self, forKey: .canScoreMatch) {
            canScoreMatch = flagged
        } else {
            canScoreMatch = role.canScoreMatch || permissions.contains("score_match")
        }
    }
}
