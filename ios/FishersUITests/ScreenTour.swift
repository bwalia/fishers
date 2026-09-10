import XCTest

/// Walks the app the way somebody holding the phone would, and saves a picture
/// of every screen it reaches.
///
/// This exists because a broken layout still compiles. The unit tests prove the
/// cricket engine is right; nothing proved the app could be *used*, and every
/// visual bug so far was found by looking rather than by reading.
///
/// Needs an API on the host — `./scripts/start.sh --no-ios`. Without one it
/// says so and stops, instead of failing as though the app were broken.
final class ScreenTour: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["FISHERS_API_URL"] = Self.apiBase
        app.launch()
    }

    /// The Simulator shares the Mac's network stack, so loopback is the host.
    private static let apiBase =
        ProcessInfo.processInfo.environment["FISHERS_API_URL"] ?? "http://127.0.0.1:7312"

    private static let email =
        ProcessInfo.processInfo.environment["FISHERS_UITEST_EMAIL"] ?? "demo@fishers.test"
    private static let password =
        ProcessInfo.processInfo.environment["FISHERS_UITEST_PASSWORD"] ?? "password123"

    // MARK: The tour

    func testSignInAndVisitEveryTab() throws {
        try skipWithoutAnAPI()
        signIn()

        // The tab bar is the app's spine: if a tab cannot be reached, the app
        // is broken however well it builds.
        let tabs = ["Home", "Calendar", "Chats", "Clubs", "Profile"]
        for name in tabs {
            let tab = app.tabBars.buttons[name]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "no \(name) tab")
            tab.tap()
            // Give the screen its first fetch before photographing it.
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 8)
            capture(name)
        }
    }

    func testProfileHasItsThreeTabs() throws {
        try skipWithoutAnAPI()
        signIn()

        app.tabBars.buttons["Profile"].tap()

        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 15),
                      "the profile never loaded")

        // The segmented control, not the tab bar — "Profile" and these names
        // appear more than once on screen.
        let sections = app.segmentedControls.firstMatch
        XCTAssertTrue(sections.waitForExistence(timeout: 10), "no Overview/Batting/Bowling control")
        for section in ["Batting", "Bowling", "Overview"] {
            let control = sections.buttons[section]
            XCTAssertTrue(control.waitForExistence(timeout: 8), "no \(section) tab on the profile")
            control.tap()
            capture("Profile-\(section)")
        }
    }

    /// The band across the top, and the figures under it. Asserted rather than
    /// only photographed: a screenshot proves nothing on its own in CI.
    func testTheProfileShowsWhoYouAreAndWhatYouHaveDone() throws {
        try skipWithoutAnAPI()
        signIn()
        app.tabBars.buttons["Profile"].tap()

        // The name, set as a scorecard sets it — family name upper.
        XCTAssertTrue(app.staticTexts["CAPTAIN"].waitForExistence(timeout: 15),
                      "the hero never drew the player's name")
        XCTAssertTrue(app.staticTexts["Demo"].exists, "the given name is missing")

        // The camera button is how a photo gets on there at all.
        XCTAssertTrue(app.buttons["Add a photo"].exists || app.buttons["Change your photo"].exists,
                      "no way to set a profile picture")

        let sections = app.segmentedControls.firstMatch
        sections.buttons["Batting"].tap()
        for figure in ["Runs", "Innings", "Average", "Strike rate"] {
            XCTAssertTrue(app.staticTexts[figure].waitForExistence(timeout: 8),
                          "batting is missing \(figure)")
        }

        sections.buttons["Bowling"].tap()
        for figure in ["Wickets", "Overs", "Average", "Economy"] {
            XCTAssertTrue(app.staticTexts[figure].waitForExistence(timeout: 8),
                          "bowling is missing \(figure)")
        }
        capture("Profile-figures")
    }

    /// Opening a club-mate's record from the roster, and not seeing their
    /// phone number when you get there.
    func testAnotherPlayersProfileShowsFiguresAndNoContactDetails() throws {
        try skipWithoutAnAPI()
        signIn()

        app.tabBars.buttons["Clubs"].tap()

        // Into a club, by the button XCTest can actually press. A SwiftUI
        // List row surfaces as a cell that is often reported unhittable, and
        // tapping the cell retries for two minutes before giving up.
        let clubs = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'CC'"))
        guard clubs.firstMatch.waitForExistence(timeout: 20) else {
            throw XCTSkip("this account is in no clubs on this server")
        }
        clubs.firstMatch.tap()

        // Any element type: a SwiftUI NavigationLink surfaces as a button on
        // some OS versions and a cell or link on others, and querying only
        // `.buttons` turned a real assertion into a silent skip.
        let link = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Open their profile'"))
            .firstMatch
        guard link.waitForExistence(timeout: 15) else {
            throw XCTSkip("this account's club has no other members to open")
        }
        link.tap()

        XCTAssertTrue(app.staticTexts["Career"].waitForExistence(timeout: 15)
                      || app.staticTexts["Nothing scored yet"].waitForExistence(timeout: 5),
                      "the profile never loaded")

        // The whole point of the narrower payload: no contact details reach
        // this screen, so none can be shown on it.
        let text = app.descendants(matching: .any).allElementsBoundByIndex
            .compactMap { $0.label }
            .joined(separator: " ")
        XCTAssertFalse(text.contains("@fishers.test"), "an email address leaked onto a teammate's profile")
        XCTAssertFalse(text.lowercased().contains("emergency"), "an emergency contact leaked")
        capture("Player-profile")
    }

    /// The notifications screen filters on the server, so the controls have
    /// to be there for it to be able to.
    func testNotificationsCanBeFiltered() throws {
        try skipWithoutAnAPI()
        signIn()

        app.tabBars.buttons["Home"].tap()
        let bell = app.buttons["Notifications"].firstMatch
        guard bell.waitForExistence(timeout: 10) else {
            throw XCTSkip("no way through to notifications from Home in this build")
        }
        bell.tap()

        XCTAssertTrue(app.textFields["Search"].waitForExistence(timeout: 10),
                      "no search on the notifications screen")
        XCTAssertTrue(app.switches["Unread only"].exists, "no unread filter")
        capture("Notifications")
    }

    // MARK: Helpers

    private func signIn() {
        // Already in? The session survives between tests on one Simulator, so
        // check for the tab bar first — waiting fifteen seconds for a login
        // field that is not there cost every later test a quarter minute.
        if app.tabBars.firstMatch.waitForExistence(timeout: 3) { return }

        let field = app.textFields.firstMatch
        guard field.waitForExistence(timeout: 15) else { return }
        field.tap()
        field.typeText(Self.email)

        let password = app.secureTextFields.firstMatch
        password.tap()
        password.typeText(Self.password)

        app.buttons["Sign in"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20),
                      "signing in never reached the tab bar")
    }

    /// A screenshot kept whatever happens next, so a failing run still shows
    /// what the screen looked like when it failed.
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func skipWithoutAnAPI() throws {
        guard let url = URL(string: Self.apiBase + "/health") else { return }
        var reachable = false
        let done = expectation(description: "health")
        URLSession.shared.dataTask(with: url) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)
        try XCTSkipUnless(reachable, "no API at \(Self.apiBase) — run ./scripts/start.sh --no-ios")
    }
}
