import XCTest

/// Scores under Fixtures: the list of matches, and a match started from
/// nothing with the club's captain marked on the sheet for them.
final class ScoreTour: APITourCase {

    func testStartingAMatchNowPicksTheCaptain() throws {
        try skipWithoutAnAPI()
        let name = "Cap Tain"
        let secretary = try makeAccount("hub", name: name, role: "secretary", verified: true)
        let club = try api("POST", "/clubs", token: secretary.access,
                           body: ["name": "Hub \(stamp % 100000) CC", "sport_types": ["cricket"]])
        let me = try api("GET", "/me", token: secretary.access, body: nil)
        // A small club: the secretary captains the side too.
        try api("PATCH", "/clubs/\(club["id"] as! String)/members/\(me["id"] as! String)",
                token: secretary.access, body: ["role": "club_admin", "captain": true])
        launch(as: secretary)

        let tab = app.tabBars.buttons["Fixtures"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        app.buttons["Scores"].firstMatch.tap()
        let start = app.buttons["Start a match now"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "no way to start a match")
        capture("Scores-hub")
        start.tap()

        element(containing: "Opposition").tap()
        let typed = app.textFields["Opposition name"]
        XCTAssertTrue(typed.waitForExistence(timeout: 10), "the opposition picker did not open")
        typed.tap()
        typed.typeText("Hemel Strollers")
        app.buttons["Use"].tap()
        XCTAssertTrue(element(containing: "Hemel Strollers").waitForExistence(timeout: 5))
        capture("Scores-start-sheet")
        app.buttons["Start scoring"].tap()

        XCTAssertTrue(app.navigationBars["Start match"].waitForExistence(timeout: 20), "starting did not open the match")
        XCTAssertTrue(element(containing: "v Hemel Strollers").exists, "the fixture was not written from the sheet")
        capture("Scores-match-setup")
        let propose = reveal("Propose these terms")
        XCTAssertTrue(propose.isHittable, "no way to propose the terms")
        propose.tap()

        let agree = app.buttons["Agree"].firstMatch
        XCTAssertTrue(agree.waitForExistence(timeout: 10), "no agreement for the visitors")
        agree.tap()
        let captain = app.textFields["Name"]
        XCTAssertTrue(captain.waitForExistence(timeout: 10))
        captain.tap()
        captain.typeText("Hal")
        app.navigationBars.buttons["Agree"].tap()
        app.buttons["Continue to the toss"].tap()
        let toss = app.buttons["Record toss"]
        XCTAssertTrue(toss.waitForExistence(timeout: 10))
        toss.tap()

        // The sheet: picking the club's captain marks them C.
        let pick = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 20), "the club's squad is not offered")
        pick.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Captain' AND label CONTAINS %@", name))
                        .firstMatch.waitForExistence(timeout: 10),
                      "the captain was not picked for them")
        capture("Scores-sheet-captain")
    }
}
