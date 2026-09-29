import XCTest
@testable import Fishers

/// The scorecard page's payload, pinned to a real four-innings Test.
///
/// Four innings is the case that matters: two of them belong to each side, so
/// the team name alone will not tell them apart, and everything the tabs say
/// depends on getting that right.
final class WorldMatchDetailDecodingTests: XCTestCase {
    /// Captured from `GET /api/v1/cricket/world-scores/54297112`.
    private let captured = """
{
  "summary": {
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
    "report": "Day 2 - Maiwand need 296 runs.",
    "home_score": "103 & 109/7",
    "home_info": "24 ov, T:405",
    "away_score": "175 & 332",
    "away_info": null
  },
  "detail": {
    "venue": null,
    "batting_now": [
      {
        "name": "Asghar Atal",
        "team_name": "Maiwand Champions",
        "line": "0"
      }
    ],
    "bowling_now": [
      {
        "name": "Nasim Mangal",
        "team_name": "Pamir Legends",
        "line": "3/33 (8.2 ov)"
      }
    ],
    "innings": [
      {
        "team_name": "Pamir Legends",
        "team_short": "PAL",
        "team_logo": "https://highlightly.net/cricket/images/teams/45984437.png",
        "total_runs": 175,
        "wickets": 10,
        "batting": [
          {
            "name": "Usman Noori",
            "runs": 0,
            "balls": 5,
            "fours": 0,
            "sixes": 0,
            "strike_rate": 0.0,
            "how_out": "lbw b Bilal Sami",
            "not_out": false
          },
          {
            "name": "Jalat Khan",
            "runs": 12,
            "balls": 22,
            "fours": 1,
            "sixes": 0,
            "strike_rate": 54.54,
            "how_out": "c Shams Ur Rahman b Bilal Sami",
            "not_out": false
          }
        ],
        "bowling": [
          {
            "name": "Nijat Masood",
            "overs": 6.0,
            "maidens": 1,
            "runs": 30,
            "wickets": 0,
            "economy": 5.0
          }
        ],
        "fall_of_wickets": [
          {
            "wicket": 1,
            "runs": 3,
            "overs": 1.3,
            "batter": "Usman Noori"
          }
        ],
        "extras": {
          "total": 2,
          "byes": 0,
          "leg_byes": 2,
          "wides": 0,
          "no_balls": 0
        }
      },
      {
        "team_name": "Maiwand Champions",
        "team_short": "MWC",
        "team_logo": "https://highlightly.net/cricket/images/teams/48698372.png",
        "total_runs": 103,
        "wickets": 10,
        "batting": [
          {
            "name": "Asghar Atal",
            "runs": 13,
            "balls": 7,
            "fours": 2,
            "sixes": 0,
            "strike_rate": 185.71,
            "how_out": "b Nasim Mangal",
            "not_out": false
          },
          {
            "name": "Khalid Ahmadzai",
            "runs": 0,
            "balls": 1,
            "fours": 0,
            "sixes": 0,
            "strike_rate": 0.0,
            "how_out": "lbw b Fareed Ahmad",
            "not_out": false
          }
        ],
        "bowling": [
          {
            "name": "Fareed Ahmad",
            "overs": 10.0,
            "maidens": 0,
            "runs": 51,
            "wickets": 5,
            "economy": 5.1
          }
        ],
        "fall_of_wickets": [
          {
            "wicket": 1,
            "runs": 7,
            "overs": 0.3,
            "batter": "Khalid Ahmadzai"
          }
        ],
        "extras": {
          "total": 10,
          "byes": 4,
          "leg_byes": 4,
          "wides": 0,
          "no_balls": 2
        }
      },
      {
        "team_name": "Pamir Legends",
        "team_short": "PAL",
        "team_logo": "https://highlightly.net/cricket/images/teams/45984437.png",
        "total_runs": 332,
        "wickets": 10,
        "batting": [
          {
            "name": "Usman Noori",
            "runs": 10,
            "balls": 12,
            "fours": 1,
            "sixes": 0,
            "strike_rate": 83.33,
            "how_out": "b Bilal Sami",
            "not_out": false
          },
          {
            "name": "Jalat Khan",
            "runs": 32,
            "balls": 46,
            "fours": 4,
            "sixes": 0,
            "strike_rate": 69.56,
            "how_out": "c Bilal Sami b Abdullah Tarakhail",
            "not_out": false
          }
        ],
        "bowling": [
          {
            "name": "Nijat Masood",
            "overs": 20.0,
            "maidens": 0,
            "runs": 108,
            "wickets": 2,
            "economy": 5.4
          }
        ],
        "fall_of_wickets": [
          {
            "wicket": 1,
            "runs": 17,
            "overs": 3.3,
            "batter": "Usman Noori"
          }
        ],
        "extras": {
          "total": 18,
          "byes": 9,
          "leg_byes": 9,
          "wides": 0,
          "no_balls": 0
        }
      },
      {
        "team_name": "Maiwand Champions",
        "team_short": "MWC",
        "team_logo": "https://highlightly.net/cricket/images/teams/48698372.png",
        "total_runs": 110,
        "wickets": 9,
        "batting": [
          {
            "name": "Khalid Ahmadzai",
            "runs": 8,
            "balls": 15,
            "fours": 1,
            "sixes": 0,
            "strike_rate": 53.33,
            "how_out": "c Fareed Ahmad b Nasim Mangal",
            "not_out": false
          },
          {
            "name": "Majeed Alam",
            "runs": 0,
            "balls": 3,
            "fours": 0,
            "sixes": 0,
            "strike_rate": 0.0,
            "how_out": "lbw b Fareed Ahmad",
            "not_out": false
          }
        ],
        "bowling": [
          {
            "name": "Fareed Ahmad",
            "overs": 9.0,
            "maidens": 0,
            "runs": 48,
            "wickets": 2,
            "economy": 5.33
          }
        ],
        "fall_of_wickets": [
          {
            "wicket": 1,
            "runs": 3,
            "overs": 0.4,
            "batter": "Majeed Alam"
          }
        ],
        "extras": {
          "total": 6,
          "byes": 0,
          "leg_byes": 5,
          "wides": 0,
          "no_balls": 1
        }
      }
    ]
  },
  "detail_as_of": "2026-09-29T12:23:59.704171183Z"
}
"""

    private func decode() throws -> WorldMatchDetailView {
        try FishersJSONDecoder.make().decode(WorldMatchDetailView.self, from: Data(captured.utf8))
    }

    func testDecodesTheWholePage() throws {
        let v = try decode()
        XCTAssertNotNil(v.detail)
        XCTAssertEqual(v.detail?.innings.count, 4)
        XCTAssertNotNil(v.detailAsOf)
    }

    /// Two innings each, so a label has to carry the ordinal or two tabs read
    /// identically.
    func testTabLabelsTellTheTwoInningsOfASideApart() throws {
        let inns = try XCTUnwrap(try decode().detail?.innings)
        XCTAssertEqual(inns.tabLabel(at: 0), "PAL 1st")
        XCTAssertEqual(inns.tabLabel(at: 1), "MWC 1st")
        XCTAssertEqual(inns.tabLabel(at: 2), "PAL 2nd")
        XCTAssertEqual(inns.tabLabel(at: 3), "MWC 2nd")
    }

    /// The heading has the room the tab does not.
    func testTheHeadingSaysTheNameInFull() throws {
        let inns = try XCTUnwrap(try decode().detail?.innings)
        XCTAssertEqual(inns.title(at: 0), "Pamir Legends · 1st innings")
        XCTAssertEqual(inns.title(at: 3), "Maiwand Champions · 2nd innings")
    }

    /// A side's score across the match. An innings all out shows just the runs;
    /// one still going shows the wickets too — which is how the feed writes it.
    func testASidesScoreReadsAcrossBothItsInnings() throws {
        let inns = try XCTUnwrap(try decode().detail?.innings)
        XCTAssertEqual(inns.sideScore(for: "Pamir Legends"), "175 & 332")
        XCTAssertEqual(inns.sideScore(for: "Maiwand Champions"), "103 & 110/9")
        XCTAssertNil(inns.sideScore(for: "Nobody CC"))
    }

    func testAnInningsKnowsItsOwnScore() throws {
        let inns = try XCTUnwrap(try decode().detail?.innings)
        XCTAssertEqual(inns[0].score, "175-10")
        XCTAssertEqual(inns[3].score, "110-9")
    }

    /// The dismissal arrives already written. If it ever becomes parts again,
    /// three clients start inventing three different phrasings.
    func testTheDismissalIsAComposedPhrase() throws {
        let batting = try XCTUnwrap(try decode().detail?.innings.flatMap { $0.batting })
        XCTAssertFalse(batting.isEmpty)
        XCTAssertTrue(batting.allSatisfy { !$0.howOut.isEmpty })
    }

    /// "did not bat" is not "not out", and the bottom of a card is where it shows.
    func testNotOutAndDidNotBatAreDifferent() throws {
        let batting = try XCTUnwrap(try decode().detail?.innings.flatMap { $0.batting })
        for row in batting where row.howOut == "did not bat" {
            XCTAssertFalse(row.notOut)
            XCTAssertNil(row.runs)
        }
        for row in batting where row.notOut {
            XCTAssertEqual(row.howOut, "not out")
        }
    }

    /// The crease lines are composed server-side too, for the same reason.
    func testTheCreaseLinesArriveReadyToPrint() throws {
        let d = try XCTUnwrap(try decode().detail)
        XCTAssertFalse(d.battingNow.first?.line.isEmpty ?? true)
        XCTAssertTrue(d.bowlingNow.first?.line.contains("ov") ?? false)
    }

    func testExtrasBreakDownIntoWordsOrNothing() throws {
        let extras = try XCTUnwrap(try decode().detail?.innings.first?.extras)
        XCTAssertNotNil(extras.total)
        // Never an empty pair of brackets.
        if let breakdown = extras.breakdown {
            XCTAssertFalse(breakdown.isEmpty)
        }
    }

    /// A match nobody has opened yet has no card, and that is not an error.
    ///
    /// The summary is cut out of the captured payload rather than re-encoded
    /// from a decoded one: a plain `JSONEncoder` writes `start_time` as a
    /// number, which is not what the API sends and not what we decode.
    func testAMatchWithNoScorecardDecodes() throws {
        let marker = "\"detail\": {"
        let start = try XCTUnwrap(captured.range(of: marker))
        let tail = try XCTUnwrap(captured.range(of: "\"detail_as_of\""))
        // Both go: the API sets the card and its age from the same value, so a
        // payload with one and not the other is a state it never sends.
        let stripped = captured
            .replacingCharacters(in: start.lowerBound..<tail.lowerBound, with: "\"detail\": null,\n  ")
            .replacingOccurrences(
                of: #""detail_as_of": "[^"]*""#,
                with: #""detail_as_of": null"#,
                options: .regularExpression
            )
        let v = try FishersJSONDecoder.make()
            .decode(WorldMatchDetailView.self, from: Data(stripped.utf8))
        XCTAssertNil(v.detail)
        XCTAssertEqual(v.freshness, "not loaded yet")
    }
}
