import Foundation

/// One row of `GET /me/clubs`: the club, what you are in it, and the numbers
/// the list shows.
struct ClubMembershipRow: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var sportTypes: [String]
    var visibility: String
    var ownerId: UUID
    var description: String?
    var isInformalGroup: Bool
    var role: ClubRole
    /// Captains the side — by role, or a secretary who captains too.
    var isCaptain: Bool
    var memberCount: Int
    var teamCount: Int
    /// The public page's address, only once the club has switched it on.
    var publicSlug: String?

    enum CodingKeys: String, CodingKey {
        case id, name, visibility, description, role
        case sportTypes = "sport_types"
        case ownerId = "owner_id"
        case isInformalGroup = "is_informal_group"
        case isCaptain = "is_captain"
        case memberCount = "member_count"
        case teamCount = "team_count"
        case publicSlug = "public_slug"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sportTypes = try c.decodeIfPresent([String].self, forKey: .sportTypes) ?? []
        visibility = try c.decodeIfPresent(String.self, forKey: .visibility) ?? "invite_only"
        ownerId = try c.decode(UUID.self, forKey: .ownerId)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        isInformalGroup = try c.decodeIfPresent(Bool.self, forKey: .isInformalGroup) ?? false
        role = try c.decode(ClubRole.self, forKey: .role)
        isCaptain = try c.decodeIfPresent(Bool.self, forKey: .isCaptain) ?? (role == .teamCaptain)
        memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        teamCount = try c.decodeIfPresent(Int.self, forKey: .teamCount) ?? 0
        publicSlug = try c.decodeIfPresent(String.self, forKey: .publicSlug)
    }

    /// The same club, as the screens that take a `Club` want it.
    var club: Club {
        Club(id: id, name: name, sportTypes: sportTypes, visibility: visibility, ownerId: ownerId,
             description: description, isInformalGroup: isInformalGroup, role: role)
    }

    var roleLabel: String { RoleChoice(role: role, isCaptain: isCaptain).label }
    var isPublic: Bool { visibility == "public" }
    var publicPageURL: URL? {
        publicSlug.map { AppConfig.webBaseURL.appending(path: "c/\($0)") }
    }
}

/// What the clubs list is filtered and sorted by — all done by the server.
struct ClubListFilters: Equatable {
    enum Role: String, CaseIterable, Identifiable {
        case secretary, captain, viceCaptain = "vice_captain", member
        var id: String { rawValue }
        var label: String {
            switch self {
            case .secretary: return "Secretary"
            case .captain: return "Captain"
            case .viceCaptain: return "Vice captain"
            case .member: return "Member"
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case name, recent, members
        var id: String { rawValue }
        var label: String {
            switch self {
            case .name: return "Name A–Z"
            case .recent: return "Recently joined"
            case .members: return "Most members"
            }
        }
    }

    var query = ""
    var role: Role?
    var sport: String?
    /// nil for either, true for published pages, false for none.
    var publicPage: Bool?
    var sort: Sort = .name

    var isFiltered: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || role != nil || sport != nil || publicPage != nil
    }

    func queryItems(page: Int, perPage: Int) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "sort", value: sort.rawValue),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { items.append(.init(name: "q", value: String(q.prefix(100)))) }
        if let role { items.append(.init(name: "role", value: role.rawValue)) }
        if let sport { items.append(.init(name: "sport", value: sport)) }
        if let publicPage { items.append(.init(name: "public_page", value: publicPage ? "true" : "false")) }
        return items
    }
}

/// A role as the picker offers it: the roles, plus a secretary who captains.
struct RoleChoice: Hashable, Identifiable {
    var role: ClubRole
    var isCaptain: Bool

    init(role: ClubRole, isCaptain: Bool) {
        self.role = role
        // Only a secretary carries the flag; a Captain is a captain by role.
        self.isCaptain = role.isSecretary && isCaptain
    }

    var id: String { role.rawValue + (isCaptain ? "+captain" : "") }

    var label: String {
        isCaptain ? "Secretary & captain" : role.displayName
    }

    var shortLabel: String { isCaptain ? "SEC · C" : role.shortLabel }

    var responsibilities: String {
        isCaptain
            ? "A secretary who also captains the side — usual in a small club. Marked captain on the team sheet."
            : role.responsibilities
    }

    /// Every choice a secretary can make, strongest first.
    static let appointable: [RoleChoice] =
        [RoleChoice(role: .clubAdmin, isCaptain: true)]
        + ClubRole.appointable.map { RoleChoice(role: $0, isCaptain: false) }
}

/// `GET/PATCH /clubs/{id}/page` — the club's own public page.
struct ClubPageSettings: Codable, Equatable {
    let id: UUID
    var name: String
    var slug: String?
    var tagline: String?
    var about: String?
    var ground: String?
    var foundedYear: Int?
    var contactEmail: String?
    var website: String?
    var publicPage: Bool
    var iconPlayerId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, tagline, about, ground, website
        case foundedYear = "founded_year"
        case contactEmail = "contact_email"
        case publicPage = "public_page"
        case iconPlayerId = "icon_player_id"
    }

    /// A default anyone can live with, from the name the club already chose.
    static func suggestedSlug(for name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        var lastDash = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                out.unicodeScalars.append(scalar)
                lastDash = false
            } else if !lastDash, !out.isEmpty {
                out.append("-")
                lastDash = true
            }
        }
        return out.hasSuffix("-") ? String(out.dropLast()) : out
    }

    /// Sent as `icon_player_id` to mean "nobody": a JSON null means "not
    /// touched", so clearing needs a value the API can tell apart.
    static let noIconPlayer = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}

/// One person in a team, from `GET /teams/{id}/members`.
struct TeamMemberRow: Codable, Identifiable, Hashable {
    let userId: UUID
    var name: String
    var role: ClubRole
    var avatarUrl: String?
    var positionRole: String?

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case name, role
        case userId = "user_id"
        case avatarUrl = "avatar_url"
        case positionRole = "position_role"
    }
}

/// A player's card, as a secretary sees it from a shared link. No contact
/// details — those come with membership, which the player still accepts.
struct SharedPlayerCard: Codable, Identifiable {
    let id: UUID
    var name: String
    var avatarUrl: String?
    var primarySport: String?
    var sportProfiles: [SportProfile]?
    var area: String?

    enum CodingKeys: String, CodingKey {
        case id, name, area
        case avatarUrl = "avatar_url"
        case primarySport = "primary_sport"
        case sportProfiles = "sport_profiles"
    }

    /// Pulls the token out of whatever was pasted — people paste the whole
    /// message they were sent, not just the link.
    static func token(in text: String) -> String? {
        guard let range = text.range(of: #"/p/([A-Za-z0-9]{16,64})"#, options: .regularExpression) else { return nil }
        return String(text[range].dropFirst(3))
    }
}

/// A new club's next steps, ticked off from what exists.
struct ClubSetupStep: Identifiable, Equatable {
    enum Kind { case players, team, captain, ground }
    let kind: Kind
    let done: Bool
    var id: Kind { kind }

    var title: String {
        switch kind {
        case .players: return "Add your players"
        case .team: return "Add a team"
        case .captain: return "Name a captain"
        case .ground: return "Add your ground"
        }
    }

    var detail: String {
        switch kind {
        case .players: return "By email or mobile number, or from a profile link a player sends you."
        case .team: return "A 1st XI, a Sunday side, the juniors — each keeps its own squad."
        case .captain: return "Captains pick the side and run the scorebook. Captain it yourself? Be Secretary & captain."
        case .ground: return "So every fixture says where to turn up."
        }
    }

    var systemImage: String {
        switch kind {
        case .players: return "person.badge.plus"
        case .team: return "person.3"
        case .captain: return "star"
        case .ground: return "mappin.and.ellipse"
        }
    }

    static func steps(members: [ClubMemberDetail], teams: Int, venues: Int) -> [ClubSetupStep] {
        [
            ClubSetupStep(kind: .players, done: members.count > 1),
            ClubSetupStep(kind: .team, done: teams > 0),
            ClubSetupStep(kind: .captain, done: members.contains { $0.role == .teamCaptain || $0.isCaptain == true }),
            ClubSetupStep(kind: .ground, done: venues > 0),
        ]
    }
}
