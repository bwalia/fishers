import XCTest
@testable import Fishers

/// The Home overview reads `/cricket/fixtures`, whose rows carry snake_case keys
/// and fractional-second timestamps. A decode failure there empties the whole
/// screen rather than one row, so the payload is pinned to a real response.
final class CricketFixtureDecodingTests: XCTestCase {
    /// Copied from `GET /api/v1/cricket/fixtures?state=live` against a seeded
    /// local API — including the row that is live without a score, which is a
    /// match still picking its XI.
    private let json = """
    {
      "has_more": false,
      "page": 1,
      "per_page": 20,
      "total": 2,
      "items": [
        {
          "event_id": "7aabb058-cce2-44f6-bcd6-466a55f10747",
          "club_id": "a1f63def-c9c9-4bf0-8ee1-6f375a59d402",
          "title": "Lords vs Hemel — live",
          "start_at": "2026-09-01T21:37:55.590797Z",
          "event_status": "scheduled",
          "match_id": "b19e7f6b-75ad-47b8-9d19-14932c99ad78",
          "match_status": "live",
          "home_name": "Lords",
          "away_name": "Hemel",
          "has_scorer": true,
          "score": "20/1 (1.2 ov)",
          "result": null
        },
        {
          "event_id": "3ed0a459-511d-485d-ab5b-42246b78e613",
          "club_id": "a1f63def-c9c9-4bf0-8ee1-6f375a59d402",
          "title": "Saturday League",
          "start_at": "2026-09-05T12:00:00Z",
          "event_status": "scheduled",
          "match_id": "9c1f7e2a-0000-4000-8000-00000000abcd",
          "match_status": "selecting_xi",
          "home_name": null,
          "away_name": null,
          "has_scorer": true,
          "score": null,
          "result": null
        }
      ]
    }
    """

    func testFixturePageDecodes() throws {
        let page = try FishersJSONDecoder.make()
            .decode(APIPage<CricketFixtureRow>.self, from: Data(json.utf8))

        XCTAssertEqual(page.total, 2)
        XCTAssertEqual(page.perPage, 20)
        XCTAssertFalse(page.hasMore)
        XCTAssertEqual(page.items.count, 2)
    }

    func testLiveRowCarriesTheScore() throws {
        let page = try FishersJSONDecoder.make()
            .decode(APIPage<CricketFixtureRow>.self, from: Data(json.utf8))
        let row = try XCTUnwrap(page.items.first)

        XCTAssertEqual(row.sides, "Lords v Hemel")
        XCTAssertEqual(row.score, "20/1 (1.2 ov)")
        XCTAssertTrue(row.hasScorer)
        XCTAssertNil(row.result)
        // The fixture is the identity, so a row is stable across refreshes.
        XCTAssertEqual(row.id, row.eventId)
    }

    /// Fractional seconds are what broke Season stats before; the same decoder
    /// has to hold here, and it also has to accept a whole-second timestamp.
    func testTimestampsWithAndWithoutFractionalSeconds() throws {
        let page = try FishersJSONDecoder.make()
            .decode(APIPage<CricketFixtureRow>.self, from: Data(json.utf8))

        XCTAssertEqual(
            page.items[0].startAt.timeIntervalSince1970,
            1_788_298_675.590797,
            accuracy: 0.001
        )
        XCTAssertEqual(page.items[1].startAt.timeIntervalSince1970, 1_788_609_600, accuracy: 0.001)
    }

    /// A match can be live before a ball is bowled. The row has to survive the
    /// nulls that come with that, and name the fixture when the sides have not
    /// been set — otherwise the overview shows a blank line.
    func testRowBeforeTheSidesAreNamed() throws {
        let page = try FishersJSONDecoder.make()
            .decode(APIPage<CricketFixtureRow>.self, from: Data(json.utf8))
        let row = page.items[1]

        XCTAssertNil(row.score)
        XCTAssertNil(row.homeName)
        XCTAssertEqual(row.sides, "Saturday League")
    }
}
