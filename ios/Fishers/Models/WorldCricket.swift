import Foundation

/// A match from the wider game — an international or a domestic competition —
/// as opposed to a club fixture scored in this app.
///
/// Nothing here is decided on the phone. Which matches count as being played,
/// and what order they come in, is settled by the API so that iOS, Android and
/// the web cannot disagree about it.
struct WorldMatch: Codable, Identifiable, Hashable {
    let id: String
    let leagueName: String
    let leagueSeason: Int?

    let homeTeamName: String
    let homeTeamShort: String?
    let homeTeamLogo: String?
    let awayTeamName: String
    let awayTeamShort: String?
    let awayTeamLogo: String?

    let countryCode: String?
    let countryName: String?

    /// `T20`, `ODI` or `TEST`.
    let format: String?
    /// `SINGLE` or `MULTI` — whether it runs over more than one day.
    let dayType: String?

    let startTime: Date?
    /// Left as the feed's own `YYYY-MM-DD` string rather than a `Date`: it is
    /// a calendar day, not a moment, and turning it into one in the phone's
    /// timezone is how a match ends up filed under the wrong day.
    let startDate: String
    let endDate: String?

    /// The feed's own words: "In play", "Tea", "Stumps", "Finished".
    let state: String
    /// `live`, `pending` or `done`.
    let phase: String
    /// "Day 2 - Maiwand need 390 runs."
    let report: String?

    /// Strings rather than numbers: a Test innings reads "128 & 59/5".
    let homeScore: String?
    let homeInfo: String?
    let awayScore: String?
    let awayInfo: String?

    enum CodingKeys: String, CodingKey {
        case id, format, state, phase, report
        case leagueName = "league_name"
        case leagueSeason = "league_season"
        case homeTeamName = "home_team_name"
        case homeTeamShort = "home_team_short"
        case homeTeamLogo = "home_team_logo"
        case awayTeamName = "away_team_name"
        case awayTeamShort = "away_team_short"
        case awayTeamLogo = "away_team_logo"
        case countryCode = "country_code"
        case countryName = "country_name"
        case dayType = "day_type"
        case startTime = "start_time"
        case startDate = "start_date"
        case endDate = "end_date"
        case homeScore = "home_score"
        case homeInfo = "home_info"
        case awayScore = "away_score"
        case awayInfo = "away_info"
    }

    var isLive: Bool { phase == "live" }

    /// The feed shouts TEST; a scorecard should not.
    var formatLabel: String? {
        guard let format else { return nil }
        return format.uppercased() == "TEST" ? "Test" : format.uppercased()
    }

    /// The side with an over count against it is the side at the crease. The
    /// feed does not say so outright — it only ever fills that field in for
    /// whoever is batting.
    var homeBatting: Bool { isLive && !(homeInfo ?? "").isEmpty }
    var awayBatting: Bool { isLive && !(awayInfo ?? "").isEmpty }

    /// When it starts, in the reader's own timezone. A fixture list in UTC is
    /// a fixture list nobody can use.
    var startLabel: String? {
        guard let startTime else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = Calendar.current.isDateInToday(startTime) ? "HH:mm" : "EEE HH:mm"
        return f.string(from: startTime)
    }

    /// Two letters for a missing badge, so the row keeps its shape.
    var homeInitials: String { String((homeTeamShort ?? homeTeamName).prefix(2)).uppercased() }
    var awayInitials: String { String((awayTeamShort ?? awayTeamName).prefix(2)).uppercased() }
}

/// Everything the scores screen needs, in one response.
struct WorldScores: Codable, Hashable {
    /// False where no feed is configured — int and test, for instance. The
    /// screen says so rather than showing an empty list, which reads as
    /// breakage.
    let enabled: Bool
    /// When the feed was last read. Always shown: on the free allowance these
    /// scores are minutes rather than seconds old, and one that is quietly
    /// stale is worse than one that admits its age.
    let asOf: Date?
    let live: [WorldMatch]
    let upcoming: [WorldMatch]
    let recent: [WorldMatch]

    enum CodingKeys: String, CodingKey {
        case enabled, live, upcoming, recent
        case asOf = "as_of"
    }

    static let empty = WorldScores(enabled: false, asOf: nil, live: [], upcoming: [], recent: [])

    /// How old the scores are, said plainly. Under a minute is "just now"
    /// rather than "0 minutes ago", which reads like a bug.
    var freshness: String {
        guard let asOf else { return "not loaded yet" }
        let mins = Int(Date().timeIntervalSince(asOf) / 60)
        if mins < 1 { return "just now" }
        if mins == 1 { return "1 minute ago" }
        if mins < 60 { return "\(mins) minutes ago" }
        let hours = Int((Double(mins) / 60).rounded())
        return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
    }
}


/// One batter's line on the card.
///
/// Every type here is `World`-prefixed because this app scores its own cricket
/// too: `FallOfWicket` already exists in `Cricket/CricketTypes.swift` and means
/// a different thing. An outside feed's scorecard is not ours.
struct WorldBattingRow: Codable, Hashable, Identifiable {
    let name: String
    let runs: Int?
    let balls: Int?
    let fours: Int?
    let sixes: Int?
    let strikeRate: Double?
    /// Composed by the API: "c Kotian b Mulani", "not out", "did not bat".
    /// The conventions are fiddly enough — a catch by the bowler is "c & b", a
    /// run out names no bowler at all — that three clients would get them three
    /// different kinds of wrong.
    let howOut: String
    let notOut: Bool

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, runs, balls, fours, sixes
        case strikeRate = "strike_rate"
        case howOut = "how_out"
        case notOut = "not_out"
    }
}

struct WorldBowlingRow: Codable, Hashable, Identifiable {
    let name: String
    let overs: Double?
    let maidens: Int?
    let runs: Int?
    let wickets: Int?
    let economy: Double?

    var id: String { name }
}

struct WorldFallOfWicket: Codable, Hashable, Identifiable {
    /// Already counted from one; the feed counts from zero.
    let wicket: Int
    let runs: Int?
    let overs: Double?
    let batter: String?

    var id: Int { wicket }
}

struct WorldExtras: Codable, Hashable {
    let total: Int?
    let byes: Int?
    let legByes: Int?
    let wides: Int?
    let noBalls: Int?

    enum CodingKeys: String, CodingKey {
        case total, byes, wides
        case legByes = "leg_byes"
        case noBalls = "no_balls"
    }

    /// "(4b, 2lb, 21nb)" — only the ones that happened.
    var breakdown: String? {
        let parts = [
            byes.flatMap { $0 > 0 ? "\($0)b" : nil },
            legByes.flatMap { $0 > 0 ? "\($0)lb" : nil },
            wides.flatMap { $0 > 0 ? "\($0)w" : nil },
            noBalls.flatMap { $0 > 0 ? "\($0)nb" : nil },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

struct WorldInnings: Codable, Hashable, Identifiable {
    let teamName: String
    /// "AUS-A". What a tab is labelled with: "Australia A 1st innings" does not
    /// fit across a phone four times.
    let teamShort: String?
    let teamLogo: String?
    /// Computed by the API — runs off the bat plus extras, which is cricket's
    /// own identity for a total.
    let totalRuns: Int?
    let wickets: Int?
    let batting: [WorldBattingRow]
    let bowling: [WorldBowlingRow]
    let fallOfWickets: [WorldFallOfWicket]
    let extras: WorldExtras

    /// Two innings by the same side in a Test are two different cards, so the
    /// name alone will not do.
    var id: String { teamName + "-" + (batting.first?.name ?? "") }

    enum CodingKeys: String, CodingKey {
        case batting, bowling, extras, wickets
        case teamName = "team_name"
        case teamShort = "team_short"
        case teamLogo = "team_logo"
        case totalRuns = "total_runs"
        case fallOfWickets = "fall_of_wickets"
    }

    /// "105-7", or "105" where nobody is out.
    var score: String? {
        guard let totalRuns else { return nil }
        guard let wickets, wickets > 0 else { return "\(totalRuns)" }
        return "\(totalRuns)-\(wickets)"
    }
}

extension Array where Element == WorldInnings {
    /// A Test has four innings and two of them belong to each side, so the team
    /// name alone will not tell them apart.
    private func ordinal(at index: Int) -> (nth: Int, repeated: Bool) {
        let name = self[index].teamName
        let nth = self[0...index].filter { $0.teamName == name }.count
        return (nth, filter { $0.teamName == name }.count > 1)
    }

    /// "MWC 2nd" — a tab's label.
    func tabLabel(at index: Int) -> String {
        let inn = self[index]
        let name = inn.teamShort ?? inn.teamName
        let (nth, repeated) = ordinal(at: index)
        guard repeated else { return name }
        return "\(name) \(Self.ordinalWord(nth))"
    }

    /// "Maiwand Champions · 2nd innings" — the heading over the open card,
    /// which has the room the tab does not.
    func title(at index: Int) -> String {
        let inn = self[index]
        let (nth, repeated) = ordinal(at: index)
        guard repeated else { return inn.teamName }
        return "\(inn.teamName) · \(Self.ordinalWord(nth)) innings"
    }

    /// A side's score across the whole match: "103 & 105/7". An innings all out
    /// shows just the runs; one still going shows the wickets too.
    func sideScore(for team: String) -> String? {
        let mine = filter { $0.teamName == team && $0.totalRuns != nil }
        guard !mine.isEmpty else { return nil }
        return mine.map { inn in
            let runs = inn.totalRuns ?? 0
            return (inn.wickets ?? 0) >= 10 ? "\(runs)" : "\(runs)/\(inn.wickets ?? 0)"
        }
        .joined(separator: " & ")
    }

    private static func ordinalWord(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }
}

/// Somebody at the crease or bowling right now. `line` is composed server-side
/// — "101 (153b, 7x4, 3x6)" for a batter, "1/19 (11.6 ov)" for a bowler.
struct WorldCurrentPlayer: Codable, Hashable, Identifiable {
    let name: String
    let teamName: String?
    let line: String

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, line
        case teamName = "team_name"
    }
}

struct WorldMatchDetail: Codable, Hashable {
    let venue: String?
    let battingNow: [WorldCurrentPlayer]
    let bowlingNow: [WorldCurrentPlayer]
    let innings: [WorldInnings]

    enum CodingKeys: String, CodingKey {
        case venue, innings
        case battingNow = "batting_now"
        case bowlingNow = "bowling_now"
    }
}

/// The page's whole payload: the summary it is headed with, and the card.
struct WorldMatchDetailView: Codable, Hashable {
    let summary: WorldMatch
    /// `nil` when no scorecard has been fetched for this match — the screen
    /// shows the summary and says so rather than drawing empty tables.
    let detail: WorldMatchDetail?
    let detailAsOf: Date?

    enum CodingKeys: String, CodingKey {
        case summary, detail
        case detailAsOf = "detail_as_of"
    }

    /// How old the card is, said plainly.
    var freshness: String {
        guard let detailAsOf else { return "not loaded yet" }
        let mins = Int(Date().timeIntervalSince(detailAsOf) / 60)
        if mins < 1 { return "just now" }
        if mins == 1 { return "1 minute ago" }
        if mins < 60 { return "\(mins) minutes ago" }
        let hours = Int((Double(mins) / 60).rounded())
        return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
    }
}
