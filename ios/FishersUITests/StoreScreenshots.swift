import XCTest

/// The App Store screenshots, taken against the world `scripts/seed-area.py`
/// builds, as Hemel Hempstead Town's captain sees it.
///
/// Each screen is a test attachment named `NN-what`, in the order the listing
/// shows them. `scripts/store-screenshots.sh` runs this on the iPhone and iPad
/// sizes App Store Connect asks for and pulls the PNGs out of the result.
///
/// A screen that will not open is left out rather than failing the run: a
/// listing with six good screenshots beats no listing.
final class StoreScreenshots: APITourCase {

    func testStoreScreenshots() throws {
        try skipWithoutAnAPI()
        let world = try SeedManifest.load()
        let tokens = try api("POST", "/auth/login", token: nil,
                             body: ["identifier": world.hero.email, "password": world.password])
        let access = try XCTUnwrap(tokens["access_token"] as? String)
        let refresh = try XCTUnwrap(tokens["refresh_token"] as? String)
        launch(as: Account(access: access, refresh: refresh, email: world.hero.email))
        // iPad draws the tabs as buttons along the top, not as a tab bar.
        XCTAssertTrue(app.buttons["Home"].firstMatch.waitForExistence(timeout: 30), "signing in never reached the tabs")

        // Nothing in front of the app: the system's notification prompt, then
        // the nudge to finish a profile.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 8) { allow.tap() }
        let later = app.buttons["Remind me later"]
        if later.waitForExistence(timeout: 5) { later.tap() }

        // 1 · Home, with the 2nd XI's T20 live on it.
        _ = element(containing: "2nd XI").waitForExistence(timeout: 20)
        settle()
        capture("01-home")

        // 2 · The live match, then its scorecard.
        let live = reveal("2nd XI", timeout: 10)
        if live.exists {
            live.tap()
            let scorecard = app.buttons["Full scorecard"]
            if scorecard.waitForExistence(timeout: 20) {
                settle()
                capture("02-live-match")
                scorecard.tap()
                if app.navigationBars["Scorecard"].waitForExistence(timeout: 15) {
                    settle()
                    capture("03-scorecard")
                    back()
                }
            }
            back()
        }
        app.swipeDown()

        // 4 · Fixtures, and 5 · the calendar.
        go("Fixtures")
        _ = element(containing: "Hemel Hempstead Town").waitForExistence(timeout: 20)
        settle()
        capture("04-fixtures")
        let calendar = app.buttons["Calendar"]
        if calendar.waitForExistence(timeout: 5) {
            calendar.tap()
            settle()
            capture("05-calendar")
            let list = app.buttons["List"]
            if list.waitForExistence(timeout: 5) { list.tap() }
        }

        // 6 · The club, and 7 · its season's figures.
        go("Clubs")
        let clubName = world.hero.club ?? "Hemel Hempstead Town CC"
        let club = element(containing: clubName)
        if club.waitForExistence(timeout: 20) {
            club.tap()
            if app.navigationBars[clubName].waitForExistence(timeout: 15) {
                settle()
                capture("06-club")
                let stats = element(containing: "Runs, wickets")
                if stats.waitForExistence(timeout: 10) {
                    stats.tap()
                    settle(3)
                    capture("07-club-stats")
                    back()
                }
            }
            back()
        }

        // 8 · The player's own season.
        go("Profile")
        let sections = app.segmentedControls.firstMatch
        if sections.waitForExistence(timeout: 20) {
            sections.buttons["Batting"].tap()
            settle()
            capture("08-profile-batting")
        }
    }

    /// A tab by name: the tab bar on iPhone, a button along the top on iPad.
    private func go(_ name: String) {
        let bar = app.tabBars.buttons[name].firstMatch
        let button = bar.exists ? bar : app.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "no \(name) tab")
        button.tap()
    }

    /// Long enough for images and numbers to land, so no shot has a spinner in it.
    private func settle(_ seconds: Double = 2.5) {
        linger(seconds)
    }
}
