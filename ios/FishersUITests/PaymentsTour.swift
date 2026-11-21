import XCTest

/// Paying the club by bank transfer, from a player's, a treasurer's and a
/// secretary's phone. Every step is checked against the API as well as on
/// screen: a button that looks pressed is not a payment recorded.
///
/// Runs against the demo club from `.dev/payments/seed_demo.py`, which it tops
/// up through the API with a bill of its own each run:
///   ./scripts/start.sh --no-ios && python3 .dev/payments/seed_demo.py
///   FISHERS_SIM_DEVICE="iPhone 16" ./scripts/ios-ui-test.sh   (or -only-testing:FishersUITests/PaymentsTour)
final class PaymentsTour: APITourCase {

    private static let demoPassword = "password123"
    private static let demoClub = "Riverside Strikers (demo)"

    /// A demo account, signed in through the API, with a finished profile so
    /// the app goes straight to Home rather than the quick start.
    private func demo(_ email: String, role: String) throws -> Account {
        let tokens = try api("POST", "/auth/login", token: nil,
                             body: ["identifier": email, "password": Self.demoPassword])
        let access = try XCTUnwrap(tokens["access_token"] as? String, "no demo account \(email) — run seed_demo.py")
        let refresh = try XCTUnwrap(tokens["refresh_token"] as? String)
        try api("PATCH", "/me", token: access, body: [
            "primary_sport": "cricket",
            "sport_profiles": [["sport": "cricket", "position": "batter", "skill_level": "club", "stats": [:]]],
            "role_intent": role,
        ])
        return Account(access: access, refresh: refresh, email: email)
    }

    private func demoClubId(_ secretary: Account) throws -> String {
        if let clubs = try? apiList("/clubs?mine=true", token: secretary.access),
           let id = clubs.first(where: { $0["name"] as? String == Self.demoClub })?["id"] as? String { return id }
        let dues = try api("GET", "/me/dues", token: secretary.access, body: nil)["clubs"] as? [[String: Any]] ?? []
        return try XCTUnwrap(dues.first { $0["club_name"] as? String == Self.demoClub }?["club_id"] as? String,
                             "no demo club — run .dev/payments/seed_demo.py")
    }

    private func iso(_ offset: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset))
    }

    private func dues(_ account: Account, club: String) throws -> [String: Any] {
        let clubs = try api("GET", "/me/dues", token: account.access, body: nil)["clubs"] as? [[String: Any]] ?? []
        return clubs.first { $0["club_id"] as? String == club } ?? [:]
    }

    private func tapTab(_ name: String) {
        let tab = app.tabBars.buttons[name].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "no \(name) tab")
        tab.tap()
    }

    /// A player sees what they owe on Home, opens the pay screen, finds the
    /// club's details and reference, and says they've paid. The share becomes
    /// "waiting", never "paid".
    func testAPlayerSeesWhatTheyOweAndSaysTheyHavePaid() throws {
        try skipWithoutAnAPI()
        let secretary = try demo("aman@pay.test", role: "secretary")
        let player = try demo("ravi@pay.test", role: "player")
        let clubId = try demoClubId(secretary)
        // A bill of this run's own: £30 for nets that finished an hour ago, between two.
        let event = try api("POST", "/events", token: secretary.access, body: [
            "club_id": clubId, "sport": "cricket", "event_subtype": "nets", "title": "iOS nets \(stamp % 100000)",
            "start_at": iso(-3 * 3600), "end_at": iso(-3600),
            "cost_mode": "split_total", "cost_amount_cents": 3000,
        ])
        let eventId = try XCTUnwrap(event["id"] as? String)
        try api("POST", "/events/\(eventId)/bill", token: secretary.access, body: [
            "attendees": [try meId(secretary), try meId(player)],
        ])
        let before = try dues(player, club: clubId)
        let owedBefore = before["owed_cents"] as? Int ?? 0
        let waitingBefore = before["waiting_cents"] as? Int ?? 0
        XCTAssertGreaterThanOrEqual(owedBefore, 1500, "the bill did not reach the player")

        launch(as: player)
        let card = element(containing: "You owe")
        XCTAssertTrue(card.waitForExistence(timeout: 25), "Home does not say what the player owes")
        capture("Pay-1-home-you-owe")
        card.tap()

        // The list is grouped by club; each club's "You owe £…" row opens its pay screen.
        XCTAssertTrue(element(containing: Self.demoClub.uppercased()).waitForExistence(timeout: 15)
                      || element(containing: Self.demoClub).exists, "the list of what is owed does not open")
        capture("Pay-2-dues-list")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'You owe'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no row to open the pay screen")
        row.tap()

        let paid = app.buttons["I've paid"].firstMatch
        XCTAssertTrue(element(containing: "You owe").waitForExistence(timeout: 15), "no headline saying what is owed")
        XCTAssertTrue(element(containing: "Pay ").exists, "the pay screen does not say who to pay")
        XCTAssertTrue(reveal("Account number").exists, "the pay screen has no account number")
        XCTAssertTrue(element(containing: "reference box").exists, "the pay screen has no reference")
        capture("Pay-3-pay-screen")
        let copy = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Copy'")).firstMatch
        if copy.exists { copy.tap(); capture("Pay-4-copied") }

        XCTAssertTrue(reveal("I've paid").exists, "no I've paid button")
        // Just below the two big buttons, while something is still owed.
        if element(containing: "Send these details to someone").exists { capture("Pay-3b-send-these-details") }
        paid.tap()
        XCTAssertTrue(element(containing: "Waiting for the club to confirm").waitForExistence(timeout: 15),
                      "the claim does not show as waiting")
        XCTAssertTrue(reveal("Add a screenshot").exists, "no Add a screenshot once it is waiting")
        capture("Pay-5-waiting")

        let after = try dues(player, club: clubId)
        XCTAssertEqual(after["owed_cents"] as? Int, 0, "a claim did not cover what was owed")
        XCTAssertEqual(after["waiting_cents"] as? Int, waitingBefore + owedBefore, "the claim is not the amount owed")
    }

    /// The treasurer opens the club's Payments and marks the claim received.
    func testATreasurerConfirmsAPayment() throws {
        try skipWithoutAnAPI()
        let secretary = try demo("aman@pay.test", role: "secretary")
        let treasurer = try demo("tara@pay.test", role: "player")
        let player = try demo("ravi@pay.test", role: "player")
        let clubId = try demoClubId(secretary)
        // Make sure there is a claim to check, whatever ran before.
        let owed = try dues(player, club: clubId)["owed_cents"] as? Int ?? 0
        if owed > 0 {
            var request = URLRequest(url: URL(string: Self.apiBase + "/api/v1/clubs/\(clubId)/payments")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(player.access)", forHTTPHeaderField: "Authorization")
            request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["method": "transfer"])
            let done = expectation(description: "claim")
            URLSession.shared.dataTask(with: request) { _, _, _ in done.fulfill() }.resume()
            wait(for: [done], timeout: 20)
        }
        let claimsBefore = try apiList("/clubs/\(clubId)/payments?status=claimed", token: treasurer.access)
        XCTAssertFalse(claimsBefore.isEmpty, "nothing for the treasurer to check")

        launch(as: treasurer)
        tapTab("Clubs")
        if !element(containing: Self.demoClub).waitForExistence(timeout: 10) { tapTab("Clubs") }
        reveal(Self.demoClub).tap()
        reveal("5 members").tap()
        let payments = app.buttons["Payments"].firstMatch
        XCTAssertTrue(payments.waitForExistence(timeout: 20), "no Payments tab for the treasurer")
        payments.tap()
        XCTAssertTrue(element(containing: "Payments to check").waitForExistence(timeout: 20), "no payments to check")
        capture("Treasurer-1-to-check")

        let received = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Received' AND NOT (label CONTAINS 'Not')")).firstMatch
        XCTAssertTrue(reveal("Received").exists && received.exists, "no Received button")
        received.tap()
        sleep(3)
        capture("Treasurer-2-confirmed")

        let claimsAfter = try apiList("/clubs/\(clubId)/payments?status=claimed", token: treasurer.access)
        XCTAssertEqual(claimsAfter.count, claimsBefore.count - 1, "Received did not confirm a payment")
    }

    /// The secretary ticks who came on a fixture with a cost and sends the bill.
    func testASecretaryTicksWhoCameAndSendsTheBill() throws {
        try skipWithoutAnAPI()
        let secretary = try demo("aman@pay.test", role: "secretary")
        let player = try demo("ravi@pay.test", role: "player")
        let clubId = try demoClubId(secretary)
        let title = "iOS fixture \(stamp % 100000)"
        let event = try api("POST", "/events", token: secretary.access, body: [
            "club_id": clubId, "sport": "cricket", "event_subtype": "friendly", "title": title,
            "start_at": iso(86400), "end_at": iso(86400 + 4 * 3600),
            "cost_mode": "per_player", "cost_amount_cents": 500,
        ])
        let eventId = try XCTUnwrap(event["id"] as? String)
        try api("POST", "/events/\(eventId)/rsvp", token: player.access, body: ["status": "going"])

        launch(as: secretary)
        tapTab("Fixtures")
        let row = reveal(title)
        XCTAssertTrue(row.exists, "the fixture is not listed")
        row.tap()

        XCTAssertTrue(reveal("£5.00").exists, "the event does not show its cost")
        let whoCame = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Who came'")).firstMatch
        XCTAssertTrue(reveal("Who came").exists && whoCame.exists, "no Who came? button")
        capture("Secretary-1-event-money")
        whoCame.tap()

        let send = app.buttons["Send the bill"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 15), "the who-came sheet has no Send")
        XCTAssertTrue(element(containing: "Ravi Sharma").exists, "the player who said going is not listed")
        capture("Secretary-2-who-came")
        send.tap()
        sleep(3)
        capture("Secretary-3-billed")
        XCTAssertTrue(reveal("Who paid cash?").exists, "no Who paid cash? on a billed event")
        XCTAssertTrue(reveal("Share the bill").exists, "no Share the bill once the bill is sent")
        capture("Secretary-4-tell-the-group")

        let bill = try api("GET", "/events/\(eventId)/bill", token: secretary.access, body: nil)
        let shares = bill["shares"] as? [[String: Any]] ?? []
        XCTAssertNotNil(bill["bill"] as? [String: Any], "no bill was sent")
        XCTAssertTrue(shares.contains { $0["name"] as? String == "Ravi Sharma" && $0["amount_cents"] as? Int == 500 },
                      "Ravi was not billed £5")
    }

    private func meId(_ account: Account) throws -> String {
        try XCTUnwrap(api("GET", "/me", token: account.access, body: nil)["id"] as? String)
    }
}
