import Foundation

/// Canonical ECB Play-Cricket public site. Fabricated `/website/...` sample paths
/// do not resolve — always open the real homepage.
enum PlayCricketLinks {
    static let homeString = "https://play-cricket.com/"
    static let home = URL(string: homeString)!

    /// Returns the Play-Cricket home URL when `raw` points at play-cricket.com
    /// (including legacy broken deep links), otherwise parses `raw` as-is.
    static func resolve(_ raw: String?) -> URL? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let lowered = raw.lowercased()
        if lowered.contains("play-cricket.com") || lowered.contains("playcricket.com") {
            return home
        }
        return URL(string: raw)
    }
}

// MARK: - Play-Cricket player link

struct PlayCricketPlayerLink: Decodable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let clubId: UUID?
    let playCricketPlayerId: String
    let playCricketSiteId: String?
    let displayName: String?
    let profileUrl: String?
    /// Kept optional + lossy so fractional timestamps never fail the whole payload.
    let linkedAt: Date?
    let lastSyncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case clubId = "club_id"
        case playCricketPlayerId = "play_cricket_player_id"
        case playCricketSiteId = "play_cricket_site_id"
        case displayName = "display_name"
        case profileUrl = "profile_url"
        case linkedAt = "linked_at"
        case lastSyncedAt = "last_synced_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        userId = try c.decode(UUID.self, forKey: .userId)
        clubId = try c.decodeIfPresent(UUID.self, forKey: .clubId)
        playCricketPlayerId = try c.decode(String.self, forKey: .playCricketPlayerId)
        playCricketSiteId = try c.decodeIfPresent(String.self, forKey: .playCricketSiteId)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        profileUrl = try c.decodeIfPresent(String.self, forKey: .profileUrl)
        linkedAt = Self.lossyDate(c, forKey: .linkedAt)
        lastSyncedAt = Self.lossyDate(c, forKey: .lastSyncedAt)
    }

    var profileURL: URL? {
        PlayCricketLinks.resolve(profileUrl)
    }

    private static func lossyDate(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
        if let date = try? c.decode(Date.self, forKey: key) { return date }
        guard let raw = try? c.decode(String.self, forKey: key) else { return nil }
        return StatsDateParsing.date(from: raw)
    }
}

// MARK: - Player season row

struct PlayerSeasonStats: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let clubId: UUID?
    let teamId: UUID?
    let sport: String
    let seasonYear: Int
    let source: String
    let matches: Int
    let runs: Int
    let wickets: Int
    let battingInnings: Int
    let notOuts: Int
    let ballsFaced: Int
    let fours: Int
    let sixes: Int
    let highScore: Int?
    let oversBowled: Double
    let bowlingRuns: Int
    let maidens: Int
    let catches: Int
    let stumpings: Int
    let playerName: String?
    let clubName: String?
    let playCricketProfileUrl: String?
    let playCricketPlayerId: String?
    let battingAverage: Double?
    let bowlingAverage: Double?
    let strikeRate: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case clubId = "club_id"
        case teamId = "team_id"
        case sport
        case seasonYear = "season_year"
        case source
        case matches, runs, wickets
        case battingInnings = "batting_innings"
        case notOuts = "not_outs"
        case ballsFaced = "balls_faced"
        case fours, sixes
        case highScore = "high_score"
        case oversBowled = "overs_bowled"
        case bowlingRuns = "bowling_runs"
        case maidens, catches, stumpings
        case playerName = "player_name"
        case clubName = "club_name"
        case playCricketProfileUrl = "play_cricket_profile_url"
        case playCricketPlayerId = "play_cricket_player_id"
        case battingAverage = "batting_average"
        case bowlingAverage = "bowling_average"
        case strikeRate = "strike_rate"
    }

    var playCricketURL: URL? {
        PlayCricketLinks.resolve(playCricketProfileUrl)
    }
}

// MARK: - Achievements

struct UserAchievement: Decodable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let achievementCode: String
    let clubId: UUID?
    let seasonYear: Int?
    let awardedAt: Date?
    let title: String
    let description: String?
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case achievementCode = "achievement_code"
        case clubId = "club_id"
        case seasonYear = "season_year"
        case awardedAt = "awarded_at"
        case title, description, icon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        userId = try c.decode(UUID.self, forKey: .userId)
        achievementCode = try c.decode(String.self, forKey: .achievementCode)
        clubId = try c.decodeIfPresent(UUID.self, forKey: .clubId)
        seasonYear = try c.decodeIfPresent(Int.self, forKey: .seasonYear)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        if let date = try? c.decode(Date.self, forKey: .awardedAt) {
            awardedAt = date
        } else if let raw = try? c.decode(String.self, forKey: .awardedAt) {
            awardedAt = StatsDateParsing.date(from: raw)
        } else {
            awardedAt = nil
        }
    }
}

struct MeStatsResponse: Decodable, Equatable {
    let links: [PlayCricketPlayerLink]
    let seasons: [PlayerSeasonStats]
    let achievements: [UserAchievement]
}

// MARK: - Club board

struct PlayCricketClubSite: Decodable, Equatable {
    let clubId: UUID
    let siteId: String
    let siteName: String?
    let publicUrl: String?
    let lastSyncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case clubId = "club_id"
        case siteId = "site_id"
        case siteName = "site_name"
        case publicUrl = "public_url"
        case lastSyncedAt = "last_synced_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clubId = try c.decode(UUID.self, forKey: .clubId)
        siteId = try c.decode(String.self, forKey: .siteId)
        siteName = try c.decodeIfPresent(String.self, forKey: .siteName)
        publicUrl = try c.decodeIfPresent(String.self, forKey: .publicUrl)
        if let date = try? c.decode(Date.self, forKey: .lastSyncedAt) {
            lastSyncedAt = date
        } else if let raw = try? c.decode(String.self, forKey: .lastSyncedAt) {
            lastSyncedAt = StatsDateParsing.date(from: raw)
        } else {
            lastSyncedAt = nil
        }
    }

    var publicURL: URL? {
        PlayCricketLinks.resolve(publicUrl)
    }
}

struct ClubSeasonStats: Codable, Equatable {
    let id: UUID
    let clubId: UUID
    let seasonYear: Int
    let source: String
    let matchesPlayed: Int
    let wins: Int
    let losses: Int
    let draws: Int
    let noResults: Int
    let runsFor: Int
    let runsAgainst: Int
    let wicketsTaken: Int
    let wicketsLost: Int

    enum CodingKeys: String, CodingKey {
        case id
        case clubId = "club_id"
        case seasonYear = "season_year"
        case source
        case matchesPlayed = "matches_played"
        case wins, losses, draws
        case noResults = "no_results"
        case runsFor = "runs_for"
        case runsAgainst = "runs_against"
        case wicketsTaken = "wickets_taken"
        case wicketsLost = "wickets_lost"
    }

    var recordLabel: String {
        "\(wins)–\(losses)–\(draws)"
    }
}

struct ClubSeasonBoard: Decodable, Equatable {
    let club: ClubSeasonStats
    let playCricket: PlayCricketClubSite?
    let topBatters: [PlayerSeasonStats]
    let topBowlers: [PlayerSeasonStats]

    enum CodingKeys: String, CodingKey {
        case club
        case playCricket = "play_cricket"
        case topBatters = "top_batters"
        case topBowlers = "top_bowlers"
    }
}

// MARK: - Date helpers

enum StatsDateParsing {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from raw: String) -> Date? {
        fractional.date(from: raw) ?? plain.date(from: raw)
    }
}
