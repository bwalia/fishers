import XCTest
@testable import Fishers

/// Regression: Postgres/chrono timestamps include fractional seconds. Foundation's
/// default `.iso8601` strategy rejects them, which used to wipe Season stats on Profile.
final class SeasonStatsDecodingTests: XCTestCase {
    func testMeStatsDecodesFractionalTimestamps() throws {
        let json = """
        {
          "links": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "user_id": "22222222-2222-2222-2222-222222222222",
              "club_id": "33333333-3333-3333-3333-333333333333",
              "play_cricket_player_id": "12340001",
              "play_cricket_site_id": "1234",
              "display_name": "Demo Batter",
              "profile_url": "https://play-cricket.com/website/player_stats?site_id=1234&player_id=12340001",
              "linked_at": "2026-04-12T09:15:30.123456Z",
              "last_synced_at": "2026-09-01T18:22:01.987654Z"
            }
          ],
          "seasons": [
            {
              "id": "44444444-4444-4444-4444-444444444444",
              "user_id": "22222222-2222-2222-2222-222222222222",
              "club_id": "33333333-3333-3333-3333-333333333333",
              "team_id": null,
              "sport": "cricket",
              "season_year": 2026,
              "source": "play_cricket",
              "matches": 14,
              "runs": 412,
              "wickets": 23,
              "batting_innings": 13,
              "not_outs": 2,
              "balls_faced": 310,
              "fours": 48,
              "sixes": 9,
              "high_score": 87,
              "overs_bowled": 68.0,
              "bowling_runs": 295,
              "maidens": 7,
              "catches": 8,
              "stumpings": 0,
              "extras": { "featured": true },
              "updated_at": "2026-09-05T10:00:00.111111Z",
              "player_name": "Demo Batter",
              "club_name": "London Lords CC",
              "play_cricket_profile_url": "https://play-cricket.com/website/player_stats?site_id=1234&player_id=12340001",
              "play_cricket_player_id": "12340001",
              "batting_average": 37.45,
              "bowling_average": 12.826,
              "strike_rate": 132.9
            }
          ],
          "achievements": [
            {
              "id": "55555555-5555-5555-5555-555555555555",
              "user_id": "22222222-2222-2222-2222-222222222222",
              "achievement_code": "club_champion",
              "club_id": "33333333-3333-3333-3333-333333333333",
              "season_year": 2026,
              "awarded_at": "2026-08-20T12:00:00.500000Z",
              "evidence": { "category": "leading_run_scorer" },
              "title": "Club champion",
              "description": "Leading run scorer",
              "icon": "🏆"
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try FishersJSONDecoder.make().decode(MeStatsResponse.self, from: json)
        XCTAssertEqual(decoded.seasons.count, 1)
        XCTAssertEqual(decoded.seasons[0].runs, 412)
        XCTAssertEqual(decoded.seasons[0].wickets, 23)
        XCTAssertEqual(decoded.achievements.count, 1)
        XCTAssertEqual(decoded.links.count, 1)
        XCTAssertNotNil(decoded.links[0].linkedAt)
        XCTAssertNotNil(decoded.achievements[0].awardedAt)
        // Legacy /website/... deep links must open the real Play-Cricket home.
        XCTAssertEqual(decoded.links[0].profileURL, PlayCricketLinks.home)
        XCTAssertEqual(decoded.seasons[0].playCricketURL, PlayCricketLinks.home)
    }

    func testDefaultIso8601StrategyRejectsFractionalSeconds() {
        let raw = "\"2026-04-12T09:15:30.123456Z\"".data(using: .utf8)!
        let plain = JSONDecoder()
        plain.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try plain.decode(Date.self, from: raw))
    }

    func testFishersDecoderAcceptsFractionalSeconds() throws {
        let raw = "\"2026-04-12T09:15:30.123456Z\"".data(using: .utf8)!
        let date = try FishersJSONDecoder.make().decode(Date.self, from: raw)
        XCTAssertEqual(date.timeIntervalSince1970, 1_776_024_930.123456, accuracy: 0.001)
    }

    func testClubBoardDecodesExtraSiteFields() throws {
        let json = """
        {
          "club": {
            "id": "66666666-6666-6666-6666-666666666666",
            "club_id": "33333333-3333-3333-3333-333333333333",
            "team_id": null,
            "sport": "cricket",
            "season_year": 2026,
            "source": "play_cricket",
            "matches_played": 18,
            "wins": 11,
            "losses": 5,
            "draws": 2,
            "no_results": 0,
            "runs_for": 2401,
            "runs_against": 2105,
            "wickets_taken": 140,
            "wickets_lost": 118,
            "extras": {},
            "updated_at": "2026-09-05T10:00:00.222222Z"
          },
          "play_cricket": {
            "club_id": "33333333-3333-3333-3333-333333333333",
            "site_id": "1234",
            "site_name": "London Lords CC",
            "public_url": "https://play-cricket.com/website/results?site_id=1234",
            "api_token_env": "PLAY_CRICKET_API_TOKEN",
            "last_synced_at": "2026-09-01T18:22:01.987654Z",
            "created_at": "2026-03-01T08:00:00.000001Z"
          },
          "top_batters": [],
          "top_bowlers": []
        }
        """.data(using: .utf8)!

        let board = try FishersJSONDecoder.make().decode(ClubSeasonBoard.self, from: json)
        XCTAssertEqual(board.club.wins, 11)
        XCTAssertEqual(board.playCricket?.siteId, "1234")
        XCTAssertNotNil(board.playCricket?.lastSyncedAt)
    }
}
