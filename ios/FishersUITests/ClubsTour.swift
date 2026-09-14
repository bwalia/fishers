import XCTest

/// The Clubs tab and a club, from a secretary's phone.
final class ClubsTour: APITourCase {

    /// iOS 26's tab bar reports each tab twice while it settles, so "the"
    /// Clubs button is the first of them.
    private func openClubsTab() {
        let tab = app.tabBars.buttons["Clubs"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "no Clubs tab")
        tab.tap()
    }

    func testTheListIsSearchedOnTheServer() throws {
        try skipWithoutAnAPI()
        let secretary = try makeAccount("list", name: "Lee List", role: "secretary", verified: true)
        let tag = stamp % 100000
        for name in ["Alpha \(tag) CC", "Bravo \(tag) CC", "Charlie \(tag) Pickleball"] {
            try api("POST", "/clubs", token: secretary.access, body: ["name": name, "sport_types": ["cricket"]])
        }
        launch(as: secretary)

        openClubsTab()
        XCTAssertTrue(element(containing: "3 clubs").waitForExistence(timeout: 20), "the count is missing")
        XCTAssertTrue(element(containing: "Bravo \(tag) CC").exists)
        capture("Clubs-list")

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "no search")
        search.tap()
        search.typeText("Bravo")
        XCTAssertTrue(element(containing: "1 club").waitForExistence(timeout: 10), "search did not narrow the list")
        XCTAssertFalse(element(containing: "Alpha \(tag) CC").exists)
        capture("Clubs-search")
    }

    func testStartingAClubOpensItWithItsSetup() throws {
        try skipWithoutAnAPI()
        let secretary = try makeAccount("setup", name: "Sue Setup", role: "secretary", verified: true)
        launch(as: secretary)
        let clubName = "Setup \(stamp % 100000) CC"

        openClubsTab()
        let start = app.buttons["Start a club"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        let name = app.textFields["Fishers CC"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText(clubName)
        app.buttons["Create"].tap()

        XCTAssertTrue(app.staticTexts["\(clubName) is ready"].waitForExistence(timeout: 20), "no welcome")
        capture("Club-welcome")
        app.buttons["I'll do it later"].tap()

        XCTAssertTrue(app.staticTexts["Get \(clubName) ready for its first match"].waitForExistence(timeout: 15),
                      "the setup checklist is missing")
        capture("Club-setup")

        // A team, from the checklist.
        element(containing: "A 1st XI, a Sunday side").tap()
        let team = app.textFields["1st XI"]
        XCTAssertTrue(team.waitForExistence(timeout: 10), "the team sheet did not open")
        team.tap()
        team.typeText("Sunday XI")
        app.buttons["Create"].tap()
        XCTAssertTrue(element(containing: "2 of 5 done").waitForExistence(timeout: 15), "adding a team did not tick")
        XCTAssertTrue(reveal("Sunday XI").exists, "the new team is not listed")
        app.swipeDown()
        app.swipeDown()

        // A ground, from the checklist.
        element(containing: "So every fixture says where to turn up").tap()
        let ground = app.textFields["Highbury Fields"]
        XCTAssertTrue(ground.waitForExistence(timeout: 10), "the ground sheet did not open")
        ground.tap()
        ground.typeText("Gadebridge Park")
        app.buttons["Add"].tap()
        XCTAssertTrue(element(containing: "3 of 5 done").waitForExistence(timeout: 15), "the checklist did not tick")
        capture("Club-setup-progress")
        XCTAssertTrue(reveal("Gadebridge Park").exists, "the ground is not listed")
        capture("Club-teams-grounds")

        // The public page, published.
        reveal("Your public page").tap()
        XCTAssertTrue(app.staticTexts["Not published"].waitForExistence(timeout: 15), "the public page editor did not open")
        capture("Club-public-page-editor")
        let publish = reveal("Publish it")
        XCTAssertTrue(publish.exists, "no way to publish")
        publish.tap()
        XCTAssertTrue(element(containing: "Take it offline").waitForExistence(timeout: 15), "publishing did not take")
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["Live"].waitForExistence(timeout: 10), "the page does not say it is live")
        capture("Club-public-page-live")
    }

    func testASecretaryCanCaptainTheirOwnSide() throws {
        try skipWithoutAnAPI()
        let secretary = try makeAccount("captain", name: "Cap Secretary", role: "secretary", verified: true)
        let clubName = "Captain \(stamp % 100000) CC"
        let club = try api("POST", "/clubs", token: secretary.access, body: ["name": clubName, "sport_types": ["cricket"]])
        launch(as: secretary)

        openClubsTab()
        let row = element(containing: clubName)
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        let members = reveal("1 member")
        XCTAssertTrue(members.exists, "the club did not open")
        members.tap()

        let badge = app.buttons.containing(NSPredicate(format: "label CONTAINS 'role, now Club secretary'")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 15), "no way to change your own role")
        badge.tap()
        let choice = element(containing: "Secretary & captain")
        XCTAssertTrue(choice.waitForExistence(timeout: 10), "Secretary & captain is not offered")
        choice.tap()
        capture("Role-secretary-captain")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'now Secretary & captain'")).firstMatch.waitForExistence(timeout: 15),
                      "the badge does not say captain")
        let roster = try apiList("/clubs/\(club["id"] as! String)/members", token: secretary.access)
        XCTAssertEqual(roster.first?["is_captain"] as? Bool, true, "the server was not told")
        capture("Roster-secretary-captain")
    }

    func testInvitingAPlayerFromTheLinkTheySent() throws {
        try skipWithoutAnAPI()
        let player = try makeAccount("linked", name: "Lin Linked", role: "player")
        let link = try api("POST", "/me/share-link", token: player.access, body: nil)
        let token = try XCTUnwrap(link["token"] as? String)
        let secretary = try makeAccount("reader", name: "Rae Reader", role: "secretary", verified: true)
        let clubName = "Linked \(stamp % 100000) CC"
        try api("POST", "/clubs", token: secretary.access, body: ["name": clubName, "sport_types": ["cricket"]])
        launch(as: secretary)

        openClubsTab()
        let row = element(containing: clubName)
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        let members = reveal("1 member")
        XCTAssertTrue(members.exists, "the club did not open")
        members.tap()
        let add = app.buttons["Add a member"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()

        let paste = app.textFields["Paste the link they sent you"]
        XCTAssertTrue(paste.waitForExistence(timeout: 10), "no way to use a profile link")
        paste.tap()
        paste.typeText("Hi, here's my profile: http://127.0.0.1:7311/p/\(token)")
        element(containing: "Open their profile").tap()

        XCTAssertTrue(app.staticTexts["Lin Linked"].waitForExistence(timeout: 15), "the card did not open")
        capture("Shared-card")
        app.buttons["Send the invite"].tap()
        XCTAssertTrue(element(containing: "Invite sent to Lin Linked").waitForExistence(timeout: 15), "no confirmation")

        let invites = try apiList("/invites/mine", token: player.access)
        XCTAssertTrue(invites.contains { $0["status"] as? String == "pending" && $0["target_name"] as? String == clubName },
                      "the player has no invite to accept")
        capture("Shared-card-sent")
    }
}
