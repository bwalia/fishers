import XCTest
@testable import Fishers

/// A career average is the sum of the runs over the sum of the dismissals.
/// It is *not* the mean of the seasons' own averages — that gives a different
/// number, and it is the mistake every homemade stats page makes.
final class CareerTotalsTests: XCTestCase {

    private func season(
        year: Int,
        matches: Int = 0,
        runs: Int = 0,
        wickets: Int = 0,
        innings: Int = 0,
        notOuts: Int = 0,
        ballsFaced: Int = 0,
        highScore: Int? = nil,
        overs: Double = 0,
        bowlingRuns: Int = 0,
        maidens: Int = 0,
        catches: Int = 0
    ) -> PlayerSeasonStats {
        PlayerSeasonStats(
            id: UUID(), userId: UUID(), clubId: nil, teamId: nil, sport: "cricket",
            seasonYear: year, source: "manual", matches: matches, runs: runs,
            wickets: wickets, battingInnings: innings, notOuts: notOuts,
            ballsFaced: ballsFaced, fours: 0, sixes: 0, highScore: highScore,
            oversBowled: overs, bowlingRuns: bowlingRuns, maidens: maidens,
            catches: catches, stumpings: 0, playerName: nil, clubName: nil,
            playCricketProfileUrl: nil, playCricketPlayerId: nil,
            battingAverage: nil, bowlingAverage: nil, strikeRate: nil
        )
    }

    func testTheCareerAverageIsNotTheMeanOfTheSeasonAverages() {
        // 100 from 1 dismissal, then 10 from 9. Season averages are 100 and
        // 1.11, whose mean is 50.56 — a number this player never had.
        let seasons = [
            season(year: 2025, runs: 100, innings: 1, notOuts: 0),
            season(year: 2026, runs: 10, innings: 9, notOuts: 0),
        ]
        let totals = Totals(seasons)

        XCTAssertEqual(totals.runs, 110)
        XCTAssertEqual(totals.battingAverage ?? 0, 11.0, accuracy: 0.0001)
    }

    func testANeverDismissedPlayerHasNoAverageRatherThanZero() {
        let totals = Totals([season(year: 2026, runs: 42, innings: 3, notOuts: 3)])
        XCTAssertNil(totals.battingAverage, "0 dismissals is no average, not an average of 0")
        XCTAssertNil(Totals([]).strikeRate)
        XCTAssertNil(Totals([]).bowlingAverage)
        XCTAssertNil(Totals([]).economy)
    }

    func testBowlingFiguresSumAcrossSeasons() {
        let seasons = [
            season(year: 2025, wickets: 17, overs: 52.4, bowlingRuns: 233, maidens: 5),
            season(year: 2026, wickets: 9, overs: 38.0, bowlingRuns: 171, maidens: 3),
        ]
        let totals = Totals(seasons)

        XCTAssertEqual(totals.wickets, 26)
        XCTAssertEqual(totals.overs, 90.4, accuracy: 0.0001)
        XCTAssertEqual(totals.bowlingAverage ?? 0, 404.0 / 26.0, accuracy: 0.0001)
        XCTAssertEqual(totals.economy ?? 0, 404.0 / 90.4, accuracy: 0.0001)
    }

    func testStrikeRateIsRunsPerHundredBalls() {
        let totals = Totals([season(year: 2026, runs: 75, ballsFaced: 50)])
        XCTAssertEqual(totals.strikeRate ?? 0, 150.0, accuracy: 0.0001)
    }

    /// Catches and stumpings are one number to a club player, and the profile
    /// shows them as one.
    func testCatchesIncludeStumpings() {
        var s = season(year: 2026, catches: 6)
        s = PlayerSeasonStats(
            id: s.id, userId: s.userId, clubId: nil, teamId: nil, sport: s.sport,
            seasonYear: s.seasonYear, source: s.source, matches: 0, runs: 0, wickets: 0,
            battingInnings: 0, notOuts: 0, ballsFaced: 0, fours: 0, sixes: 0,
            highScore: nil, oversBowled: 0, bowlingRuns: 0, maidens: 0,
            catches: 6, stumpings: 2, playerName: nil, clubName: nil,
            playCricketProfileUrl: nil, playCricketPlayerId: nil,
            battingAverage: nil, bowlingAverage: nil, strikeRate: nil
        )
        XCTAssertEqual(Totals([s]).catches, 8)
    }
}
