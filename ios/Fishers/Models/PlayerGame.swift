import Foundation

// A player's season, match by match, as `/me/game` and `/users/{id}/game`
// return it, and a club's season from `/clubs/{id}/season`. The arithmetic is
// the API's (`backend/domain/src/season.rs`); this is the shape and the words,
// the same split the web makes in `web/src/lib/season.ts`.
//
// Every decoder here is lenient about what is missing: a count the server
// stops sending reads as 0 and a list as empty, rather than failing the whole
// screen. This page is the good news about somebody's summer, and a new field
// on the server is no reason for it to become an error message.

// MARK: - Player

/// Wickets for runs, the way a scorebook writes it: "4/23".
struct GameFigures: Decodable, Equatable {
    let wickets: Int
    let runs: Int

    var label: String { "\(wickets)/\(runs)" }
}

/// A season, or a career, added up.
struct GameTotals: Decodable, Equatable {
    var matches = 0
    var won = 0
    var battingInnings = 0
    var notOuts = 0
    var runs = 0
    var ballsFaced = 0
    var fours = 0
    var sixes = 0
    var highScore: Int?
    var highScoreNotOut = false
    var fifties = 0
    var hundreds = 0
    var ducks = 0
    var doubleFigures = 0
    var battingAverage: Double?
    var strikeRate: Double?
    var bowlingBalls = 0
    var overs = "0.0"
    var bowlingRuns = 0
    var wickets = 0
    var maidens = 0
    var economy: Double?
    var bowlingAverage: Double?
    var bowlingStrikeRate: Double?
    var bestBowling: GameFigures?
    var catches = 0
    var stumpings = 0
    var playerOfMatch = 0

    enum CodingKeys: String, CodingKey {
        case matches, won, runs, fours, sixes, fifties, hundreds, ducks, overs, wickets, maidens
        case economy, catches, stumpings
        case battingInnings = "batting_innings"
        case notOuts = "not_outs"
        case ballsFaced = "balls_faced"
        case highScore = "high_score"
        case highScoreNotOut = "high_score_not_out"
        case doubleFigures = "double_figures"
        case battingAverage = "batting_average"
        case strikeRate = "strike_rate"
        case bowlingBalls = "bowling_balls"
        case bowlingRuns = "bowling_runs"
        case bowlingAverage = "bowling_average"
        case bowlingStrikeRate = "bowling_strike_rate"
        case bestBowling = "best_bowling"
        case playerOfMatch = "player_of_match"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? 0 }
        func double(_ key: CodingKeys) -> Double? { (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil }
        matches = int(.matches)
        won = int(.won)
        battingInnings = int(.battingInnings)
        notOuts = int(.notOuts)
        runs = int(.runs)
        ballsFaced = int(.ballsFaced)
        fours = int(.fours)
        sixes = int(.sixes)
        highScore = (try? c.decodeIfPresent(Int.self, forKey: .highScore)) ?? nil
        highScoreNotOut = (try? c.decodeIfPresent(Bool.self, forKey: .highScoreNotOut)) ?? false
        fifties = int(.fifties)
        hundreds = int(.hundreds)
        ducks = int(.ducks)
        doubleFigures = int(.doubleFigures)
        battingAverage = double(.battingAverage)
        strikeRate = double(.strikeRate)
        bowlingBalls = int(.bowlingBalls)
        overs = (try? c.decodeIfPresent(String.self, forKey: .overs)) ?? "0.0"
        bowlingRuns = int(.bowlingRuns)
        wickets = int(.wickets)
        maidens = int(.maidens)
        economy = double(.economy)
        bowlingAverage = double(.bowlingAverage)
        bowlingStrikeRate = double(.bowlingStrikeRate)
        bestBowling = (try? c.decodeIfPresent(GameFigures.self, forKey: .bestBowling)) ?? nil
        catches = int(.catches)
        stumpings = int(.stumpings)
        playerOfMatch = int(.playerOfMatch)
    }
}

/// One match on the form guide.
struct GameFormEntry: Decodable, Equatable, Identifiable {
    let matchId: UUID
    let eventId: UUID?
    let playedAt: Date
    let opposition: String
    /// nil is a tie or no result, not "unknown".
    let won: Bool?
    let batted: Bool
    let runs: Int
    let balls: Int
    let notOut: Bool
    let bowled: Bool
    let wickets: Int
    let runsConceded: Int
    let overs: String
    let catches: Int
    let playerOfMatch: Bool

    var id: UUID { matchId }

    enum CodingKeys: String, CodingKey {
        case opposition, won, batted, runs, balls, bowled, wickets, overs, catches
        case matchId = "match_id"
        case eventId = "event_id"
        case playedAt = "played_at"
        case notOut = "not_out"
        case runsConceded = "runs_conceded"
        case playerOfMatch = "player_of_match"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? 0 }
        func bool(_ key: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? false }
        matchId = try c.decode(UUID.self, forKey: .matchId)
        eventId = try c.decodeIfPresent(UUID.self, forKey: .eventId)
        playedAt = try c.decode(Date.self, forKey: .playedAt)
        opposition = (try c.decodeIfPresent(String.self, forKey: .opposition)) ?? ""
        won = try c.decodeIfPresent(Bool.self, forKey: .won)
        batted = bool(.batted)
        runs = int(.runs)
        balls = int(.balls)
        notOut = bool(.notOut)
        bowled = bool(.bowled)
        wickets = int(.wickets)
        runsConceded = int(.runsConceded)
        overs = (try c.decodeIfPresent(String.self, forKey: .overs)) ?? "0.0"
        catches = int(.catches)
        playerOfMatch = bool(.playerOfMatch)
    }
}

/// Which way the recent innings are heading. Never "falling": the API says
/// `quieter`, and the words for it put it in proportion.
enum GameTrend: String, Equatable {
    case rising, steady, quieter
}

/// The last few matches, and what they add up to.
struct GameForm: Decodable, Equatable {
    /// Newest first, at most ten.
    var matches: [GameFormEntry] = []
    var recentBattingAverage: Double?
    var battingTrend: GameTrend?
    var recentWicketsPerMatch: Double?
    var bowlingTrend: GameTrend?

    enum CodingKeys: String, CodingKey {
        case matches
        case recentBattingAverage = "recent_batting_average"
        case battingTrend = "batting_trend"
        case recentWicketsPerMatch = "recent_wickets_per_match"
        case bowlingTrend = "bowling_trend"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matches = try c.decodeIfPresent([GameFormEntry].self, forKey: .matches) ?? []
        recentBattingAverage = try c.decodeIfPresent(Double.self, forKey: .recentBattingAverage)
        recentWicketsPerMatch = try c.decodeIfPresent(Double.self, forKey: .recentWicketsPerMatch)
        // A trend this build has no words for is no trend, not a failed page.
        battingTrend = (try? c.decodeIfPresent(String.self, forKey: .battingTrend)).flatMap { $0 }.flatMap(GameTrend.init)
        bowlingTrend = (try? c.decodeIfPresent(String.self, forKey: .bowlingTrend)).flatMap { $0 }.flatMap(GameTrend.init)
    }
}

/// A best, with where and when it came.
struct GameBest: Decodable, Equatable, Identifiable {
    let code: String
    /// "78*", "5/23", "6", "412" — already written the way cricket writes it.
    let value: String
    let opposition: String?
    let playedAt: Date?
    let seasonYear: Int?
    let thisSeason: Bool

    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code, value, opposition
        case playedAt = "played_at"
        case seasonYear = "season_year"
        case thisSeason = "this_season"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        value = (try c.decodeIfPresent(String.self, forKey: .value)) ?? ""
        opposition = try c.decodeIfPresent(String.self, forKey: .opposition)
        playedAt = try c.decodeIfPresent(Date.self, forKey: .playedAt)
        seasonYear = try c.decodeIfPresent(Int.self, forKey: .seasonYear)
        thisSeason = (try c.decodeIfPresent(Bool.self, forKey: .thisSeason)) ?? false
    }
}

/// A first or a round number, and when it came.
struct GameMilestone: Decodable, Equatable, Identifiable {
    let code: String
    let reachedAt: Date
    let opposition: String
    let thisSeason: Bool

    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code, opposition
        case reachedAt = "reached_at"
        case thisSeason = "this_season"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        reachedAt = try c.decode(Date.self, forKey: .reachedAt)
        opposition = (try c.decodeIfPresent(String.self, forKey: .opposition)) ?? ""
        thisSeason = (try c.decodeIfPresent(Bool.self, forKey: .thisSeason)) ?? false
    }
}

/// Where somebody stands in their club this season. A nil place is a list
/// they are not on (no wickets, say), which is left out rather than shown last.
struct GameClubRank: Decodable, Equatable {
    let clubId: UUID
    let clubName: String
    let runs: Int?
    let wickets: Int?
    let catches: Int?
    let players: Int

    enum CodingKeys: String, CodingKey {
        case runs, wickets, catches, players
        case clubId = "club_id"
        case clubName = "club_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clubId = try c.decode(UUID.self, forKey: .clubId)
        clubName = (try c.decodeIfPresent(String.self, forKey: .clubName)) ?? ""
        runs = try c.decodeIfPresent(Int.self, forKey: .runs)
        wickets = try c.decodeIfPresent(Int.self, forKey: .wickets)
        catches = try c.decodeIfPresent(Int.self, forKey: .catches)
        players = (try c.decodeIfPresent(Int.self, forKey: .players)) ?? 0
    }
}

/// One true thing that went well. `text` is the API's English, kept as the
/// fallback for a code this build has not been taught.
struct GameHighlight: Decodable, Equatable {
    let code: String
    let text: String
    let value: String?
    let detail: String?

    init(code: String, text: String, value: String? = nil, detail: String? = nil) {
        self.code = code
        self.text = text
        self.value = value
        self.detail = detail
    }
}

struct PlayerGame: Decodable, Equatable {
    let userId: UUID
    let name: String
    let season: Int
    let seasons: [Int]
    let totals: GameTotals
    /// Last season, when they played one — the only comparison the page makes.
    let previous: GameTotals?
    let career: GameTotals
    let form: GameForm
    let bests: [GameBest]
    let milestones: [GameMilestone]
    let clubRank: GameClubRank?
    let highlights: [GameHighlight]

    enum CodingKeys: String, CodingKey {
        case name, season, seasons, totals, previous, career, form, bests, milestones, highlights
        case userId = "user_id"
        case clubRank = "club_rank"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(UUID.self, forKey: .userId)
        name = (try c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        season = try c.decode(Int.self, forKey: .season)
        seasons = try c.decodeIfPresent([Int].self, forKey: .seasons) ?? []
        totals = try c.decodeIfPresent(GameTotals.self, forKey: .totals) ?? GameTotals()
        previous = try c.decodeIfPresent(GameTotals.self, forKey: .previous)
        career = try c.decodeIfPresent(GameTotals.self, forKey: .career) ?? GameTotals()
        form = try c.decodeIfPresent(GameForm.self, forKey: .form) ?? GameForm()
        bests = try c.decodeIfPresent([GameBest].self, forKey: .bests) ?? []
        milestones = try c.decodeIfPresent([GameMilestone].self, forKey: .milestones) ?? []
        clubRank = try c.decodeIfPresent(GameClubRank.self, forKey: .clubRank)
        highlights = try c.decodeIfPresent([GameHighlight].self, forKey: .highlights) ?? []
    }
}

// MARK: - Club

struct SeasonLeader: Decodable, Equatable {
    let userId: UUID
    let name: String
    /// Already formatted: "281", "40.1", "4/23".
    let value: String
    /// "7 inns", "at 20.2" — the context that makes the value fair.
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case name, value, detail
        case userId = "user_id"
    }
}

struct SeasonLeaderboard: Decodable, Equatable, Identifiable {
    let code: String
    let leaders: [SeasonLeader]

    var id: String { code }

    enum CodingKeys: String, CodingKey { case code, leaders }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        leaders = try c.decodeIfPresent([SeasonLeader].self, forKey: .leaders) ?? []
    }
}

struct SeasonRecordLine: Decodable, Equatable {
    var played = 0
    var won = 0
    var lost = 0
    var tiedOrNoResult = 0

    enum CodingKeys: String, CodingKey {
        case played, won, lost
        case tiedOrNoResult = "tied_or_no_result"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        played = (try c.decodeIfPresent(Int.self, forKey: .played)) ?? 0
        won = (try c.decodeIfPresent(Int.self, forKey: .won)) ?? 0
        lost = (try c.decodeIfPresent(Int.self, forKey: .lost)) ?? 0
        tiedOrNoResult = (try c.decodeIfPresent(Int.self, forKey: .tiedOrNoResult)) ?? 0
    }

    /// Of the matches played. nil before the first, rather than "0% won".
    var winPercent: Int? {
        played > 0 ? Int((Double(won) / Double(played) * 100).rounded()) : nil
    }
}

struct ClubSeason: Decodable, Equatable {
    let clubId: UUID
    let clubName: String
    let season: Int
    /// Set once a secretary has closed it and the emails have gone.
    let closedAt: Date?
    let seasons: [Int]
    let record: SeasonRecordLine
    let players: Int
    let boards: [SeasonLeaderboard]

    enum CodingKeys: String, CodingKey {
        case season, seasons, record, players, boards
        case clubId = "club_id"
        case clubName = "club_name"
        case closedAt = "closed_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clubId = try c.decode(UUID.self, forKey: .clubId)
        clubName = (try c.decodeIfPresent(String.self, forKey: .clubName)) ?? ""
        season = try c.decode(Int.self, forKey: .season)
        closedAt = try c.decodeIfPresent(Date.self, forKey: .closedAt)
        seasons = try c.decodeIfPresent([Int].self, forKey: .seasons) ?? []
        record = try c.decodeIfPresent(SeasonRecordLine.self, forKey: .record) ?? SeasonRecordLine()
        players = (try c.decodeIfPresent(Int.self, forKey: .players)) ?? 0
        boards = try c.decodeIfPresent([SeasonLeaderboard].self, forKey: .boards) ?? []
    }
}

/// What closing the season would do, asked for before anything is sent —
/// because it cannot be taken back.
struct SeasonClosePreview: Decodable, Equatable {
    let season: Int
    let closedAt: Date?
    let members: Int
    let willEmail: Int
    let played: Int
    /// False when the server cannot send mail yet: nobody is emailed until it
    /// can. Absent from older servers, which is the same as on.
    var emailOn: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case season, members, played
        case closedAt = "closed_at"
        case willEmail = "will_email"
        case emailOn = "email_on"
    }
}

struct SeasonClosed: Decodable, Equatable {
    let season: Int
    let queued: Int
}

// MARK: - Words

/// The season in the reader's language, from the codes the API sends. The
/// same mapping as `web/src/lib/season.ts`, key for key, so a club reads the
/// same sentence on the phone as in its email and on the website.
enum SeasonWords {
    static func fmt(_ value: Double?, dp: Int = 1) -> String {
        guard let value else { return "–" }
        return String(format: "%.\(dp)f", value)
    }

    static func score(_ runs: Int?, notOut: Bool) -> String {
        guard let runs else { return "–" }
        return "\(runs)\(notOut ? "*" : "")"
    }

    /// "Top", "Second", "Third", then "No. 7" — ordinals do not pluralise, so
    /// they are words for the three that matter and a number after that.
    static func place(_ n: Int) -> String {
        switch n {
        case 1: return t("ss.place.1")
        case 2: return t("ss.place.2")
        case 3: return t("ss.place.3")
        default: return t("ss.place.n", vars: ["n": n])
        }
    }

    /// A milestone code as words: "first_fifty", "runs_250".
    static func milestone(_ code: String) -> String {
        let parts = code.split(separator: "_", maxSplits: 1).map(String.init)
        if parts.count == 2, let n = Int(parts[1]) {
            switch parts[0] {
            case "matches": return t("ss.ms.matches", vars: ["n": n])
            case "runs": return t("ss.ms.runs", vars: ["n": n])
            case "wickets": return t("ss.ms.wickets", vars: ["n": n])
            default: break
            }
        }
        switch code {
        case "first_match": return t("ss.ms.first_match")
        case "first_six": return t("ss.ms.first_six")
        case "first_fifty": return t("ss.ms.first_fifty")
        case "first_hundred": return t("ss.ms.first_hundred")
        case "first_wicket": return t("ss.ms.first_wicket")
        case "first_three_wickets": return t("ss.ms.first_three_wickets")
        case "first_five_wickets": return t("ss.ms.first_five_wickets")
        case "first_catch": return t("ss.ms.first_catch")
        case "first_player_of_match": return t("ss.ms.first_player_of_match")
        case "first_win": return t("ss.ms.first_win")
        default: return code.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// A highlight in the reader's language, from its code. The API's English
    /// is the fallback for a code this build does not know yet.
    static func highlight(_ h: GameHighlight) -> String {
        let v = h.value ?? ""
        let d = h.detail ?? ""
        let n = Int(v) ?? 0
        switch h.code {
        case "new_best_score":
            return d.isEmpty ? h.text : t("ss.hl.new_best_score", vars: ["value": v, "opposition": d])
        case "season_best_score":
            return d.isEmpty ? h.text : t("ss.hl.season_best_score", vars: ["value": v, "opposition": d])
        case "new_best_bowling":
            return d.isEmpty ? h.text : t("ss.hl.new_best_bowling", vars: ["value": v, "opposition": d])
        case "season_best_bowling":
            return d.isEmpty ? h.text : t("ss.hl.season_best_bowling", vars: ["value": v, "opposition": d])
        case "milestone":
            return t("ss.hl.milestone", vars: ["label": milestone(d)])
        case "average_up":
            return t("ss.hl.average_up", vars: ["value": v])
        case "strike_rate_up":
            return t("ss.hl.strike_rate_up", vars: ["value": v])
        case "economy_down":
            return t("ss.hl.economy_down", vars: ["value": v])
        case "more_runs":
            return t("ss.hl.more_runs", vars: ["value": v, "before": d])
        case "more_wickets":
            return t("ss.hl.more_wickets", vars: ["value": v, "before": d])
        case "club_top_runs":
            return t("ss.hl.club_top_runs", vars: ["place": place(n), "club": d])
        case "club_top_wickets":
            return t("ss.hl.club_top_wickets", vars: ["place": place(n), "club": d])
        case "consistent":
            return t("ss.hl.consistent", vars: ["value": v, "of": d])
        case "player_of_match":
            return t("ss.hl.player_of_match", count: n, vars: ["n": n])
        case "safe_hands":
            return t("ss.hl.safe_hands", vars: ["value": v])
        case "winning_side":
            return t("ss.hl.winning_side", vars: ["value": v, "of": d])
        case "turned_up":
            return t("ss.hl.turned_up", count: n, vars: ["n": n])
        default:
            return h.text
        }
    }

    /// A best or a club record, which earns a trophy rather than a tick.
    static func isTrophy(_ h: GameHighlight) -> Bool {
        h.code.hasPrefix("club_top") || h.code.contains("best")
    }

    static func best(_ code: String) -> String {
        switch code {
        case "best_score": return t("ss.best.best_score")
        case "best_bowling": return t("ss.best.best_bowling")
        case "most_sixes": return t("ss.best.most_sixes")
        case "most_catches": return t("ss.best.most_catches")
        case "best_season_runs": return t("ss.best.best_season_runs")
        case "best_season_wickets": return t("ss.best.best_season_wickets")
        default: return code.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func board(_ code: String) -> String {
        switch code {
        case "runs": return t("ss.board.runs")
        case "wickets": return t("ss.board.wickets")
        case "batting_average": return t("ss.board.batting_average")
        case "strike_rate": return t("ss.board.strike_rate")
        case "economy": return t("ss.board.economy")
        case "best_innings": return t("ss.board.best_innings")
        case "best_bowling": return t("ss.board.best_bowling")
        case "catches": return t("ss.board.catches")
        case "sixes": return t("ss.board.sixes")
        case "player_of_match": return t("ss.board.player_of_match")
        default: return code.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func battingTrend(_ trend: GameTrend?, recent: Double?) -> String? {
        guard let trend, let recent else { return nil }
        let value = fmt(recent)
        switch trend {
        case .rising: return t("ss.trend.bat_rising", vars: ["value": value])
        case .steady: return t("ss.trend.bat_steady", vars: ["value": value])
        case .quieter: return t("ss.trend.bat_quieter", vars: ["value": value])
        }
    }

    static func bowlingTrend(_ trend: GameTrend?, recent: Double?) -> String? {
        guard let trend, let recent else { return nil }
        let value = fmt(recent)
        switch trend {
        case .rising: return t("ss.trend.bowl_rising", vars: ["value": value])
        case .steady: return t("ss.trend.bowl_steady", vars: ["value": value])
        case .quieter: return t("ss.trend.bowl_quieter", vars: ["value": value])
        }
    }

    /// "3 Oct", in the reader's language.
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    static var locale: Locale { Locale(identifier: Strings.current.rawValue) }
}

// MARK: - Headline tiles

/// One of the numbers that describe the season, with last season beside it.
struct SeasonTile: Equatable, Identifiable {
    let id: String
    let label: String
    let value: String
    var sub: String?
    /// Better than last season. Only ever true or not-shown: a lower number
    /// is plain context, never a red mark against somebody.
    var up = false
    /// Last season's figure, when there is one to compare with.
    var was: String?

    /// Only the tiles that apply — nobody who never bowled is shown an
    /// economy of "–". The same choices as the web's `Headline`.
    static func headline(now: GameTotals, before: GameTotals?) -> [SeasonTile] {
        func better(_ a: Double?, _ b: Double?, higherIsBetter: Bool = true) -> Bool {
            guard let a, let b else { return false }
            return higherIsBetter ? a > b : a < b
        }
        var tiles: [SeasonTile] = [
            SeasonTile(id: "matches", label: t("ss.matches"), value: String(now.matches),
                       sub: t("ss.won_n", vars: ["n": now.won])),
        ]
        if now.battingInnings > 0 {
            let batted = before.map { $0.battingInnings > 0 } ?? false
            tiles.append(SeasonTile(
                id: "runs", label: t("ss.runs"), value: String(now.runs),
                sub: t("ss.innings_n", count: now.battingInnings, vars: ["n": now.battingInnings]),
                up: batted && now.runs > (before?.runs ?? 0),
                was: batted ? before.map { String($0.runs) } : nil
            ))
            tiles.append(SeasonTile(
                id: "avg", label: t("ss.average"), value: SeasonWords.fmt(now.battingAverage),
                sub: t("ss.best_n", vars: ["score": SeasonWords.score(now.highScore, notOut: now.highScoreNotOut)]),
                up: better(now.battingAverage, before?.battingAverage),
                was: before?.battingAverage.map { SeasonWords.fmt($0) }
            ))
            tiles.append(SeasonTile(
                id: "sr", label: t("ss.strike_rate"), value: SeasonWords.fmt(now.strikeRate),
                sub: t("ss.fours_sixes", vars: ["fours": now.fours, "sixes": now.sixes]),
                up: better(now.strikeRate, before?.strikeRate),
                was: before?.strikeRate.map { SeasonWords.fmt($0) }
            ))
        }
        if now.bowlingBalls > 0 {
            let bowled = before.map { $0.bowlingBalls > 0 } ?? false
            let sub: String
            if let best = now.bestBowling, best.wickets > 0 {
                sub = t("ss.best_n", vars: ["score": best.label])
            } else {
                sub = t("ss.overs_n", vars: ["overs": now.overs])
            }
            tiles.append(SeasonTile(
                id: "wkts", label: t("ss.wickets"), value: String(now.wickets), sub: sub,
                up: bowled && now.wickets > (before?.wickets ?? 0),
                was: bowled ? before.map { String($0.wickets) } : nil
            ))
            tiles.append(SeasonTile(
                id: "econ", label: t("ss.economy"), value: SeasonWords.fmt(now.economy, dp: 2),
                sub: t("ss.overs_n", vars: ["overs": now.overs]),
                up: better(now.economy, before?.economy, higherIsBetter: false),
                was: before?.economy.map { SeasonWords.fmt($0, dp: 2) }
            ))
        }
        let held = now.catches + now.stumpings
        if held > 0 || now.battingInnings == 0 {
            let heldBefore = before.map { $0.catches + $0.stumpings }
            tiles.append(SeasonTile(
                id: "field", label: t("ss.catches"), value: String(held),
                up: heldBefore.map { held > $0 } ?? false,
                was: heldBefore.map(String.init)
            ))
        }
        return tiles
    }
}
