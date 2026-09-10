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

    // MARK: Helpers

    private func signIn() {
        let field = app.textFields.firstMatch
        guard field.waitForExistence(timeout: 15) else {
            // Already signed in from a previous run on this Simulator.
            return
        }
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
