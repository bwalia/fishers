import XCTest
@testable import Fishers

/// Offline venue mode stores a pending `CreateEventBody` on the local match and
/// reloads fixtures from disk. Both must survive an encode → decode round trip
/// with ISO-8601 dates (the same strategy the sync service uses).
final class OfflineVenueModeTests: XCTestCase {
    func testCreateEventBodyRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_725_000_000)
        let body = CreateEventBody(
            club_id: UUID(uuidString: "a1f63def-c9c9-4bf0-8ee1-6f375a59d402")!,
            opponent_club_id: UUID(uuidString: "b2f63def-c9c9-4bf0-8ee1-6f375a59d403")!,
            team_id: nil,
            sport: "cricket",
            event_subtype: "friendly",
            title: "Lords v Hemel",
            venue_id: nil,
            start_at: start,
            end_at: start.addingTimeInterval(4 * 3600),
            recurrence_rule: nil,
            capacity: 22,
            fee_amount_cents: nil,
            metadata: [
                "opposition": .string("Hemel"),
                "home_name": .string("Lords"),
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(body)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CreateEventBody.self, from: data)

        XCTAssertEqual(decoded.club_id, body.club_id)
        XCTAssertEqual(decoded.opponent_club_id, body.opponent_club_id)
        XCTAssertEqual(decoded.title, "Lords v Hemel")
        XCTAssertEqual(decoded.sport, "cricket")
        XCTAssertEqual(decoded.event_subtype, "friendly")
        XCTAssertEqual(decoded.capacity, 22)
        XCTAssertEqual(
            decoded.start_at.timeIntervalSince1970,
            body.start_at.timeIntervalSince1970,
            accuracy: 1
        )
        if case let .string(away)? = decoded.metadata?["opposition"] {
            XCTAssertEqual(away, "Hemel")
        } else {
            XCTFail("opposition metadata missing")
        }
    }

    func testOfflineCacheFixturesRoundTrip() throws {
        let row = CricketFixtureRow(
            eventId: UUID(uuidString: "7aabb058-cce2-44f6-bcd6-466a55f10747")!,
            clubId: UUID(uuidString: "a1f63def-c9c9-4bf0-8ee1-6f375a59d402")!,
            title: "Lords vs Hemel — live",
            startAt: Date(timeIntervalSince1970: 1_725_000_000),
            eventStatus: "scheduled",
            matchId: UUID(uuidString: "b19e7f6b-75ad-47b8-9d19-14932c99ad78")!,
            matchStatus: "live",
            homeName: "Lords",
            awayName: "Hemel",
            hasScorer: true,
            score: "20/1 (1.2 ov)",
            result: nil
        )
        let page = APIPage(
            items: [row], total: 1, page: 1, perPage: 20, hasMore: false
        )
        OfflineCache.saveFixtures(page, state: "live")
        let snap = OfflineCache.loadFixtures(state: "live")
        XCTAssertEqual(snap?.total, 1)
        XCTAssertEqual(snap?.rows.first?.sides, "Lords v Hemel")
        XCTAssertEqual(snap?.rows.first?.score, "20/1 (1.2 ov)")

        let event = OfflineCache.loadEvent(id: row.eventId)
        XCTAssertEqual(event?.title, row.title)
        XCTAssertEqual(event?.clubId, row.clubId)
    }

    func testLocalMatchHasPendingWorkIncludesPendingEvent() {
        // Mirror the flag the sync sweep uses — a fixture minted offline must
        // count as pending even before any ball is bowled.
        let state = MatchState(oversLimit: 20, homeName: "Lords", awayName: "Hemel")
        let match = LocalCricketMatch(
            matchId: UUID(),
            eventId: UUID(),
            clubId: UUID(),
            deviceId: "test-device",
            homeName: "Lords",
            awayName: "Hemel",
            oversLimit: 20,
            state: state,
            needsRemoteCreate: true
        )
        XCTAssertTrue(match.hasPendingWork)
        match.needsRemoteCreate = false
        XCTAssertFalse(match.hasPendingWork)
        match.pendingEventJSON = Data("{}".utf8)
        XCTAssertTrue(match.hasPendingWork)
    }
}
