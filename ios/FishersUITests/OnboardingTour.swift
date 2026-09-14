import XCTest

/// The first minutes of a new account, driven through the real app.
///
/// Accounts are made through the API with a finished player profile — the
/// profile setup screens have their own coverage — and then everything the
/// guide asks for is done by tapping: the code from the email, the club, the
/// profile link, the invite.
final class OnboardingTour: APITourCase {

    func testSignUpAsksWhichWayIn() throws {
        try skipWithoutAnAPI()
        launch()
        let signUp = app.buttons["Need an account? Sign up"]
        XCTAssertTrue(signUp.waitForExistence(timeout: 15), "no way to sign up")
        signUp.tap()

        let secretary = app.buttons.containing(NSPredicate(format: "label CONTAINS 'I run a club'")).firstMatch
        XCTAssertTrue(secretary.waitForExistence(timeout: 5), "signup does not ask how they will use Fishers")
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'I play for a club'")).firstMatch.exists)
        secretary.tap()
        XCTAssertTrue(secretary.isSelected, "picking a role does not show as picked")
        capture("Signup-role")
    }

    func testSecretaryConfirmsTheirEmailThenStartsAClub() throws {
        try skipWithoutAnAPI()
        let account = try makeAccount("sec", name: "Sam Secretary", role: "secretary")
        try skipUnlessVerificationIsOn(account.access)
        launch(as: account)

        XCTAssertTrue(app.staticTexts["Let's set up your club"].waitForExistence(timeout: 20),
                      "a new secretary is not shown the guide")
        let codeField = app.textFields["Verification code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 10), "the first step is not the code")
        capture("Guide-1-verify")

        codeField.tap()
        codeField.typeText(try codeFromMailpit(for: account.email))

        let start = app.buttons["Start your club"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "confirming the code did not move the guide on")
        capture("Guide-2-start-club")
        start.tap()

        let name = app.textFields["Fishers CC"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the new club form did not open")
        name.tap()
        name.typeText("Tour CC \(stamp % 10000)")
        app.buttons["Create"].tap()

        // Creating a club opens it, with a welcome.
        let later = app.buttons["I'll do it later"]
        XCTAssertTrue(later.waitForExistence(timeout: 20), "the new club did not open with its welcome")
        later.tap()
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(app.buttons["Add a team"].waitForExistence(timeout: 20)
                      || app.staticTexts["Add your first team"].waitForExistence(timeout: 5),
                      "after the club, the guide should ask for a team")
        capture("Guide-3-add-team")
    }

    func testPlayerSharesTheirLinkThenAcceptsTheInvite() throws {
        try skipWithoutAnAPI()
        let player = try makeAccount("player", name: "Pat Player", role: "player", verified: true)
        launch(as: player)

        XCTAssertTrue(app.staticTexts["Let's get you into your club"].waitForExistence(timeout: 20),
                      "a new player is not shown the guide")
        let getLink = app.buttons["Get my profile link"]
        XCTAssertTrue(getLink.waitForExistence(timeout: 10), "the share step is not next")
        getLink.tap()
        let link = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '/p/'")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10), "no profile link appeared")
        capture("Guide-player-link")

        // A secretary elsewhere invites them to their club.
        let secretary = try makeAccount("inviter", name: "Ivy Inviter", role: "secretary", verified: true)
        let club = try api("POST", "/clubs", token: secretary.access,
                           body: ["name": "Invite Test \(stamp % 10000)", "sport_types": ["cricket"]])
        try api("POST", "/invites", token: secretary.access,
                body: ["target_type": "club", "target_id": club["id"] as! String, "invited_email": player.email])

        // Away and back, as when the invite arrives while the phone is in a pocket.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        let accept = app.buttons["Accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 20), "the invite never showed on Home")
        XCTAssertTrue(app.staticTexts["Waiting for you"].exists)
        capture("Home-invite-waiting")
        accept.tap()

        XCTAssertTrue(accept.waitForNonExistence(timeout: 20), "accepting did not clear the invite")
        XCTAssertFalse(app.staticTexts["Let's get you into your club"].exists,
                       "in a club now, the guide should be gone")
        capture("Home-joined")
    }
}
