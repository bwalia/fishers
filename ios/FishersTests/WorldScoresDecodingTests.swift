import XCTest
@testable import Fishers

/// `GET /cricket/world-scores` is the one screen whose content comes from
/// outside this project, by way of our own database. Two things can quietly
/// break it: the API renaming a field, and a score arriving as something other
/// than the string cricket actually needs ("128 & 59/5" is not a number). So
/// the payload is pinned to a real response.
final class WorldScoresDecodingTests: XCTestCase {
    /// Captured from `GET /api/v1/cricket/world-scores` against a local API
    /// holding real feed data.
    private let captured = """
    {
      "enabled": true,
      "as_of": "2026-09-29T10:35:54.649542Z",
      "live": [
        {
          "id": "54297112",
          "league_name": "Ahmad Shah Abdali 4-day Tournament",
          "league_season": 2026,
          "home_team_name": "Maiwand Champions",
          "home_team_short": "MWC",
          "home_team_logo": "https://highlightly.net/cricket/images/teams/48698372.png",
          "away_team_name": "Pamir Legends",
          "away_team_short": "PAL",
          "away_team_logo": "https://highlightly.net/cricket/images/teams/45984437.png",
          "country_code": "AF",
          "country_name": "Afghanistan",
          "format": "TEST",
          "day_type": "MULTI",
          "start_time": "2026-09-28T05:00:00Z",
          "start_date": "2026-09-28",
          "end_date": "2026-10-01",
          "state": "In play",
          "phase": "live",
          "report": "Day 2 - Maiwand need 390 runs.",
          "home_score": "103 & 15/1",
          "home_info": "4 ov, T:405",
          "away_score": "175 & 332",
          "away_info": null
        }
      ],
      "upcoming": [
        {
          "id": "54314542",
          "league_name": "Big Bash League",
          "league_season": 2026,
          "home_team_name": "Melbourne Renegades",
          "home_team_short": "MR",
          "home_team_logo": null,
          "away_team_name": "Melbourne Stars",
          "away_team_short": "MS",
          "away_team_logo": null,
          "country_code": "AU",
          "country_name": "Australia",
          "format": "T20",
          "day_type": "SINGLE",
          "start_time": "2026-09-29T16:00:00Z",
          "start_date": "2026-09-29",
          "end_date": "2026-09-29",
          "state": "Scheduled",
          "phase": "pending",
          "report": null,
          "home_score": null,
          "home_info": null,
          "away_score": null,
          "away_info": null
        }
      ],
      "recent": []
    }
    """

    private func decode(_ json: String) throws -> WorldScores {
        try FishersJSONDecoder.make().decode(WorldScores.self, from: Data(json.utf8))
    }

    func testDecodesTheResponse() throws {
        let scores = try decode(captured)
        XCTAssertTrue(scores.enabled)
        XCTAssertEqual(scores.live.count, 1)
        XCTAssertEqual(scores.upcoming.count, 1)
        XCTAssertTrue(scores.recent.isEmpty)
        XCTAssertNotNil(scores.asOf)
    }

    /// Scores are strings because cricket's are: a Test innings reads
    /// "103 & 15/1" and no number will hold that.
    func testScoresStayStrings() throws {
        let m = try decode(captured).live[0]
        XCTAssertEqual(m.homeScore, "103 & 15/1")
        XCTAssertEqual(m.awayScore, "175 & 332")
        XCTAssertEqual(m.homeInfo, "4 ov, T:405")
        XCTAssertNil(m.awayInfo)
    }

    /// The side with an over count against it is the side at the crease. It is
    /// the only signal the feed gives, and it is what the screen bolds.
    func testTheBattingSideIsTheOneWithAnOverCount() throws {
        let m = try decode(captured).live[0]
        XCTAssertTrue(m.homeBatting)
        XCTAssertFalse(m.awayBatting)
    }

    /// A match that is not live has nobody at the crease, whatever else the
    /// row happens to hold.
    func testNobodyIsBattingInAMatchThatHasNotStarted() throws {
        let next = try decode(captured).upcoming[0]
        XCTAssertFalse(next.isLive)
        XCTAssertFalse(next.homeBatting)
        XCTAssertFalse(next.awayBatting)
    }

    /// The start date is a calendar day, not a moment. Decoding it as a `Date`
    /// would shift it by a timezone and file a match under the wrong day.
    func testTheStartDateStaysACalendarDay() throws {
        let m = try decode(captured).live[0]
        XCTAssertEqual(m.startDate, "2026-09-28")
        XCTAssertEqual(m.endDate, "2026-10-01")
    }

    func testFormatIsTitleCasedForReading() throws {
        let scores = try decode(captured)
        XCTAssertEqual(scores.live[0].formatLabel, "Test")
        XCTAssertEqual(scores.upcoming[0].formatLabel, "T20")
    }

    /// A missing badge must stay missing rather than become an empty URL the
    /// row would try to load.
    func testAMissingBadgeFallsBackToInitials() throws {
        let next = try decode(captured).upcoming[0]
        XCTAssertNil(next.homeTeamLogo)
        XCTAssertEqual(next.homeInitials, "MR")
        XCTAssertEqual(next.awayInitials, "MS")
    }

    /// Off is a state the screen has to render, not an error: int and test run
    /// without a feed key on purpose.
    func testADisabledFeedDecodes() throws {
        let scores = try decode(
            #"{"enabled":false,"as_of":null,"live":[],"upcoming":[],"recent":[]}"#
        )
        XCTAssertFalse(scores.enabled)
        XCTAssertNil(scores.asOf)
        XCTAssertEqual(scores.freshness, "not loaded yet")
    }

    func testFreshnessReadsAsEnglish() {
        let at = { (mins: Int) in
            WorldScores(
                enabled: true,
                asOf: Date().addingTimeInterval(Double(-mins) * 60),
                live: [], upcoming: [], recent: []
            ).freshness
        }
        // Under a minute is "just now", never "0 minutes ago" — which reads
        // like a bug rather than a fresh score.
        XCTAssertEqual(at(0), "just now")
        XCTAssertEqual(at(1), "1 minute ago")
        XCTAssertEqual(at(7), "7 minutes ago")
        XCTAssertEqual(at(60), "1 hour ago")
        XCTAssertEqual(at(180), "3 hours ago")
    }
}
