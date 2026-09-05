import Foundation

struct PlayCricketPlayerLink: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let clubId: UUID?
    let playCricketPlayerId: String
    let playCricketSiteId: String?
    let displayName: String?
    let profileUrl: String?
    let linkedAt: Date
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

    var profileURL: URL? {
        guard let profileUrl, let url = URL(string: profileUrl) else { return nil }
        return url
    }
}

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
        guard let playCricketProfileUrl, let url = URL(string: playCricketProfileUrl) else {
            return nil
        }
        return url
    }
}

struct UserAchievement: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let achievementCode: String
    let clubId: UUID?
    let seasonYear: Int?
    let awardedAt: Date
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
}

struct MeStatsResponse: Codable, Equatable {
    let links: [PlayCricketPlayerLink]
    let seasons: [PlayerSeasonStats]
    let achievements: [UserAchievement]
}

struct PlayCricketClubSite: Codable, Equatable {
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

    var publicURL: URL? {
        guard let publicUrl, let url = URL(string: publicUrl) else { return nil }
        return url
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

struct ClubSeasonBoard: Codable, Equatable {
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
