import XCTest
@testable import Fishers

/// Nets and training: what the schedule sheet sends, and how a session reads
/// once it exists. Matches are checked alongside, because the same sheet
/// sends them and they must not change.
final class PracticeSessionsTests: XCTestCase {
    private let club = Club(
        id: UUID(), name: "Boom Blast", sportTypes: ["cricket"], visibility: "public",
        ownerId: UUID(), description: nil, isInformalGroup: false, role: nil
    )
    private let london: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    override func setUp() {
        super.setUp()
        Strings.setCurrent(.en)
    }

    /// 19:00 in London on the given day.
    private func sevenPM(_ year: Int, _ month: Int, _ day: Int) -> Date {
        london.date(from: DateComponents(year: year, month: month, day: day, hour: 19))!
    }

    private func event(for body: CreateEventBody) -> Event {
        Event(
            id: UUID(), clubId: body.club_id, teamId: body.team_id, sport: body.sport,
            eventSubtype: body.event_subtype, title: body.title, venueId: body.venue_id,
            startAt: body.start_at, endAt: body.end_at, capacity: nil, feeAmountCents: nil,
            feeCurrency: "GBP", status: "scheduled", metadata: body.metadata,
            ticketPriceCents: nil, opponentClubId: nil
        )
    }

    private struct Offline: Error {}

    // MARK: - What is sent

    func testASingleSession() {
        let start = sevenPM(2026, 11, 18)
        let team = UUID(), ground = UUID()
        let bodies = ScheduleRequests.sessions(
            kind: .nets, club: club, teamId: team, title: "Wednesday nets", venueId: ground,
            start: start, minutes: 120, note: "  Bring your own bat.  ", weeks: nil, calendar: london
        )

        XCTAssertEqual(bodies.count, 1)
        let body = bodies[0]
        XCTAssertEqual(body.club_id, club.id)
        XCTAssertEqual(body.team_id, team)
        XCTAssertEqual(body.venue_id, ground)
        XCTAssertEqual(body.sport, "cricket")
        XCTAssertEqual(body.event_subtype, "nets")
        XCTAssertEqual(body.title, "Wednesday nets")
        XCTAssertEqual(body.start_at, start)
        XCTAssertEqual(body.end_at, start.addingTimeInterval(120 * 60))
        XCTAssertNil(body.opponent_club_id)
        XCTAssertNil(body.recurrence_rule)
        XCTAssertEqual(body.metadata, ["note": .string("Bring your own bat.")])
    }

    func testALoneSessionWithNoNoteSendsNoSeriesAndNoNote() {
        let bodies = ScheduleRequests.sessions(
            kind: .training, club: club, teamId: nil, title: "Training", venueId: nil,
            start: sevenPM(2026, 11, 18), minutes: 90, note: "   ", weeks: nil, calendar: london
        )
        XCTAssertEqual(bodies.count, 1)
        XCTAssertEqual(bodies[0].event_subtype, "training")
        XCTAssertNil(bodies[0].team_id)
        XCTAssertEqual(bodies[0].metadata, [:])
    }

    func testTheSportIsTheClubsOwnElseCricket() {
        var football = club
        football.sportTypes = ["football", "cricket"]
        var none = club
        none.sportTypes = []
        for (club, sport) in [(football, "football"), (none, "cricket")] {
            let body = ScheduleRequests.sessions(
                kind: .nets, club: club, teamId: nil, title: "Nets", venueId: nil,
                start: sevenPM(2026, 11, 18), minutes: 60, note: "", weeks: nil, calendar: london
            )[0]
            XCTAssertEqual(body.sport, sport)
        }
    }

    /// Three Wednesdays across the night the clocks go back (25 October 2026).
    /// A week is a calendar week, not 7 × 24 hours, so 19:00 stays 19:00.
    func testAThreeWeekSeriesAcrossTheClocksGoingBack() {
        let start = sevenPM(2026, 10, 21)
        let series = UUID()
        let bodies = ScheduleRequests.sessions(
            kind: .nets, club: club, teamId: nil, title: "Wednesday nets", venueId: nil,
            start: start, minutes: 120, note: "", weeks: 3, seriesId: series, calendar: london
        )

        XCTAssertEqual(bodies.count, 3)
        for (index, body) in bodies.enumerated() {
            XCTAssertEqual(body.metadata?["series_id"], .string(series.uuidString.lowercased()))
            XCTAssertEqual(body.metadata?["series_index"], .number(Double(index)))
            XCTAssertEqual(body.metadata?["series_count"], .number(3))
            XCTAssertNil(body.metadata?["note"])
            XCTAssertEqual(body.end_at, body.start_at.addingTimeInterval(120 * 60))
            XCTAssertEqual(london.component(.hour, from: body.start_at), 19, "week \(index + 1) moved off 19:00")
            XCTAssertEqual(london.component(.minute, from: body.start_at), 0)
            XCTAssertEqual(london.component(.weekday, from: body.start_at), 4, "week \(index + 1) is not a Wednesday")
            XCTAssertNil(body.opponent_club_id)
            XCTAssertNil(body.recurrence_rule)
        }
        let days = bodies.map { london.dateComponents([.month, .day], from: $0.start_at) }
        XCTAssertEqual(days.map { [$0.month, $0.day] }, [[10, 21], [10, 28], [11, 4]])
        // The week the clocks go back is an hour longer in real time.
        XCTAssertEqual(bodies[1].start_at.timeIntervalSince(bodies[0].start_at), 7 * 86400 + 3600)
        XCTAssertEqual(bodies[2].start_at.timeIntervalSince(bodies[1].start_at), 7 * 86400)
    }

    func testEachSeriesGetsItsOwnId() {
        func one() -> JSONValue? {
            ScheduleRequests.sessions(
                kind: .nets, club: club, teamId: nil, title: "Nets", venueId: nil,
                start: sevenPM(2026, 11, 18), minutes: 120, note: "", weeks: 2, calendar: london
            )[0].metadata?["series_id"]
        }
        XCTAssertNotNil(one())
        XCTAssertNotEqual(one(), one())
    }

    /// The server reads `series_index` as a whole number: `1.0` would read as
    /// no index at all, and every week would notify.
    func testTheWireCarriesWholeNumbersAndLeavesOutWhatIsNotSent() throws {
        let body = ScheduleRequests.sessions(
            kind: .nets, club: club, teamId: nil, title: "Nets", venueId: nil,
            start: sevenPM(2026, 10, 21), minutes: 120, note: "", weeks: 3, calendar: london
        )[1]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(body), as: UTF8.self)

        XCTAssertNotNil(json.range(of: #""series_index":1[,}]"#, options: .regularExpression), json)
        XCTAssertNotNil(json.range(of: #""series_count":3[,}]"#, options: .regularExpression), json)
        XCTAssertTrue(json.contains(#""event_subtype":"nets""#), json)
        XCTAssertFalse(json.contains("opponent_club_id"), json)
        XCTAssertFalse(json.contains("recurrence_rule"), json)
    }

    // MARK: - Sending them

    func testFailureOnWeekTwoStopsAndARetryNeverResendsWeekOne() async {
        let bodies = ScheduleRequests.sessions(
            kind: .nets, club: club, teamId: nil, title: "Nets", venueId: nil,
            start: sevenPM(2026, 11, 18), minutes: 120, note: "", weeks: 3, calendar: london
        )
        func index(_ body: CreateEventBody) -> Int {
            guard case .number(let n)? = body.metadata?["series_index"] else { return -1 }
            return Int(n)
        }

        var sent: [Int] = []
        let first = await ScheduleRequests.create(bodies) { body in
            sent.append(index(body))
            if index(body) == 1 { throw Offline() }
            return self.event(for: body)
        }
        XCTAssertEqual(sent, [0, 1], "it carried on after week 2 failed")
        XCTAssertEqual(first.made.count, 1)
        XCTAssertTrue(first.failure is Offline)

        // Schedule again: from the week that failed, never week 1.
        sent = []
        let retry = await ScheduleRequests.create(bodies, from: first.made.count) { body in
            sent.append(index(body))
            return self.event(for: body)
        }
        XCTAssertEqual(sent, [1, 2])
        XCTAssertEqual(retry.made.count, 2)
        XCTAssertNil(retry.failure)
    }

    func testEveryWeekIsSentInOrderWhenNothingFails() async {
        let bodies = ScheduleRequests.sessions(
            kind: .training, club: club, teamId: nil, title: "Training", venueId: nil,
            start: sevenPM(2026, 11, 18), minutes: 90, note: "", weeks: 4, calendar: london
        )
        var sent: [Date] = []
        let outcome = await ScheduleRequests.create(bodies) { body in
            sent.append(body.start_at)
            return self.event(for: body)
        }
        XCTAssertEqual(sent, bodies.map(\.start_at))
        XCTAssertEqual(outcome.made.map(\.startAt), bodies.map(\.start_at))
        XCTAssertNil(outcome.failure)
    }

    // MARK: - Matches are unchanged

    func testAMatchIsSentAsItAlwaysWas() {
        let start = sevenPM(2026, 11, 21)
        let them = UUID(), ground = UUID()
        let body = ScheduleRequests.match(
            club: club, opponentClubId: them, theirName: "Wanderers", venueId: ground, start: start
        )
        XCTAssertEqual(body.event_subtype, "league_match")
        XCTAssertEqual(body.title, "Boom Blast v Wanderers")
        XCTAssertEqual(body.opponent_club_id, them)
        XCTAssertEqual(body.venue_id, ground)
        XCTAssertEqual(body.sport, "cricket")
        XCTAssertNil(body.team_id)
        XCTAssertEqual(body.end_at, start.addingTimeInterval(5 * 3600))
        XCTAssertNil(body.recurrence_rule)
        XCTAssertNil(body.capacity)
        XCTAssertNil(body.fee_amount_cents)
        XCTAssertNil(body.metadata)
    }

    func testAMatchStillAsksWhetherYouCanPlay() {
        for subtype in ["league_match", "friendly", "tournament", "social"] {
            XCTAssertFalse(Practice.isPractice(subtype), subtype)
            XCTAssertNil(Practice.label(subtype), subtype)
            XCTAssertEqual(
                Practice.question(subtype: subtype, title: "Boom Blast v Wanderers"),
                "Can you play Boom Blast v Wanderers?"
            )
        }
    }

    // MARK: - How a session reads

    func testASessionAsksWhetherYouAreComing() {
        XCTAssertTrue(Practice.isPractice("nets"))
        XCTAssertTrue(Practice.isPractice("training"))
        XCTAssertEqual(Practice.label("nets"), "Nets")
        XCTAssertEqual(Practice.label("training"), "Training")
        XCTAssertEqual(Practice.question(subtype: "nets", title: "Wednesday nets"), "Are you coming?")
    }

    func testWeekOfAndNote() {
        let metadata: [String: JSONValue] = [
            "series_id": .string(UUID().uuidString.lowercased()),
            "series_index": .number(2), "series_count": .number(8),
            "note": .string("Bowling machine booked"),
        ]
        XCTAssertEqual(Practice.weekOf(metadata), "Week 3 of 8")
        XCTAssertEqual(Practice.note(metadata), "Bowling machine booked")
        XCTAssertNil(Practice.weekOf([:]))
        XCTAssertNil(Practice.weekOf(nil))
        XCTAssertNil(Practice.note(["note": .string("  ")]))
    }

    func testTheSheetsDefaults() {
        XCTAssertEqual(ScheduleKind.nets.defaultMinutes, 120)
        XCTAssertEqual(ScheduleKind.training.defaultMinutes, 90)
        XCTAssertEqual(ScheduleRequests.minuteChoices, [60, 90, 120, 180])
        XCTAssertEqual(ScheduleRequests.weekChoices, 2...12)
        XCTAssertEqual(ScheduleRequests.defaultWeeks, 8)
        XCTAssertEqual(ScheduleKind.allCases.map(\.label), ["Match", "Nets", "Training"])
    }

    func testOnlyASeriesSaysHowManyWereScheduled() {
        XCTAssertNil(ScheduledSessions(eventId: UUID(), count: 1).notice)
        XCTAssertEqual(ScheduledSessions(eventId: UUID(), count: 8).notice, "8 sessions scheduled")
    }
}
