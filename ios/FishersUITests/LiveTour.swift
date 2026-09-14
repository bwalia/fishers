import XCTest

/// What arrives without anybody pulling to refresh: a message in the open
/// thread, an alert from another screen, a score moving ball by ball.
final class LiveTour: APITourCase {

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "no \(name) tab")
        button.tap()
    }

    func testAMessageAppearsInTheOpenThread() throws {
        try skipWithoutAnAPI()
        let secretary = try makeAccount("chat", name: "Cal Chat", role: "secretary", verified: true)
        let club = try api("POST", "/clubs", token: secretary.access,
                           body: ["name": "Chat \(stamp % 100000) CC", "sport_types": ["cricket"]])
        let thread = try api("POST", "/conversations", token: secretary.access,
                             body: ["title": "Saturday squad", "club_id": club["id"] as! String])
        launch(as: secretary)

        tab("Chats")
        let row = element(containing: "Saturday squad")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the thread is not listed")
        row.tap()
        XCTAssertTrue(app.navigationBars["Saturday squad"].waitForExistence(timeout: 10))
        sleep(2) // connected

        // Written somewhere else — the web, another phone.
        try api("POST", "/conversations/\(thread["id"] as! String)/messages", token: secretary.access,
                body: ["body": "Nets at six, bring the new ball"])
        XCTAssertTrue(element(containing: "Nets at six").waitForExistence(timeout: 15),
                      "the message did not arrive by itself")
        capture("Live-thread")
    }

    func testAnInviteRaisesAnAlert() throws {
        try skipWithoutAnAPI()
        let player = try makeAccount("alert", name: "Al Alert", role: "player", verified: true)
        launch(as: player)
        tab("Fixtures")
        sleep(3) // connected

        let secretary = try makeAccount("alerter", name: "Ivy Inviter", role: "secretary", verified: true)
        let name = "Alert \(stamp % 100000) CC"
        let club = try api("POST", "/clubs", token: secretary.access, body: ["name": name, "sport_types": ["cricket"]])
        try api("POST", "/invites", token: secretary.access,
                body: ["target_type": "club", "target_id": club["id"] as! String, "invited_email": player.email])

        let alert = element(containing: "\(name) wants you in the club")
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "no alert for the invite")
        capture("Live-alert")
        alert.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 10),
                      "the alert did not open what it was about")
    }

    func testTheScoreMovesBallByBall() throws {
        try skipWithoutAnAPI()
        let secretary = try makeAccount("score", name: "Sam Scorer", role: "secretary", verified: true)
        let club = try api("POST", "/clubs", token: secretary.access,
                           body: ["name": "Lords \(stamp % 100000)", "sport_types": ["cricket"]])
        let clubId = club["id"] as! String
        let now = ISO8601DateFormatter().string(from: .now)
        let later = ISO8601DateFormatter().string(from: .now.addingTimeInterval(4 * 3600))
        let event = try api("POST", "/events", token: secretary.access, body: [
            "club_id": clubId, "sport": "cricket", "event_subtype": "league_match",
            "title": "Lords v Hemel", "start_at": now, "end_at": later, "capacity": 22,
        ])
        let match = try api("POST", "/events/\(event["id"] as! String)/cricket-match", token: secretary.access,
                            body: ["overs_limit": 20, "home_name": "Lords", "away_name": "Hemel"])
        let matchId = match["id"] as! String
        try api("POST", "/cricket/matches/\(matchId)/claim-scorer", token: secretary.access, body: ["device_id": "tour"])

        let player = { (n: String) in ["id": UUID().uuidString.lowercased(), "name": n, "bats_left": false] as [String: Any] }
        let home = (1...11).map { player("Lords \($0)") }
        let away = (1...11).map { player("Hemel \($0)") }
        var seq = 0
        func post(_ kinds: [[String: Any]]) throws {
            let events = kinds.map { kind -> [String: Any] in
                seq += 1
                return ["client_event_id": UUID().uuidString.lowercased(), "seq": seq, "kind": kind]
            }
            try api("POST", "/cricket/matches/\(matchId)/events", token: secretary.access,
                    body: ["device_id": "tour", "events": events])
        }
        func ball(_ runs: Int, four: Bool = false, six: Bool = false) -> [String: Any] {
            ["type": "delivery_recorded", "runs": runs, "is_legal": true,
             "is_boundary_four": four, "is_boundary_six": six, "shot": NSNull()]
        }
        let conditions: [String: Any] = [
            "overs_limit": 20, "overs_per_bowler": 4, "ground": "open", "ball": "white",
            "powerplay_overs": 6, "fielders_outside_powerplay": 2, "fielders_outside_normal": 5,
            "fielders_behind_square_leg": 2, "target_overs_per_hour": 14,
        ]
        try post([
            ["type": "match_prepared", "overs_limit": 20, "home_name": "Lords", "away_name": "Hemel"],
            ["type": "conditions_proposed", "by": "home", "by_name": "Sam", "conditions": conditions],
            ["type": "conditions_agreed", "side": "away", "captain_name": "Hal"],
            ["type": "toss_recorded", "winner": "home", "decision": "bat"],
            ["type": "xi_selected", "side": "home", "players": home, "captain_id": home[0]["id"]!],
            ["type": "xi_selected", "side": "away", "players": away, "captain_id": away[0]["id"]!],
            ["type": "innings_started", "innings_index": 0, "batting": "home",
             "striker_id": home[0]["id"]!, "non_striker_id": home[1]["id"]!,
             "bowler_id": away[0]["id"]!, "super_over": false],
            ball(1),
        ])
        launch(as: secretary)

        // Home: the match in progress, its score in the row.
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(reveal("Lords v Hemel", timeout: 25).exists, "the live match is not on Home")
        sleep(2) // connected
        try post([ball(6, six: true)])
        XCTAssertTrue(element(containing: "7/0").waitForExistence(timeout: 15), "Home's score did not move")
        capture("Live-home-score")

        // The fixture: the summary moves, and the four is celebrated.
        element(containing: "Lords v Hemel").tap()
        XCTAssertTrue(app.buttons["Full scorecard"].waitForExistence(timeout: 15))
        sleep(2)
        try post([ball(4, four: true)])
        XCTAssertTrue(element(containing: "11/0").waitForExistence(timeout: 15), "the fixture's score did not move")
        capture("Live-moment-four")

        // Somebody reading the card sees the wicket go down.
        app.buttons["Full scorecard"].tap()
        sleep(2)
        try post([["type": "wicket_recorded", "kind": "bowled", "batter_id": home[1]["id"]!,
                   "new_batter_id": home[2]["id"]!, "runs": 0]])
        XCTAssertTrue(element(containing: "b Hemel 1").waitForExistence(timeout: 15), "the card did not take the wicket")
        capture("Live-moment-wicket")
    }
}
