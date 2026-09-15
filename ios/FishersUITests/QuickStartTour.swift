import XCTest

/// The first minute: a sport and a number, or nothing at all, and straight on
/// to what gets somebody playing.
final class QuickStartTour: APITourCase {

    func testAPlayerPicksASportAndIsHandedTheirLink() throws {
        try skipWithoutAnAPI()
        let player = try makeAccount("quick", name: "Pat Quick", role: "player", profile: false)
        launch(as: player)

        XCTAssertTrue(app.staticTexts["Hi Pat"].waitForExistence(timeout: 20), "no quick start for a new account")
        XCTAssertTrue(app.buttons["Skip for now"].exists, "the quick start cannot be skipped")
        XCTAssertFalse(app.buttons["Continue"].isEnabled, "Continue before a sport is picked")
        capture("QuickStart-empty")

        app.buttons["Cricket"].tap()
        let phone = app.textFields["07700 900123"]
        phone.tap()
        // Numbers are unique across accounts, so each run needs its own.
        let number = String(format: "07%09d", stamp % 1_000_000_000)
        phone.typeText(number)
        capture("QuickStart-filled")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["You're in. Now get picked."].waitForExistence(timeout: 20),
                      "a player is not handed their profile link")
        XCTAssertTrue(app.buttons["Get my profile link"].waitForExistence(timeout: 5))
        capture("QuickStart-player-link")
        app.buttons["Done"].tap()

        XCTAssertTrue(element(containing: "Your profile is 35% complete").waitForExistence(timeout: 15),
                      "Home does not say how complete the profile is")
        XCTAssertTrue(reveal("Remind me later").exists, "no way to be reminded")
        capture("QuickStart-home-strength")

        let me = try api("GET", "/me", token: player.access, body: nil)
        XCTAssertEqual(me["primary_sport"] as? String, "cricket")
        XCTAssertEqual(me["phone"] as? String, number)
    }

    func testASecretarySkipsStraightToTheirClubAndAMatch() throws {
        try skipWithoutAnAPI()
        let secretary = try makeAccount("skip", name: "Sid Skip", role: "secretary", verified: true, profile: false)
        launch(as: secretary)

        let skip = app.buttons["Skip for now"]
        XCTAssertTrue(skip.waitForExistence(timeout: 20), "no quick start for a new account")
        skip.tap()

        let name = app.textFields["Fishers CC"]
        XCTAssertTrue(name.waitForExistence(timeout: 20), "a secretary is not taken to start their club")
        capture("QuickStart-secretary-club")
        let clubName = "Skip \(stamp % 100000) CC"
        name.tap()
        name.typeText(clubName)
        app.buttons["Create"].tap()

        let addPlayers = app.buttons["Add players"]
        XCTAssertTrue(addPlayers.waitForExistence(timeout: 20), "the new club does not lead to adding players")
        XCTAssertTrue(app.staticTexts["Start your first match"].exists)
        capture("QuickStart-club-welcome")
        addPlayers.tap()
        XCTAssertTrue(app.navigationBars["Add a member"].waitForExistence(timeout: 15), "adding players did not open")
        capture("QuickStart-add-players")
        app.navigationBars["Add a member"].buttons["Cancel"].tap()
        let back = app.navigationBars["Manage club"].buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()

        XCTAssertTrue(app.buttons["Start a match"].waitForExistence(timeout: 15), "the club page does not offer a match")
        capture("QuickStart-club-start-match")
    }
}
