import XCTest

/// Fixtures and availability, from a player's and a secretary's phone.
final class FixturesTour: APITourCase {

    private func openFixturesTab() {
        let tab = app.tabBars.buttons["Fixtures"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "no Fixtures tab")
        tab.tap()
    }

    /// A club with a fixture next week, and its secretary.
    private func clubWithFixture(_ tag: String, title: String, extra: [String: Any] = [:]) throws -> (Account, String, String) {
        let secretary = try makeAccount(tag, name: "Sid \(tag.capitalized)", role: "secretary", verified: true)
        let club = try api("POST", "/clubs", token: secretary.access, body: ["name": "\(tag.capitalized) \(stamp % 100000) CC", "sport_types": ["cricket"]])
        let clubId = club["id"] as! String
        let start = Date().addingTimeInterval(3 * 86400)
        var body: [String: Any] = [
            "club_id": clubId, "sport": "cricket", "event_subtype": "league_match", "title": title,
            "start_at": ISO8601DateFormatter().string(from: start),
            "end_at": ISO8601DateFormatter().string(from: start.addingTimeInterval(5 * 3600)),
        ]
        body.merge(extra) { $1 }
        let event = try api("POST", "/events", token: secretary.access, body: body)
        return (secretary, clubId, event["id"] as! String)
    }

    func testAnsweringAFixtureFromTheList() throws {
        try skipWithoutAnAPI()
        let title = "Answer Test \(stamp % 100000)"
        let (secretary, _, eventId) = try clubWithFixture("answer", title: title)
        launch(as: secretary)
        openFixturesTab()

        XCTAssertTrue(reveal(title).exists, "the fixture is not listed")
        let available = app.buttons.matching(NSPredicate(format: "label == 'Available'")).firstMatch
        XCTAssertTrue(available.waitForExistence(timeout: 10), "no way to say you can play")
        capture("Fixtures-list")
        available.tap()
        sleep(2)

        let mine = try apiList("/events/mine?from=\(iso(-86400))&to=\(iso(30 * 86400))", token: secretary.access)
        XCTAssertEqual(mine.first { $0["event_id"] as? String == eventId }?["my_answer"] as? String, "going",
                       "the answer did not reach the server")
        capture("Fixtures-answered")
    }

    func testSchedulingAMatch() throws {
        try skipWithoutAnAPI()
        let secretary = try makeAccount("sched", name: "Sam Scheduler", role: "secretary", verified: true)
        let clubName = "Sched \(stamp % 100000) CC"
        let club = try api("POST", "/clubs", token: secretary.access, body: ["name": clubName, "sport_types": ["cricket"]])
        try api("POST", "/clubs/\(club["id"] as! String)/venues", token: secretary.access, body: ["name": "Gadebridge Park"])
        launch(as: secretary)
        openFixturesTab()

        let add = app.buttons["Schedule a match"]
        XCTAssertTrue(add.waitForExistence(timeout: 20), "a secretary cannot schedule")
        add.tap()
        XCTAssertTrue(element(containing: "Still needed").waitForExistence(timeout: 10), "the form does not say what is missing")
        element(containing: "Opposition").tap()
        let typed = app.textFields["Opposition name"]
        XCTAssertTrue(typed.waitForExistence(timeout: 10), "no way to type the opposition")
        capture("Schedule-opposition")
        typed.tap()
        typed.typeText("Wanderers")
        app.buttons["Use"].tap()

        let schedule = reveal("Schedule and ask who is available")
        XCTAssertTrue(schedule.waitForExistence(timeout: 10))
        capture("Schedule-ready")
        schedule.tap()
        XCTAssertTrue(reveal("\(clubName) v Wanderers", timeout: 25).exists, "the new fixture is not in the list")
        capture("Schedule-listed")
    }

    func testSettingEverySaturday() throws {
        try skipWithoutAnAPI()
        let player = try makeAccount("sat", name: "Pip Saturday", role: "player")
        launch(as: player)
        openFixturesTab()
        app.segmentedControls.buttons["Calendar"].firstMatch.tap()

        let usual = reveal("Your usual days")
        XCTAssertTrue(usual.exists, "no way to set a usual day")
        let everySaturday = app.buttons["Every Saturday Available"]
        XCTAssertTrue(everySaturday.waitForExistence(timeout: 10) || reveal("Every Saturday Available").exists)
        everySaturday.tap()
        sleep(2)
        capture("Calendar-saturdays")

        let cal = Calendar(identifier: .gregorian)
        let saturdays = (0..<31).compactMap { cal.date(byAdding: .day, value: $0, to: cal.date(from: cal.dateComponents([.year, .month], from: .now))!) }
            .filter { cal.component(.weekday, from: $0) == 7 && cal.component(.month, from: $0) == cal.component(.month, from: .now) }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let saved = try apiList("/availability?from=\(f.string(from: saturdays.first!))&to=\(f.string(from: saturdays.last!))", token: player.access)
        XCTAssertEqual(saved.filter { $0["status"] as? String == "available" }.count, saturdays.count,
                       "not every Saturday this month was saved")
    }

    func testBookingAndMarkingATicketPaid() throws {
        try skipWithoutAnAPI()
        let title = "Dinner \(stamp % 100000)"
        let (secretary, _, eventId) = try clubWithFixture("dinner", title: title, extra: [
            "event_subtype": "social", "ticket_price_cents": 2500, "ticket_capacity": 40, "guests_allowed": 2,
        ])
        launch(as: secretary)
        openFixturesTab()
        reveal(title).tap()
        let tickets = reveal("Tickets")
        XCTAssertTrue(tickets.exists, "the dinner has no tickets link")
        tickets.tap()

        let book = app.buttons["Book 1 place"]
        XCTAssertTrue(book.waitForExistence(timeout: 15), "no way to book")
        capture("Tickets-book")
        book.tap()
        XCTAssertTrue(element(containing: "You are booked").waitForExistence(timeout: 15), "booking did not take")

        // The booking under "Who is coming", by name — "Reserved" is also on
        // the summary of your own place, which has nothing to swipe.
        let row = reveal("Sid Dinner")
        XCTAssertTrue(row.exists, "the booking is not listed")
        row.swipeLeft()
        let cash = app.buttons["Cash"]
        XCTAssertTrue(cash.waitForExistence(timeout: 5), "no way to take cash at the door")
        cash.tap()
        XCTAssertTrue(element(containing: "marked paid").waitForExistence(timeout: 15), "marking paid did not take")
        capture("Tickets-paid")

        let booking = try api("GET", "/events/\(eventId)/tickets", token: secretary.access, body: nil)
        let status = ((booking["tickets"] as? [[String: Any]]) ?? []).first?["status"] as? String
        XCTAssertEqual(status, "paid", "the server does not have it paid")
    }

    private func iso(_ offset: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset))
    }
}
