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
        let tabs = ["Home", "Fixtures", "Chats", "Clubs", "Profile"]
        for name in tabs {
            let tab = app.tabBars.buttons[name].firstMatch
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

        app.tabBars.buttons["Profile"].firstMatch.tap()

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
        app.tabBars.buttons["Profile"].firstMatch.tap()

        // The name, set as a scorecard sets it — family name upper.
        XCTAssertTrue(app.staticTexts["CAPTAIN"].waitForExistence(timeout: 15),
                      "the hero never drew the player's name")
        XCTAssertTrue(app.staticTexts["Demo"].exists, "the given name is missing")

        // The camera button is how a photo gets on there at all.
        XCTAssertTrue(app.buttons["Add a photo"].exists || app.buttons["Change your photo"].exists,
                      "no way to set a profile picture")

        let sections = app.segmentedControls.firstMatch
        sections.buttons["Batting"].tap()
        try figures(["Runs", "Innings", "Average", "Strike rate"], for: "batting")

        sections.buttons["Bowling"].tap()
        try figures(["Wickets", "Overs", "Average", "Economy"], for: "bowling")
        capture("Profile-figures")
    }

    /// Opening a club-mate's record from the roster, and not seeing their
    /// phone number when you get there.
    func testAnotherPlayersProfileShowsFiguresAndNoContactDetails() throws {
        try skipWithoutAnAPI()
        signIn()

        app.tabBars.buttons["Clubs"].firstMatch.tap()

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

        app.tabBars.buttons["Home"].firstMatch.tap()
        // "Notifications", or "3 unread notifications" when some are waiting.
        let bell = app.buttons.matching(NSPredicate(format: "label ENDSWITH[c] 'notifications'")).firstMatch
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

    /// Opens the app as the demo account, whoever was signed in before.
    ///
    /// The tours that make their own accounts leave those signed in on the
    /// Simulator, and a profile test run as one of them fails for the wrong
    /// reason. The tokens go in at launch: signing in through the form raises
    /// the Save Password sheet over the next tap.
    private func signIn() {
        var request = URLRequest(url: URL(string: Self.apiBase + "/api/v1/auth/login")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": Self.email, "password": Self.password])
        var tokens: [String: Any]?
        let done = expectation(description: "login")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            tokens = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 15)

        guard let access = tokens?["access_token"] as? String,
              let refresh = tokens?["refresh_token"] as? String else {
            XCTFail("\(Self.email) could not sign in on \(Self.apiBase) — run scripts/seed-demo.sh")
            return
        }
        app.launchArguments += ["-FishersSignOutOnLaunch"]
        app.launchEnvironment["FISHERS_UITEST_ACCESS_TOKEN"] = access
        app.launchEnvironment["FISHERS_UITEST_REFRESH_TOKEN"] = refresh
        app.launch()

        // An account whose profile is not filled in lands on the quick start
        // rather than the tab bar, so the tour has to step past it. Skipping is
        // remembered per user in UserDefaults, which outlives the relaunch, so
        // only the first tour to sign in sees it — waiting on the skip button
        // alone would cost every later one its whole timeout. First one to
        // arrive wins.
        let skip = app.buttons["Skip for now"]
        let tabBar = app.tabBars.firstMatch
        waitForEither(skip, tabBar, timeout: 20)
        if skip.exists { skip.tap() }

        XCTAssertTrue(tabBar.waitForExistence(timeout: 20),
                      "signing in never reached the tab bar")
    }

    /// Waits until whichever of these the screen draws first is there, so a
    /// screen with two legitimate outcomes does not cost the wrong one a full
    /// timeout before it is even looked at.
    private func waitForEither(_ one: XCUIElement, _ other: XCUIElement, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !one.exists, !other.exists {
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// Asserts a discipline's figures are on screen, or says why they could not
    /// be checked. Figures are worked out from matches scored on Fishers, so an
    /// account that has not batted or bowled in one draws the empty state
    /// instead — that is the app working, and asserting against a screen that
    /// cannot hold figures would report it as broken.
    private func figures(_ names: [String], for discipline: String) throws {
        let empty = app.staticTexts["No \(discipline) figures yet"]
        waitForEither(app.staticTexts[names[0]], empty, timeout: 8)
        if empty.exists {
            throw XCTSkip("this account has no \(discipline) figures on this server")
        }
        for figure in names {
            XCTAssertTrue(app.staticTexts[figure].waitForExistence(timeout: 8),
                          "\(discipline) is missing \(figure)")
        }
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
