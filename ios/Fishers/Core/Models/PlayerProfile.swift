import Foundation

/// One sport a player takes part in, with the level, league grade and stats they
/// keep for it. A player carries one of these per sport they picked at setup.
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

    /// Spelled out because supplying both coding halves stops synthesis. The
    /// API coder converts snake_case JSON to these camelCase names.
    private enum CodingKeys: String, CodingKey {
        case sport, position, skillLevel, currentDivision, targetDivision
        case ageGroup, teamName, yearsPlaying, stats
    }

    /// Stats travel as `[{key, value}]` rather than a JSON object: the API
    /// coder's snake_case conversion rewrites dictionary keys, which would
    /// mangle stat keys like `batting_style` on the way back.
    private struct StatEntry: Codable {
        var key: String
        var value: String
    }

    /// Hand-rolled so a payload without `stats` still decodes, and so either
    /// wire shape (entry list or plain object) is accepted.
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
        if let entries = try? c.decodeIfPresent([StatEntry].self, forKey: .stats) {
            stats = Dictionary(entries.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        } else {
            stats = try c.decodeIfPresent([String: String].self, forKey: .stats) ?? [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sport, forKey: .sport)
        try c.encodeIfPresent(position, forKey: .position)
        try c.encodeIfPresent(skillLevel, forKey: .skillLevel)
        try c.encodeIfPresent(currentDivision, forKey: .currentDivision)
        try c.encodeIfPresent(targetDivision, forKey: .targetDivision)
        try c.encodeIfPresent(ageGroup, forKey: .ageGroup)
        try c.encodeIfPresent(teamName, forKey: .teamName)
        try c.encodeIfPresent(yearsPlaying, forKey: .yearsPlaying)
        let entries = stats.keys.sorted().map { StatEntry(key: $0, value: stats[$0] ?? "") }
        try c.encode(entries, forKey: .stats)
    }

    var sportKind: Sport? { Sport(rawValue: sport) }
    var tier: SkillTier? { SkillTier(stored: skillLevel) }
    var division: Division? { Division(stored: currentDivision) }
    var target: Division? { Division(stored: targetDivision) }
    var ageBand: AgeGroup? { AgeGroup(stored: ageGroup) }

    /// True once the player has said how good they are — the gate the setup flow uses.
    var isComplete: Bool { tier != nil }

    /// Divisions above the one they play now, i.e. what "levelling up" means here.
    var divisionsToTarget: Int {
        guard let division, let target else { return 0 }
        return max(0, target.rank - division.rank)
    }
}

/// Where the player is based and how they get to fixtures — drives away-game
/// lift sharing and "is this venue realistic for them" filtering.
struct PlayerLocation: Codable, Hashable {
    var area: String?
    var postcode: String?
    var travelRadiusMiles: Int?
    var transport: TransportMode?
    var spareSeats: Int?
    var preferredDays: [Int]?
    var notes: String?

    var weekdays: [Weekday] {
        (preferredDays ?? []).compactMap { Weekday(rawValue: $0) }
    }

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
    case unproven
    case patchy
    case dependable
    case rockSolid

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
/// they pay. Captains see it in the squad picker; players see their own here.
struct ReliabilityScore: Codable, Hashable {
    var score: Int
    var attendanceRate: Double
    var responseRate: Double
    var paymentRate: Double
    var lateCancellations: Int
    var sampleSize: Int

    static let minimumSample = 3

    var band: ReliabilityBand {
        guard sampleSize >= Self.minimumSample else { return .unproven }
        switch score {
        case 85...: return .rockSolid
        case 65..<85: return .dependable
        default: return .patchy
        }
    }

    /// 0…1 for the progress ring on the profile header.
    var fraction: Double { Double(min(max(score, 0), 100)) / 100 }

    /// Same weighting the backend applies, kept here so demo mode matches live.
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
        let penalty = 5 * lateCancellations
        let score = max(0, min(100, Int((weighted * 100).rounded()) - penalty))
        return ReliabilityScore(
            score: score,
            attendanceRate: attendanceRate,
            responseRate: responseRate,
            paymentRate: paymentRate,
            lateCancellations: lateCancellations,
            sampleSize: invitesReceived
        )
    }
}

/// Body of `PATCH /users/me`. Legacy flat fields (`sports`, `position`,
/// `skillLevel`) mirror the primary sport so older screens keep working.
struct ProfileUpdate: Codable, Hashable {
    var name: String
    var phone: String?
    var avatarUrl: String?
    var emergencyContact: String?
    var primarySport: String?
    var sports: [String]
    var position: String?
    var skillLevel: String?
    var sportProfiles: [SportProfile]
    var location: PlayerLocation?

    init(name: String, sportProfiles: [SportProfile], primarySport: String?) {
        self.name = name
        self.sportProfiles = sportProfiles
        self.primarySport = primarySport
        self.sports = sportProfiles.map(\.sport)
        let primary = sportProfiles.first { $0.sport == primarySport } ?? sportProfiles.first
        self.position = primary?.position
        self.skillLevel = primary?.skillLevel
    }
}
