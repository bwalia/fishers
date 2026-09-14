import XCTest
@testable import Fishers

final class FixturesTests: XCTestCase {
    private let decoder = FishersJSONDecoder.make()
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    private func fixture(_ title: String, start: String, hours: Double = 5, answer: String? = nil) throws -> MyFixture {
        let startDate = ISO8601DateFormatter().date(from: start)!
        let end = ISO8601DateFormatter().string(from: startDate.addingTimeInterval(hours * 3600))
        return try decoder.decode(MyFixture.self, from: Data("""
        {"event_id":"\(UUID().uuidString)","title":"\(title)","sport":"cricket","event_subtype":"league_match",
         "status":"scheduled","start_at":"\(start)","end_at":"\(end)","club_id":"\(UUID().uuidString)",
         "club_name":"Boom Blast","opponent_club_id":null,"opponent_club_name":null,"venue_name":"Gadebridge",
         "match_id":null,"my_answer":\(answer.map { "\"\($0)\"" } ?? "null"),"fee_amount_cents":null,"ticket_price_cents":null}
        """.utf8))
    }

    func testDecodesAnswers() throws {
        XCTAssertEqual(try fixture("A", start: "2026-09-20T12:00:00Z", answer: "not_going").myAnswer, .notGoing)
        XCTAssertNil(try fixture("B", start: "2026-09-20T12:00:00Z").myAnswer)
        XCTAssertEqual(try fixture("B", start: "2026-09-20T12:00:00Z").saidLabel, "Not answered yet")
        XCTAssertEqual(FixtureAnswer.notGoing.rsvp, .notGoing)
    }

    func testGroupsByLocalDayInOrder() throws {
        let late = try fixture("Late", start: "2026-09-20T17:00:00Z")
        let early = try fixture("Early", start: "2026-09-20T09:00:00Z")
        let next = try fixture("Next", start: "2026-09-21T09:00:00Z")
        let days = FixtureList.byDay([next, late, early], calendar: calendar)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].fixtures.map(\.title), ["Early", "Late"])
        XCTAssertEqual(days[1].fixtures.map(\.title), ["Next"])
    }

    func testClashesAreOnlyBetweenFixturesYouArePlaying() throws {
        let a = try fixture("A", start: "2026-09-20T12:00:00Z", answer: "going")
        let b = try fixture("B", start: "2026-09-20T14:00:00Z", answer: "going")
        let c = try fixture("C", start: "2026-09-20T13:00:00Z", answer: "maybe")
        let d = try fixture("D", start: "2026-09-20T20:00:00Z", answer: "going")
        XCTAssertEqual(FixtureList.clashes([a, b, c, d]), [a.eventId, b.eventId])
    }

    func testDayTitles() throws {
        let now = ISO8601DateFormatter().date(from: "2026-09-14T10:00:00Z")!
        let today = calendar.startOfDay(for: now)
        XCTAssertTrue(FixtureList.dayTitle(today, now: now, calendar: calendar).hasPrefix("Today · "))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        XCTAssertTrue(FixtureList.dayTitle(tomorrow, now: now, calendar: calendar).hasPrefix("Tomorrow · "))
        let later = calendar.date(byAdding: .day, value: 5, to: today)!
        XCTAssertFalse(FixtureList.dayTitle(later, now: now, calendar: calendar).contains("·"))
    }

    func testEveryWeekdayInAMonth() {
        let september = ISO8601DateFormatter().date(from: "2026-09-14T10:00:00Z")!
        let saturdays = FixtureList.dates(in: september, weekday: 7, calendar: calendar)
        XCTAssertEqual(saturdays.map { calendar.component(.day, from: $0) }, [5, 12, 19, 26])
        XCTAssertEqual(FixtureList.dates(in: september, weekday: 3, calendar: calendar).count, 5, "September 2026 has five Tuesdays")
    }

    func testTicketSummaryWithAndWithoutGuests() throws {
        let with = try decoder.decode(TicketSummary.self, from: Data("""
        {"event_id":"\(UUID().uuidString)","title":"Dinner","ticket_capacity":40,"ticket_price_cents":2500,
         "guests_allowed":2,"bookings":3,"headcount":7,"collected_cents":5000,"outstanding_cents":12500}
        """.utf8))
        XCTAssertEqual(with.guestsAllowed, 2)
        XCTAssertEqual(with.placesLeft, 33)
        let without = try decoder.decode(TicketSummary.self, from: Data("""
        {"event_id":"\(UUID().uuidString)","title":"Quiz","ticket_capacity":null,"ticket_price_cents":null,
         "bookings":0,"headcount":0,"collected_cents":0,"outstanding_cents":0}
        """.utf8))
        XCTAssertNil(without.guestsAllowed)
        XCTAssertNil(without.placesLeft)
    }
}
