import XCTest

/// The narrated video tour: a season on the phone, in five parts.
///
///   1. a player joins a club and is picked
///   2. saying whether you can play
///   3. the captain picking the side
///   4. a twenty-over match, ball by ball
///   5. the rest of what the cricket section does
///
/// `scripts/record-tour-video.sh` films the Simulator while this runs and captions the footage
/// from the markers in `TourNarration`. It is a test as well as a film: the spine of every part
/// is asserted, so a silent failure is a failure.
///
///   ./scripts/start.sh --no-ios && ./scripts/seed-area.py
///   ./scripts/record-tour-video.sh
///
/// Needs the seeded season (`scripts/seed-area.py`) and, for the joining-a-club part, an API with
/// verification switched on and Mailpit behind it; it says so and skips otherwise.
final class FishersTourUITests: APITourCase {

    private var world: SeedManifest!

    /// A twenty-over match is twenty overs of tapping: XCTest's ten minutes a test is not enough,
    /// and the command-line override does not always reach the runner.
    override var executionTimeAllowance: TimeInterval {
        get { 2700 }
        set { super.executionTimeAllowance = newValue }
    }

    override func setUp() {
        super.setUp()
        // A missing screen should not stop the rest of the film; failures are still reported.
        continueAfterFailure = true
        // Plot the boundaries and let the singles be: asking after every single makes for a long
        // evening on a twenty-over game.
        app.launchArguments += ["-cricket_wheel_mode", "boundaries"]
    }

    override func tearDown() {
        // The recorder reads these back out of the result bundle to caption the footage.
        TourNarration.attach(to: self)
        super.tearDown()
    }

    // MARK: Helpers

    /// Marks the moment this screen was ready, keeps a still of it, and on a filmed run holds it
    /// long enough for its caption to be read.
    private func snapshot(_ name: String) {
        linger(1.2)
        TourNarration.beat(name)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let reading = TourNarration.readingSeconds(for: name)
        if reading > 0 { linger(reading) }
    }

    /// iOS offers to save the password of its own accord, over whatever comes next. Which
    /// process owns that alert has moved between releases, so look in both.
    private func dismissSystemPrompts(timeout: TimeInterval = 8) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for source in [app, springboard] {
                for label in ["Not Now", "Not now", "Never for This App", "Dismiss"] {
                    let button = source!.buttons[label]
                    if button.exists, button.isHittable {
                        button.tap()
                        linger(0.6)
                        return
                    }
                }
            }
            linger(0.4)
        }
    }

    /// Puts the software keyboard away, when there is one. A field under it takes the key's tap
    /// rather than its own.
    private func dismissKeyboard() {
        guard app.keyboards.count > 0 else { return }
        for key in ["return", "Done", "Next", "Search"] where app.keyboards.buttons[key].exists {
            app.keyboards.buttons[key].tap()
            linger(0.4)
            return
        }
        app.swipeDown(velocity: .slow)
    }

    /// Fills a field and puts the keyboard away again: the next field down is under it
    /// otherwise, and the tap lands on a key instead.
    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no field to type \(text) into")
        dismissKeyboard()
        scrollTo(field).tap()
        // iOS offers to invent a password on a new-password field, over the top of it.
        let suggestion = app.buttons["Fill Strong Password"]
        if suggestion.waitForExistence(timeout: 2) {
            let close = app.buttons.matching(NSPredicate(
                format: "label IN {'Close', 'Not Now', 'Dismiss', 'Choose My Own Password'}")).firstMatch
            if close.waitForExistence(timeout: 3) { close.tap() }
            linger(0.6)
            field.tap()
        }
        field.typeText(text)
        // Put the software keyboard away when there is one; with a hardware keyboard attached
        // there is nothing to dismiss.
        dismissKeyboard()
    }

    private func loadWorld() throws -> SeedManifest {
        if world == nil { world = try SeedManifest.load() }
        return world
    }

    @discardableResult
    private func signIn(_ email: String, password: String) throws -> String {
        let tokens = try api("POST", "/auth/login", token: nil,
                             body: ["identifier": email, "password": password])
        let access = try XCTUnwrap(tokens["access_token"] as? String)
        let refresh = try XCTUnwrap(tokens["refresh_token"] as? String)
        launch(as: Account(access: access, refresh: refresh, email: email))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30),
                      "signing in never reached the tab bar")
        return access
    }

    /// This Saturday's league fixture at the hero's own club. An away fixture is the other
    /// club's event and theirs to open, so it is no good to a tour of this one.
    private func saturdayFixture(token: String) throws -> [String: Any]? {
        guard let club = try apiList("/me/clubs", token: token).first,
              let clubId = club["id"] as? String else { return nil }
        let events = try apiList("/events?club_id=\(clubId)&per_page=100", token: token)
        return events.first { event in
            (event["event_subtype"] as? String) == "league_match"
                && (event["status"] as? String) == "scheduled"
        }
    }

    // MARK: 1 · A player joins a club

    func test1JoiningAClub() throws {
        try skipWithoutAnAPI()
        let seed = try loadWorld()
        let hero = try api("POST", "/auth/login", token: nil,
                           body: ["identifier": seed.hero.email, "password": seed.password])
        let heroToken = try XCTUnwrap(hero["access_token"] as? String)
        try skipUnlessVerificationIsOn(heroToken)

        // …and if it still gets in the way, the monitor catches it on the next tap.
        addUIInterruptionMonitor(withDescription: "Save Password") { alert in
            for label in ["Not Now", "Not now"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        let name = "Marcus Adeyemi"
        let email = "marcus.adeyemi-\(stamp)@fishers.test"
        launch()

        TourNarration.chapter("A player joins a club", "Signing up, confirming, and being picked")
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 30), "no sign-in screen")
        snapshot("onb-01-welcome")

        app.buttons["Need an account? Sign up"].tap()
        XCTAssertTrue(app.staticTexts["Join your club"].waitForExistence(timeout: 10))
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'I play for a club'"))
            .firstMatch.tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        type(name, into: nameField)
        type(email, into: app.textFields["Email"])
        type(Self.password, into: app.secureTextFields["Password"])
        snapshot("onb-02-signup")
        dismissKeyboard()
        app.buttons["Create account"].tap()
        dismissSystemPrompts()

        // The quick start: a sport and a number, and nothing else.
        let sport = app.buttons["Cricket"]
        XCTAssertTrue(sport.waitForExistence(timeout: 30), "the quick start never opened")
        dismissSystemPrompts(timeout: 4)
        sport.tap()
        let phone = app.textFields["07700 900123"]
        if phone.waitForExistence(timeout: 5) {
            type(String(format: "07700 9%05d", stamp % 100_000), into: phone)
        }
        snapshot("onb-03-quickstart")
        app.buttons["Continue"].firstMatch.tap()

        // Handed their profile link, which is how a secretary finds them.
        if app.buttons["Get my profile link"].waitForExistence(timeout: 20) {
            app.buttons["Get my profile link"].tap()
            snapshot("onb-05-profile-link")
            app.buttons["Done"].firstMatch.tap()
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "never reached the app")
        snapshot("onb-06-home-waiting")

        // Confirming the address, because joining somebody's membership list asks for it.
        tab("Profile")
        let confirm = scrollTo(element(containing: "Confirm your email"))
        if confirm.exists {
            confirm.tap()
            // The code is on its way as the screen opens; this reads it out of Mailpit the way
            // the player reads it in their inbox.
            let code = try codeFromMailpit(for: email)
            let field = app.textFields["••••••"]
            if field.waitForExistence(timeout: 15) {
                snapshot("onb-04-confirm")
                field.tap()
                field.typeText(code)
                linger(1.5)
                // Six digits confirm themselves; the button is for a code typed a digit short.
                let button = app.buttons["Confirm"].firstMatch
                if button.exists, button.isHittable { button.tap() }
                linger(2)
            }
            back()
        }
        tab("Home")

        // The secretary invites them from that link, and it lands while the app is open.
        let club = try apiList("/me/clubs", token: heroToken).first
        let clubId = try XCTUnwrap(club?["id"] as? String, "the hero runs no club")
        try api("POST", "/invites", token: heroToken,
                body: ["target_type": "club", "target_id": clubId, "invited_email": email])
        // It arrives on its own while the app is open. If the app was somewhere else when it
        // landed, it is waiting on Home the next time they open it.
        let waiting = element(containing: "wants you in the club")
        if !waiting.waitForExistence(timeout: 12) {
            app.launchArguments.removeAll { $0 == "-FishersSignOutOnLaunch" }
            app.terminate()
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "the app did not come back")
            tab("Home")
            linger(2)
        }
        let accept = scrollTo(app.buttons["Accept"].firstMatch)
        if !accept.exists {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "home-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(accept.exists, "the invite never arrived")
        snapshot("onb-07-invite-arrives")
        accept.tap()
        linger(3)
        snapshot("onb-08-invite-accepted")
        snapshot("onb-09-profile-strength")

        tab("Profile")
        linger(1)
        snapshot("onb-10-profile-cricket")
        TourNarration.chapterEnd()
    }

    // MARK: 2 · Can you play on Saturday?

    func test2SayingWhetherYouCanPlay() throws {
        try skipWithoutAnAPI()
        let seed = try loadWorld()
        let opener = try XCTUnwrap(seed.super5s.home).batting[1]
        let player = seedEmail(for: opener)
        try signIn(player, password: seed.password)

        TourNarration.chapter("Can you play on Saturday?", "Availability, from both ends")
        tab("Fixtures")
        linger(2)
        snapshot("avail-01-fixtures")

        // The fixture asks the one thing it needs.
        let available = app.buttons["Available"].firstMatch
        if available.waitForExistence(timeout: 15) {
            snapshot("avail-02-answer")
            available.tap()
            linger(1.5)
            snapshot("avail-03-answered")
        }

        // The calendar is the same question the other way round.
        app.buttons["Calendar"].tap()
        linger(2)
        snapshot("avail-04-calendar")
        let saturdays = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Every Saturday'"))
        if saturdays.firstMatch.waitForExistence(timeout: 10) {
            scrollTo(saturdays.firstMatch).tap()
            linger(2)
            snapshot("avail-05-marked")
            snapshot("avail-06-usual-days")
        }

        app.buttons["List"].tap()
        let fixture = reveal(seed.super5s.title, timeout: 15)
        if fixture.exists {
            fixture.tap()
            XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 15))
            linger(1.5)
            snapshot("avail-07-event")
        }
        TourNarration.chapterEnd()
    }

    // MARK: 3 · The captain picks the side

    func test3TheCaptainPicksTheSide() throws {
        try skipWithoutAnAPI()
        let seed = try loadWorld()
        let token = try signIn(seed.hero.email, password: seed.password)

        TourNarration.chapter("The captain picks the side", "Availability, reliability and who has sat out")
        let saturday = try saturdayFixture(token: token)
        let title = (saturday?["title"] as? String) ?? "v "
        tab("Fixtures")
        let row = reveal(title, timeout: 20)
        XCTAssertTrue(row.exists, "Saturday's fixture is not in the list")
        row.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 20))

        linger(1.5)
        snapshot("sel-00-event")
        // The board is under the attendees, and there are a dozen of those.
        let board = scrollTo(element(containing: "Selection board"), swipes: 18)
        XCTAssertTrue(board.exists, "the captain is not offered the selection board")
        board.tap()
        XCTAssertTrue(app.navigationBars["Selection"].waitForExistence(timeout: 20), "no selection board")
        linger(2)
        snapshot("sel-01-board")
        app.swipeUp(velocity: .slow)
        snapshot("sel-02-signals")

        // The assistant will offer a side; the captain is the one who picks.
        let menu = app.navigationBars.buttons.element(boundBy: 1)
        if menu.exists {
            menu.tap()
            if app.buttons["Suggest from ranking"].waitForExistence(timeout: 5) {
                snapshot("sel-03-suggested")
                app.buttons["Suggest from ranking"].tap()
                linger(2.5)
            }
        }
        snapshot("sel-04-picked")

        let publish = scrollTo(button(startingWith: "Publish squad"))
        if publish.exists {
            snapshot("sel-05-publish")
            publish.tap()
            linger(3)
        }

        // It lands in the club chat with the rest of the week's arrangements.
        tab("Chats")
        let thread = element(containing: seed.club_chat)
        if thread.waitForExistence(timeout: 20) {
            thread.tap()
            linger(2.5)
            snapshot("sel-06-announced")
            back()
        }

        // …and the players picked confirm their place.
        tab("Fixtures")
        let again = reveal(title, timeout: 20)
        if again.exists {
            again.tap()
            linger(2)
            snapshot("sel-07-confirm")
        }
        TourNarration.chapterEnd()
    }

    // MARK: 4 · A T20, ball by ball

    func test4TwentyOverMatch() throws {
        try skipWithoutAnAPI()
        let seed = try loadWorld()
        let fixture = try XCTUnwrap(seed.t20_tonight, "this season has no T20 to play — reseed")
        let home = try XCTUnwrap(fixture.home)
        let away = try XCTUnwrap(fixture.away)
        for side in [home, away] {
            try XCTSkipUnless(side.bowlers.count >= 5 && side.batting.count >= 11,
                              "\(side.name) cannot field 11 with five bowlers — reseed")
        }
        try signIn(seed.hero.email, password: seed.password)

        TourNarration.chapter("A T20, ball by ball", "Twenty overs a side, scored on the phone")
        tab("Fixtures")
        let row = reveal(fixture.title, timeout: 20)
        XCTAssertTrue(row.exists, "tonight's T20 is not in the list")
        row.tap()
        linger(1.5)
        snapshot("t20-01-fixture")
        // A match can only be started once. If this fixture has been scored already — a previous
        // take of the film, say — say so rather than filming a resumed innings.
        let start = app.buttons["Start match"]
        if !start.waitForExistence(timeout: 20) {
            let resumed = app.buttons.matching(NSPredicate(
                format: "label BEGINSWITH 'Continue scoring' OR label BEGINSWITH 'Reopen scoring'")).firstMatch
            try XCTSkipIf(resumed.exists,
                          "this T20 has already been scored — reseed for another take")
            XCTFail("the captain cannot start the match")
            return
        }
        start.tap()

        // The terms, as the two captains settle them.
        XCTAssertTrue(app.navigationBars["Start match"].waitForExistence(timeout: 20))
        linger(1)
        snapshot("t20-02-terms")
        scrollTo(button(startingWith: "Propose these terms")).tap()
        let agree = app.buttons["Agree"].firstMatch
        XCTAssertTrue(agree.waitForExistence(timeout: 15), "no agreement for the visitors")
        agree.tap()
        let captain = app.textFields["Name"]
        XCTAssertTrue(captain.waitForExistence(timeout: 10))
        captain.tap()
        captain.typeText(away.captain)
        app.navigationBars.buttons["Agree"].tap()
        snapshot("t20-03-agreed")
        app.buttons["Continue to the toss"].tap()

        XCTAssertTrue(app.buttons["Record toss"].waitForExistence(timeout: 10))
        app.buttons[away.name].firstMatch.tap()
        app.buttons["Bowl"].firstMatch.tap()
        snapshot("t20-04-toss")
        app.buttons["Record toss"].tap()

        pickSide(home, confirm: "Confirm \(home.name)")
        snapshot("t20-05-sheet")
        turnPage()
        pickSide(away, confirm: "Confirm \(away.name)")

        XCTAssertTrue(app.buttons["Start innings"].waitForExistence(timeout: 20), "no openers to name")
        pick("Bowler", away.bowlers[0])
        snapshot("t20-06-openers")
        app.buttons["Start innings"].tap()
        XCTAssertTrue(app.navigationBars["LIVE"].waitForExistence(timeout: 20), "the innings did not start")

        innings(bowling: away, keeper: away.keeper, first: true)

        // The break, and the chase.
        let second = app.buttons["Start second innings"]
        XCTAssertTrue(second.waitForExistence(timeout: 30), "the innings did not close")
        snapshot("t20-14-innings-break")
        second.tap()
        XCTAssertTrue(app.navigationBars["Second innings"].waitForExistence(timeout: 15))
        pick("Bowler", home.bowlers[0])
        app.navigationBars.buttons["Start"].tap()
        linger(1.5)
        snapshot("t20-15-target")

        innings(bowling: home, keeper: home.keeper, first: false)

        let result = element(containing: "won by")
        XCTAssertTrue(result.waitForExistence(timeout: 30), "the match did not finish")
        snapshot("t20-17-result")

        if app.buttons["Award"].waitForExistence(timeout: 10) {
            app.buttons["Award"].tap()
            let pick = app.buttons[home.bowlers[4]].firstMatch
            if pick.waitForExistence(timeout: 10) { pick.tap() }
            linger(1.5)
            snapshot("t20-18-potm")
        }
        if app.buttons["Scorecard"].waitForExistence(timeout: 10) {
            app.buttons["Scorecard"].tap()
            XCTAssertTrue(app.navigationBars["Scorecard"].waitForExistence(timeout: 15))
            linger(1.5)
            snapshot("t20-19-scorecard")
            app.swipeUp(velocity: .slow)
            linger(1.2)
            app.navigationBars.buttons["Done"].tap()
        }
        TourNarration.chapterEnd()
    }

    /// Twenty overs as a scorer types them: watchful, then wickets, then the arms going. The
    /// middle of it is cut from the film — the tour still has to tap every ball, but nobody needs
    /// to watch the eighth over of a demo innings.
    private func innings(bowling: SeedManifest.Side, keeper: String, first: Bool) {
        let rota = [0, 1, 0, 1, 2, 3, 2, 3, 4, 0, 4, 1, 2, 3, 4, 0, 1, 2, 3, 4]
        let shapes: [[Ball]] = [
            [.runs(1), .runs(0), .four(.cover), .runs(1), .runs(0), .runs(2)],
            [.runs(0), .runs(1), .runs(1), .runs(2), .runs(0), .runs(1)],
            [.six(.longOn), .runs(1), .runs(0), .four(.midwicket), .runs(1), .runs(1)],
            [.runs(1), .runs(2), .runs(0), .runs(1), .four(.point), .runs(0)],
            [.runs(0), .runs(1), .runs(2), .runs(1), .runs(1), .runs(0)],
        ]
        let wicketOvers: Set<Int> = first ? [2, 7, 11, 16, 19] : [1, 6, 9, 13, 17]
        let kinds = ["Caught", "Bowled", "LBW", "Caught", "Stumped"]
        var wicketsTaken = 0
        var cutFrom: Date?

        for index in 0..<20 {
            let bowler = index == 0 ? nil : bowling.bowlers[rota[index] % bowling.bowlers.count]
            var balls = shapes[first ? index % shapes.count : (index + 2) % shapes.count]
            if wicketOvers.contains(index) {
                let kind = kinds[wicketsTaken % kinds.count]
                let fielder = kind == "Bowled" || kind == "LBW" ? nil
                    : (kind == "Stumped" ? keeper : bowling.batting[(index + 3) % 11])
                balls[balls.count - 2] = .out(kind, fielder)
                wicketsTaken += 1
            }

            // The over the free hit is in is scored in two halves, so the banner is still up when
            // the caption for it lands.
            // An over is six legal balls: an extra is an extra ball, not one of the six, so the
            // half either side of a caption still adds up to an over.
            if first, index == 3 {
                over(bowler: bowler, [balls[0], .noBall])
                snapshot("t20-12-free-hit")
                over(bowler: nil, Array(balls.dropFirst(1)))
            } else if first, index == 2 {
                over(bowler: bowler, [balls[0], .wide])
                snapshot("t20-11-extras")
                over(bowler: nil, Array(balls.dropFirst(1)))
            } else {
                over(bowler: bowler, balls)
            }

            guard first else {
                if index == 1 { cutFrom = Date() }
                if index == 18 {
                    if let from = cutFrom { TourNarration.cut(from: from); cutFrom = nil }
                    snapshot("t20-16-last-over")
                }
                continue
            }
            switch index {
            case 0: snapshot("t20-07-first-over")
            case 1: snapshot("t20-08-boundary"); snapshot("t20-09-powerplay")
            case 2: snapshot("t20-10-wicket")
            case 3: snapshot("t20-13-bowler-gate"); cutFrom = Date()
            case 18: if let from = cutFrom { TourNarration.cut(from: from); cutFrom = nil }
            default: break
            }
        }
        if let from = cutFrom { TourNarration.cut(from: from) }
    }

    // MARK: 5 · The rest of the cricket

    func test5TheRestOfTheCricket() throws {
        try skipWithoutAnAPI()
        let seed = try loadWorld()
        try signIn(seed.hero.email, password: seed.password)

        TourNarration.chapter("The rest of the cricket", "The card, the wheel, the season and the book")

        // The card of the match just played, and what else is built from the same log.
        tab("Fixtures")
        app.buttons["Scores"].tap()
        linger(1.5)
        let finished = app.buttons["Finished"].firstMatch
        if finished.waitForExistence(timeout: 10) { finished.tap() }
        linger(2)
        snapshot("ckt-04-scores")
        let result = reveal("won by", timeout: 20)
        XCTAssertTrue(result.exists, "no finished match to open")
        result.tap()
        XCTAssertTrue(app.buttons["Full scorecard"].waitForExistence(timeout: 20))
        snapshot("ckt-05-result")
        app.buttons["Full scorecard"].tap()
        XCTAssertTrue(app.navigationBars["Scorecard"].waitForExistence(timeout: 15))
        linger(1.5)

        if app.buttons["Wagon wheel"].waitForExistence(timeout: 10) {
            app.buttons["Wagon wheel"].tap()
            linger(2)
            snapshot("ckt-01-wagon-wheel")
            app.buttons["Commentary"].tap()
            linger(2)
            snapshot("ckt-02-commentary")
        }
        back()
        back()
        app.buttons["List"].tap()

        // The match the 2nd XI are playing at the same time, on somebody else's phone.
        tab("Home")
        let live = reveal("2nd XI", timeout: 20)
        if live.exists {
            linger(1)
            snapshot("ckt-10-live-match")
            live.tap()
            linger(2)
            let share = app.buttons["Share live scoreboard"]
            if share.waitForExistence(timeout: 10) {
                share.tap()
                if app.buttons["Share via WhatsApp, Mail…"].waitForExistence(timeout: 5) {
                    snapshot("ckt-03-share")
                    app.buttons["Share via WhatsApp, Mail…"].tap()
                    linger(2.5)
                    let close = app.buttons["Close"].firstMatch
                    if close.waitForExistence(timeout: 8) { close.tap() }
                }
            }
            back()
        }

        // The scorer's other moves, on the match just finished.
        tab("Fixtures")
        let t20 = reveal(seed.t20_tonight?.title ?? "T20", timeout: 20)
        if t20.exists {
            t20.tap()
            let reopen = scrollTo(button(startingWith: "Reopen scoring"))
            if reopen.exists {
                reopen.tap()
                if app.navigationBars["LIVE"].waitForExistence(timeout: 20) {
                    let menu = app.navigationBars.buttons.element(boundBy: 2)
                    menu.tap()
                    linger(1)
                    snapshot("ckt-11-scorer-menu")
                    if app.buttons["Correct an earlier ball"].waitForExistence(timeout: 5) {
                        app.buttons["Correct an earlier ball"].tap()
                        linger(2)
                        snapshot("ckt-13-correction")
                        app.navigationBars.buttons["Cancel"].firstMatch.tap()
                    }
                    let menuAgain = app.navigationBars.buttons.element(boundBy: 2)
                    menuAgain.tap()
                    if app.buttons["Hand the book over"].waitForExistence(timeout: 5) {
                        app.buttons["Hand the book over"].tap()
                        linger(2)
                        snapshot("ckt-12-handover")
                        app.buttons["Close"].firstMatch.tap()
                    }
                    back()
                }
            }
            back()
        }

        // The season the cards add up to, and the club's shop window.
        tab("Clubs")
        let club = element(containing: seed.hero.club ?? "CC")
        if club.waitForExistence(timeout: 20) {
            club.tap()
            linger(1.5)
            let stats = scrollTo(element(containing: "Runs, wickets"))
            if stats.exists {
                stats.tap()
                linger(2.5)
                snapshot("ckt-06-club-stats")
                back()
            }
            let page = scrollTo(element(containing: "Your public page"))
            if page.exists {
                page.tap()
                linger(2.5)
                snapshot("ckt-08-public-page")
                back()
            }
            let more = app.navigationBars.buttons.matching(NSPredicate(format: "label == 'More'")).firstMatch
            if more.waitForExistence(timeout: 5) {
                more.tap()
                if app.buttons["QR code"].waitForExistence(timeout: 5) {
                    app.buttons["QR code"].tap()
                    linger(2)
                    snapshot("ckt-09-qr")
                    back()
                }
            }
            back()
        }

        tab("Profile")
        if app.segmentedControls.firstMatch.waitForExistence(timeout: 20) {
            app.segmentedControls.firstMatch.buttons["Batting"].tap()
            linger(2)
            snapshot("ckt-07-career")
        }
        tab("Home")
        linger(1.5)
        snapshot("ckt-14-home")
        TourNarration.chapterEnd()
    }

    // MARK: Team sheets

    /// Picks a side in batting order from the club's squad, names the keeper, and confirms it.
    private func pickSide(_ side: SeedManifest.Side, confirm: String) {
        XCTAssertTrue(app.staticTexts["From the club"].waitForExistence(timeout: 30),
                      "\(side.name)'s squad is not offered")
        for name in side.batting {
            let player = scrollTo(button(startingWith: name))
            XCTAssertTrue(player.exists && player.isHittable, "\(name) is not in \(side.name)'s squad")
            player.tap()
            linger(0.25)
        }
        pick("Wicketkeeper", side.keeper)
        linger(0.8)
        let done = button(startingWith: confirm)
        XCTAssertTrue(done.waitForExistence(timeout: 5), "no way to confirm \(side.name)")
        done.tap()
        linger(1)
    }

    /// The sheets are pages; the indicator is the one place a swipe cannot delete a player by
    /// mistake.
    private func turnPage() {
        let dots = app.pageIndicators.firstMatch
        if dots.waitForExistence(timeout: 5) {
            dots.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        } else {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'batting order'"))
                .firstMatch.swipeLeft()
        }
        linger(1)
    }
}
