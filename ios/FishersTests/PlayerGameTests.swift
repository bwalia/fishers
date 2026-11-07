import XCTest
@testable import Fishers

/// The season screens decode what the API actually sends — the fixtures are
/// real responses from `/me/game`, `/clubs/{id}/season` and the close preview
/// — and say it in the dictionary's words rather than the API's English.
final class PlayerGameTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
            "\(name).json is missing from the test bundle"
        )
        return try Data(contentsOf: url)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try FishersJSONDecoder.make().decode(T.self, from: fixture(name))
    }

    override func tearDown() {
        Strings.setCurrent(.en)
        super.tearDown()
    }

    // MARK: Decoding

    func testARealPlayerGameDecodes() throws {
        let game = try decode(PlayerGame.self, "player_game")
        XCTAssertEqual(game.name, "Gary Tucker")
        XCTAssertEqual(game.season, 2026)
        XCTAssertEqual(game.seasons, [2026])
        XCTAssertEqual(game.totals.matches, 7)
        XCTAssertEqual(game.totals.runs, 281)
        XCTAssertEqual(game.totals.battingAverage, 40.1)
        XCTAssertNil(game.totals.economy)
        XCTAssertNil(game.totals.bestBowling)
        XCTAssertNil(game.previous)
        XCTAssertEqual(game.form.matches.count, 7)
        XCTAssertEqual(game.form.matches.first?.opposition, "Abbots Langley")
        XCTAssertEqual(game.form.battingTrend, .steady)
        XCTAssertEqual(game.form.recentBattingAverage, 45.2)
        XCTAssertNil(game.form.bowlingTrend)
        XCTAssertEqual(game.bests.map(\.code), ["best_score", "most_sixes", "most_catches"])
        XCTAssertTrue(game.bests.allSatisfy(\.thisSeason))
        XCTAssertEqual(game.milestones.count, 7)
        XCTAssertEqual(game.clubRank?.runs, 1)
        XCTAssertNil(game.clubRank?.wickets)
        XCTAssertEqual(game.clubRank?.players, 22)
        XCTAssertEqual(game.highlights.map(\.code), ["season_best_score", "milestone", "club_top_runs", "consistent"])
    }

    func testABowlersGameDecodesFiguresAndTrend() throws {
        let game = try decode(PlayerGame.self, "player_game_bowler")
        XCTAssertGreaterThan(game.totals.bowlingBalls, 0)
        XCTAssertEqual(game.totals.bestBowling, GameFigures(wickets: 3, runs: 21))
        XCTAssertEqual(game.form.bowlingTrend, .rising)
    }

    func testSomebodyWhoHasNotPlayedDecodesToTheEmptyState() throws {
        let game = try decode(PlayerGame.self, "player_game_empty")
        XCTAssertEqual(game.totals.matches, 0)
        XCTAssertTrue(game.form.matches.isEmpty)
        XCTAssertNil(game.clubRank)
        XCTAssertTrue(game.highlights.isEmpty)
    }

    func testARealClubSeasonDecodes() throws {
        let club = try decode(ClubSeason.self, "club_season")
        XCTAssertEqual(club.clubName, "Hemel Hempstead Town CC")
        XCTAssertEqual(club.season, 2026)
        // Fractional seconds from Postgres, which plain `.iso8601` refuses.
        XCTAssertNotNil(club.closedAt)
        XCTAssertEqual(club.record.played, 8)
        XCTAssertEqual(club.record.won, 4)
        XCTAssertEqual(club.record.tiedOrNoResult, 1)
        XCTAssertEqual(club.record.winPercent, 50)
        XCTAssertEqual(club.players, 22)
        XCTAssertEqual(club.boards.count, 10)
        XCTAssertEqual(club.boards.first?.code, "runs")
        XCTAssertEqual(club.boards.first?.leaders.first?.value, "281")
        XCTAssertEqual(club.boards.first?.leaders.first?.detail, "7 inns")
        // Every board has words in this build.
        for board in club.boards {
            XCTAssertFalse(SeasonWords.board(board.code).contains("_"), board.code)
        }
    }

    func testTheClosePreviewDecodes() throws {
        let preview = try decode(SeasonClosePreview.self, "season_close_preview")
        XCTAssertEqual(preview.season, 2026)
        XCTAssertEqual(preview.members, 34)
        XCTAssertEqual(preview.willEmail, 33)
        XCTAssertEqual(preview.played, 22)
    }

    /// A field the server adds, or one it stops sending, is not a broken page.
    func testAMinimalGameStillDecodes() throws {
        let json = """
        {"user_id":"\(UUID().uuidString)","name":"New","season":2027,"surprise":true,
         "totals":{"matches":0},"form":{"matches":[],"batting_trend":"sideways"}}
        """
        let game = try FishersJSONDecoder.make().decode(PlayerGame.self, from: Data(json.utf8))
        XCTAssertEqual(game.totals.runs, 0)
        XCTAssertEqual(game.totals.overs, "0.0")
        XCTAssertNil(game.form.battingTrend, "a trend this build cannot name is no trend")
        XCTAssertTrue(game.bests.isEmpty)
    }

    // MARK: Words

    func testHighlightsAreTheDictionarysWordsNotTheAPIs() throws {
        let game = try decode(PlayerGame.self, "player_game")
        let said = game.highlights.map(SeasonWords.highlight)
        XCTAssertEqual(said, [
            "Best score of the season: 79 against Radlett.",
            "Milestone reached: 250 career runs.",
            "Top for runs at Hemel Hempstead Town CC this season.",
            "You reached double figures in 7 of 7 innings.",
        ])
        // In English the dictionary and the API agree, which is the point.
        XCTAssertEqual(said, game.highlights.map(\.text))
    }

    func testHighlightsComeBackInPunjabi() throws {
        let game = try decode(PlayerGame.self, "player_game")
        Strings.setCurrent(.pa)
        for h in game.highlights {
            let said = SeasonWords.highlight(h)
            XCTAssertNotEqual(said, h.text, "\(h.code) fell back to the API's English")
            XCTAssertFalse(said.contains("{"), "a placeholder survived in \(said)")
            XCTAssertTrue(
                said.unicodeScalars.contains { (0x0A00...0x0A7F).contains($0.value) },
                "\(h.code) -> \(said) is not Gurmukhi"
            )
        }
    }

    func testHighlightCodesWithPluralsAndPlaces() {
        XCTAssertEqual(
            SeasonWords.highlight(GameHighlight(code: "player_of_match", text: "", value: "1")),
            "Player of the match once this season."
        )
        XCTAssertEqual(
            SeasonWords.highlight(GameHighlight(code: "player_of_match", text: "", value: "3")),
            "Player of the match 3 times this season."
        )
        XCTAssertEqual(
            SeasonWords.highlight(GameHighlight(code: "club_top_wickets", text: "", value: "2", detail: "Hemel")),
            "Second for wickets at Hemel this season."
        )
        XCTAssertEqual(
            SeasonWords.highlight(GameHighlight(code: "more_runs", text: "", value: "300", detail: "120")),
            "300 runs this season, up from 120 last season."
        )
        XCTAssertEqual(
            SeasonWords.highlight(GameHighlight(code: "turned_up", text: "", value: "4")),
            "You played 4 matches this season — every game counts towards the next."
        )
        XCTAssertEqual(SeasonWords.place(7), "No. 7")
    }

    /// A code this build has not been taught reads as the API's sentence,
    /// and a best without an opposition does not print "against ".
    func testUnknownOrIncompleteHighlightsFallBackToTheAPIText() {
        XCTAssertEqual(
            SeasonWords.highlight(GameHighlight(code: "brand_new_code", text: "Something good happened.")),
            "Something good happened."
        )
        XCTAssertEqual(
            SeasonWords.highlight(GameHighlight(code: "new_best_score", text: "A new best score: 50.", value: "50")),
            "A new best score: 50."
        )
    }

    func testMilestoneLabels() {
        XCTAssertEqual(SeasonWords.milestone("runs_250"), "250 career runs")
        XCTAssertEqual(SeasonWords.milestone("wickets_10"), "10 career wickets")
        XCTAssertEqual(SeasonWords.milestone("matches_50"), "50 matches")
        XCTAssertEqual(SeasonWords.milestone("first_fifty"), "First fifty")
        XCTAssertEqual(SeasonWords.milestone("first_something_new"), "first something new")
    }

    // MARK: Tiles

    /// Somebody who never bowled is not shown an economy of "–".
    func testABatterGetsNoBowlingTiles() throws {
        let game = try decode(PlayerGame.self, "player_game")
        let ids = SeasonTile.headline(now: game.totals, before: game.previous).map(\.id)
        XCTAssertEqual(ids, ["matches", "runs", "avg", "sr", "field"])
    }

    /// Up is marked; down is plain context, with last season beside it.
    func testOnlyImprovementIsMarked() throws {
        var now = GameTotals()
        now.matches = 5
        now.battingInnings = 5
        now.runs = 100
        now.battingAverage = 20
        now.strikeRate = 90
        now.bowlingBalls = 60
        now.wickets = 3
        now.economy = 5.5
        var before = now
        before.runs = 150
        before.battingAverage = 15
        before.economy = 6.0
        before.wickets = 3
        let tiles = Dictionary(uniqueKeysWithValues: SeasonTile.headline(now: now, before: before).map { ($0.id, $0) })
        XCTAssertEqual(tiles["runs"]?.up, false)
        XCTAssertEqual(tiles["runs"]?.was, "150")
        XCTAssertEqual(tiles["avg"]?.up, true)
        XCTAssertEqual(tiles["econ"]?.up, true, "fewer runs an over is better")
        XCTAssertEqual(tiles["wkts"]?.up, false, "the same is not an improvement")
        XCTAssertEqual(tiles["sr"]?.up, false)
    }

    // MARK: Push

    func testTheSeasonClosedPushOpensThatSeason() {
        let club = UUID()
        let link = SeasonLink([
            "url": "/stats?season=2026&club=\(club.uuidString)",
            "club_id": club.uuidString,
            "season": NSNumber(value: 2026),
            "tag": "season:\(club.uuidString):2026",
        ])
        XCTAssertEqual(link?.season, 2026)
        XCTAssertEqual(link?.clubId, club)
        // Without the url, the two fields are enough.
        XCTAssertEqual(SeasonLink(["season": NSNumber(value: 2025)])?.season, 2025)
        // Somebody else's push is left alone.
        XCTAssertNil(SeasonLink(["conversation_id": UUID().uuidString]))
        XCTAssertNil(SeasonLink(url: "/events/123"))
        XCTAssertEqual(SeasonLink(url: "https://example.org/stats?tab=club&season=2026")?.clubTab, true)
        XCTAssertEqual(link?.clubTab, false)
    }
}
