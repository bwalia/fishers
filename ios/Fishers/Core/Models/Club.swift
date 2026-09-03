import Foundation

enum ClubVisibility: String, Codable, CaseIterable {
    case publicClub = "public"
    case inviteOnly = "invite_only"

    var label: String {
        switch self {
        case .publicClub: return "Public"
        case .inviteOnly: return "Invite only"
        }
    }
}

struct Club: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var sportTypes: [String]
    var visibility: ClubVisibility
    var ownerId: UUID
    var createdAt: Date?
}

enum MemberRole: String, Codable, CaseIterable {
    case admin
    case captain
    case member
    case guest

    var label: String { rawValue.capitalized }
}

struct ClubMember: Codable, Identifiable, Hashable {
    var clubId: UUID
    var userId: UUID
    var role: MemberRole
    var status: String
    var joinedAt: Date?
    var user: User?

    var id: UUID { userId }
}

struct Team: Codable, Identifiable, Hashable {
    var id: UUID
    var clubId: UUID
    var sport: String
    var name: String
    /// League grade the side plays in, e.g. `division3`. Nil for social sides.
    var division: String?
    /// Age band the side selects from, e.g. `senior` or `u15`.
    var ageGroup: String?

    var divisionGrade: Division? { Division(stored: division) }
    var ageBand: AgeGroup? { AgeGroup(stored: ageGroup) }
}

struct Venue: Codable, Identifiable, Hashable {
    var id: UUID
    var clubId: UUID
    var name: String
    var address: String?
    var lat: Double?
    var lng: Double?
}
