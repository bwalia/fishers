import Foundation

/// Sports the app knows about. Wire format stays a plain string (`sports_played`,
/// `Club.sportTypes`, `Team.sport`) so clubs can carry sports outside this list.
enum Sport: String, CaseIterable, Identifiable, Codable, Hashable {
    case cricket, football, badminton, padel, tennis, hockey, netball, rugby, basketball

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .cricket: return "figure.cricket"
        case .football: return "soccerball"
        case .badminton: return "figure.badminton"
        case .padel, .tennis: return "tennis.racket"
        case .hockey: return "figure.hockey"
        case .netball: return "figure.netball"
        case .rugby: return "figure.rugby"
        case .basketball: return "basketball.fill"
        }
    }

    /// Positions offered during profile setup for this sport.
    var positions: [String] {
        switch self {
        case .cricket:
            return ["Batter", "Fast Bowler", "Spinner", "All-rounder", "Wicketkeeper"]
        case .football, .hockey:
            return ["Goalkeeper", "Defender", "Midfielder", "Forward"]
        case .badminton, .tennis:
            return ["Singles", "Doubles", "Mixed doubles"]
        case .padel:
            return ["Right side", "Left side", "Either side"]
        case .netball:
            return ["Goal Shooter", "Goal Attack", "Wing Attack", "Centre", "Wing Defence", "Goal Defence", "Goal Keeper"]
        case .rugby:
            return ["Front row", "Second row", "Back row", "Half back", "Centre", "Back three"]
        case .basketball:
            return ["Guard", "Forward", "Centre"]
        }
    }

    /// Leagues are graded per sport; cricket drives the reference scenario.
    var usesDivisions: Bool {
        switch self {
        case .cricket, .football, .hockey, .netball, .rugby: return true
        case .badminton, .padel, .tennis, .basketball: return false
        }
    }

    init?(label: String?) {
        guard let label, let sport = Sport(rawValue: label.lowercased()) else { return nil }
        self = sport
    }
}

/// Self-rated standard, ordered so a player can see the rung above them.
enum SkillTier: String, CaseIterable, Identifiable, Codable, Hashable {
    case beginner, improver, intermediate, club, advanced, elite

    var id: String { rawValue }
    var label: String { self == .club ? "Club standard" : rawValue.capitalized }

    var blurb: String {
        switch self {
        case .beginner: return "New to the sport — learning the basics."
        case .improver: return "Played a bit, still building consistency."
        case .intermediate: return "Comfortable in social and lower league sides."
        case .club: return "Regular league player, holds a place in a side."
        case .advanced: return "Strong league performer, front-line pick."
        case .elite: return "Premier, county or representative standard."
        }
    }

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// The next rung up, used by the progression hint on the profile.
    var next: SkillTier? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    /// Tolerates the capitalised strings stored on `skill_level`.
    init?(stored: String?) {
        guard let stored else { return nil }
        let key = stored.lowercased().replacingOccurrences(of: " standard", with: "")
        guard let tier = SkillTier(rawValue: key) else { return nil }
        self = tier
    }
}

/// League grade, lowest to highest — a player's current and target division.
enum Division: String, CaseIterable, Identifiable, Codable, Hashable {
    case social, development, division5, division4, division3, division2, division1, premier, county

    var id: String { rawValue }

    var label: String {
        switch self {
        case .social: return "Social & friendlies"
        case .development: return "Development side"
        case .division5: return "Division 5"
        case .division4: return "Division 4"
        case .division3: return "Division 3"
        case .division2: return "Division 2"
        case .division1: return "Division 1"
        case .premier: return "Premier Division"
        case .county: return "County / Representative"
        }
    }

    var shortLabel: String {
        switch self {
        case .social: return "Social"
        case .development: return "Dev"
        case .division5: return "Div 5"
        case .division4: return "Div 4"
        case .division3: return "Div 3"
        case .division2: return "Div 2"
        case .division1: return "Div 1"
        case .premier: return "Prem"
        case .county: return "County"
        }
    }

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var next: Division? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    init?(stored: String?) {
        guard let stored, let division = Division(rawValue: stored) else { return nil }
        self = division
    }
}

/// Age band the player is eligible for — colts sides pick from the junior bands.
enum AgeGroup: String, CaseIterable, Identifiable, Codable, Hashable {
    case u11, u13, u15, u17, senior, vets40, vets50

    var id: String { rawValue }

    var label: String {
        switch self {
        case .u11: return "Under 11s"
        case .u13: return "Under 13s"
        case .u15: return "Under 15s"
        case .u17: return "Under 17s"
        case .senior: return "Senior"
        case .vets40: return "Vets 40+"
        case .vets50: return "Vets 50+"
        }
    }

    var isJunior: Bool {
        switch self {
        case .u11, .u13, .u15, .u17: return true
        default: return false
        }
    }

    init?(stored: String?) {
        guard let stored, let group = AgeGroup(rawValue: stored) else { return nil }
        self = group
    }
}

/// How the player gets to fixtures — feeds lift sharing on away games.
enum TransportMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case driverWithSeats, driver, publicTransport, needsLift

    var id: String { rawValue }

    var label: String {
        switch self {
        case .driverWithSeats: return "Drives, can offer lifts"
        case .driver: return "Drives, no spare seats"
        case .publicTransport: return "Public transport"
        case .needsLift: return "Needs a lift"
        }
    }

    var systemImage: String {
        switch self {
        case .driverWithSeats: return "car.2.fill"
        case .driver: return "car.fill"
        case .publicTransport: return "tram.fill"
        case .needsLift: return "hand.raised.fill"
        }
    }

    var offersLifts: Bool { self == .driverWithSeats }
}

/// Weekday, matching `Calendar` numbering (1 = Sunday).
enum Weekday: Int, CaseIterable, Identifiable, Codable, Hashable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    /// Monday-first ordering for the day picker.
    static var pickerOrder: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}

/// One sport a player takes part in, with the level, league grade and stats they
/// keep for it. A player carries one of these per sport picked at setup.
struct SportProfile: Codable, Hashable, Identifiable {
    var sport: String
    var position: String?
    var skillLevel: String?
    var currentDivision: String?
    var targetDivision: String?
    var ageGroup: String?
    var teamName: String?
    var yearsPlaying: Int?
    var stats: [String: String]

    var id: String { sport }

    enum CodingKeys: String, CodingKey {
        case sport, position, stats
        case skillLevel = "skill_level"
        case currentDivision = "current_division"
        case targetDivision = "target_division"
        case ageGroup = "age_group"
        case teamName = "team_name"
        case yearsPlaying = "years_playing"
    }

    init(
        sport: String,
        position: String? = nil,
        skillLevel: String? = nil,
        currentDivision: String? = nil,
        targetDivision: String? = nil,
        ageGroup: String? = nil,
        teamName: String? = nil,
        yearsPlaying: Int? = nil,
        stats: [String: String] = [:]
    ) {
        self.sport = sport
        self.position = position
        self.skillLevel = skillLevel
        self.currentDivision = currentDivision
        self.targetDivision = targetDivision
        self.ageGroup = ageGroup
        self.teamName = teamName
        self.yearsPlaying = yearsPlaying
        self.stats = stats
    }

    /// Hand-rolled so a payload without `stats` still decodes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sport = try c.decode(String.self, forKey: .sport)
        position = try c.decodeIfPresent(String.self, forKey: .position)
        skillLevel = try c.decodeIfPresent(String.self, forKey: .skillLevel)
        currentDivision = try c.decodeIfPresent(String.self, forKey: .currentDivision)
        targetDivision = try c.decodeIfPresent(String.self, forKey: .targetDivision)
        ageGroup = try c.decodeIfPresent(String.self, forKey: .ageGroup)
        teamName = try c.decodeIfPresent(String.self, forKey: .teamName)
        yearsPlaying = try c.decodeIfPresent(Int.self, forKey: .yearsPlaying)
        stats = try c.decodeIfPresent([String: String].self, forKey: .stats) ?? [:]
    }

    var sportKind: Sport? { Sport(rawValue: sport) }
    var tier: SkillTier? { SkillTier(stored: skillLevel) }
    var division: Division? { Division(stored: currentDivision) }
    var target: Division? { Division(stored: targetDivision) }
    var ageBand: AgeGroup? { AgeGroup(stored: ageGroup) }

    /// True once the player has said what standard they play at — the gate the
    /// setup flow uses.
    var isComplete: Bool { tier != nil }

    /// How many divisions sit between where they play and where they're aiming.
    var divisionsToTarget: Int {
        guard let division, let target else { return 0 }
        return max(0, target.rank - division.rank)
    }
}

/// Where the player is based and how they travel — drives away-game lift sharing.
struct PlayerLocation: Codable, Hashable {
    var area: String?
    var postcode: String?
    var travelRadiusMiles: Int?
    var transport: TransportMode?
    var spareSeats: Int?
    var preferredDays: [Int]?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case area, postcode, transport, notes
        case travelRadiusMiles = "travel_radius_miles"
        case spareSeats = "spare_seats"
        case preferredDays = "preferred_days"
    }

    var weekdays: [Weekday] { (preferredDays ?? []).compactMap { Weekday(rawValue: $0) } }

    var summary: String? {
        let parts = [area, postcode].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var isEmpty: Bool {
        (area?.isEmpty ?? true)
            && (postcode?.isEmpty ?? true)
            && travelRadiusMiles == nil
            && transport == nil
            && (preferredDays?.isEmpty ?? true)
            && (notes?.isEmpty ?? true)
    }
}

enum ReliabilityBand: String, Codable, CaseIterable {
    case unproven, patchy, dependable
    case rockSolid = "rock_solid"

    var label: String {
        switch self {
        case .unproven: return "Unproven"
        case .patchy: return "Patchy"
        case .dependable: return "Dependable"
        case .rockSolid: return "Rock solid"
        }
    }

    var blurb: String {
        switch self {
        case .unproven: return "Not enough games yet to score."
        case .patchy: return "Drops out late more often than most."
        case .dependable: return "Turns up when they say they will."
        case .rockSolid: return "Answers early, shows up, pays up."
        }
    }

    var systemImage: String {
        switch self {
        case .unproven: return "questionmark.circle"
        case .patchy: return "exclamationmark.triangle.fill"
        case .dependable: return "checkmark.circle.fill"
        case .rockSolid: return "star.circle.fill"
        }
    }
}

/// Server-computed selection weighting: did they answer, did they turn up, did
/// they pay. Captains weigh it beside skill; players see their own breakdown.
struct ReliabilityScore: Codable, Hashable {
    var score: Int
    var attendanceRate: Double
    var responseRate: Double
    var paymentRate: Double
    var lateCancellations: Int
    var sampleSize: Int
    var band: ReliabilityBand

    static let minimumSample = 3

    enum CodingKeys: String, CodingKey {
        case score, band
        case attendanceRate = "attendance_rate"
        case responseRate = "response_rate"
        case paymentRate = "payment_rate"
        case lateCancellations = "late_cancellations"
        case sampleSize = "sample_size"
    }

    /// 0…1 for the progress ring on the profile header.
    var fraction: Double { Double(min(max(score, 0), 100)) / 100 }

    /// Same weighting as `fishers_domain::reliability`, kept here so previews
    /// and any client-side estimate match the server.
    static func compute(
        invitesReceived: Int,
        responded: Int,
        saidGoing: Int,
        turnedUp: Int,
        lateCancellations: Int,
        feesDue: Int,
        feesPaid: Int
    ) -> ReliabilityScore {
        let responseRate = invitesReceived > 0 ? Double(responded) / Double(invitesReceived) : 0
        let attendanceRate = saidGoing > 0 ? Double(turnedUp) / Double(saidGoing) : 0
        let paymentRate = feesDue > 0 ? Double(feesPaid) / Double(feesDue) : 1
        let weighted = 0.5 * attendanceRate + 0.25 * responseRate + 0.25 * paymentRate
        let score = max(0, min(100, Int((weighted * 100).rounded()) - 5 * lateCancellations))
        let band: ReliabilityBand
        switch (invitesReceived, score) {
        case (..<minimumSample, _): band = .unproven
        case (_, 85...): band = .rockSolid
        case (_, 65..<85): band = .dependable
        default: band = .patchy
        }
        return ReliabilityScore(
            score: score,
            attendanceRate: attendanceRate,
            responseRate: responseRate,
            paymentRate: paymentRate,
            lateCancellations: lateCancellations,
            sampleSize: invitesReceived,
            band: band
        )
    }
}

/// Body of `PATCH /me`. The client submits the whole profile it holds; the
/// flat `position_role` / `skill_level` mirror the primary sport.
struct ProfileUpdate: Codable, Hashable {
    var name: String
    var phone: String?
    var avatarUrl: String?
    var emergencyContact: String?
    var primarySport: String?
    var sportsPlayed: [String]
    var positionRole: String?
    var skillLevel: String?
    var sportProfiles: [SportProfile]
    var location: PlayerLocation?

    enum CodingKeys: String, CodingKey {
        case name, phone, location
        case avatarUrl = "avatar_url"
        case emergencyContact = "emergency_contact"
        case primarySport = "primary_sport"
        case sportsPlayed = "sports_played"
        case positionRole = "position_role"
        case skillLevel = "skill_level"
        case sportProfiles = "sport_profiles"
    }

    init(name: String, sportProfiles: [SportProfile], primarySport: String?) {
        self.name = name
        self.sportProfiles = sportProfiles
        self.primarySport = primarySport
        self.sportsPlayed = sportProfiles.map(\.sport)
        let primary = sportProfiles.first { $0.sport == primarySport } ?? sportProfiles.first
        self.positionRole = primary?.position
        self.skillLevel = primary?.skillLevel
    }
}
