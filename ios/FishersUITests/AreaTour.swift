import XCTest

/// The app as a club captain round Hemel Hempstead would use it, against the
/// world `scripts/seed-area.py` builds: 36 local clubs, three rounds of league
/// cricket already played, a 2nd XI T20 in progress, and a 5-over game this
/// evening that nobody has started.
///
/// Paced to be watched — `scripts/record-area-tour.sh` films both tests — but
/// every step is still asserted, so a run that is not recorded is a test.
///
///   API_BASE=http://127.0.0.1:7312 ./scripts/seed-area.py
///   ./scripts/record-area-tour.sh
///
/// Skips, saying so, without an API or without the seed's manifest.
final class AreaTour: APITourCase {

    // MARK: The world

    struct Side: Decodable {
        let club: String
        let name: String
        let batting: [String]
        let captain: String
        let keeper: String
        let bowlers: [String]
    }

    struct Manifest: Decodable {
        struct Account: Decodable { let email: String; let name: String; let club: String? }
        struct Fixture: Decodable {
            let event_id: String
            let title: String
            let home: Side?
            let away: Side?
        }
        let password: String
        let hero: Account
        let watford_captain: Account
        let super5s: Fixture
        let live_t20: Fixture
        let club_chat: String
    }

    /// Written by the seed next to the repository's other local state. The
    /// Simulator shares the Mac's file system, so the test reads it directly.
    private func manifest() throws -> Manifest {
        let path = ProcessInfo.processInfo.environment["FISHERS_SEED_MANIFEST"]
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".dev/seed-area.json").path
        guard let data = FileManager.default.contents(atPath: path) else {
            throw XCTSkip("no seed manifest at \(path) — run scripts/seed-area.py first")
        }
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    private func signIn(_ email: String, password: String) throws {
        let tokens = try api("POST", "/auth/login", token: nil,
                             body: ["identifier": email, "password": password])
        let access = try XCTUnwrap(tokens["access_token"] as? String)
        let refresh = try XCTUnwrap(tokens["refresh_token"] as? String)
        launch(as: Account(access: access, refresh: refresh, email: email))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "signing in never reached the tab bar")
    }

    /// Long enough to read the screen on the recording.
    private func linger(_ seconds: Double = 1.6) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15), "no \(name) tab")
        button.tap()
    }

    private func back() {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.waitForExistence(timeout: 5) { button.tap() }
        linger(0.8)
    }

    private func button(startingWith text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// A menu-style picker in a form: open it, choose the option.
    private func pick(_ picker: String, _ option: String, file: StaticString = #filePath, line: UInt = #line) {
        let control = scrollTo(button(startingWith: picker))
        XCTAssertTrue(control.exists, "no \(picker) picker", file: file, line: line)
        control.tap()
        let choice = app.buttons.matching(NSPredicate(format: "label == %@", option)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "\(picker) does not offer \(option)", file: file, line: line)
        choice.tap()
    }

    // MARK: 1 · The key features

    func testKeyFeaturesAsHemelsCaptain() throws {
        try skipWithoutAnAPI()
        let world = try manifest()
        try signIn(world.hero.email, password: world.password)
        linger(2.5)

        // Home: the T20 the 2nd XI are playing right now, and what is coming up.
        let live = reveal("2nd XI", timeout: 20)
        XCTAssertTrue(live.exists, "the 2nd XI's live T20 is not on Home")
        linger()
        app.swipeUp()
        linger()
        app.swipeDown()
        linger(0.8)

        let bell = app.buttons.matching(NSPredicate(format: "label ENDSWITH[c] 'notifications'")).firstMatch
        if bell.waitForExistence(timeout: 5) {
            bell.tap()
            XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 10))
            linger()
            back()
        }

        app.buttons["Shop"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Shop"].waitForExistence(timeout: 10), "the shop did not open")
        XCTAssertTrue(element(containing: "Club cap").waitForExistence(timeout: 15), "the club shop has no stock")
        linger(2)
        back()

        // The live match, as anyone at the club follows it.
        reveal("2nd XI").tap()
        let scorecard = app.buttons["Full scorecard"]
        XCTAssertTrue(scorecard.waitForExistence(timeout: 20), "the live fixture has no scorecard")
        linger(2)
        scorecard.tap()
        XCTAssertTrue(app.navigationBars["Scorecard"].waitForExistence(timeout: 15))
        linger(2)
        app.swipeUp()
        linger()
        app.swipeUp()
        linger(1.2)
        back()
        back()

        // Fixtures: this week, the calendar, and every result so far.
        tab("Fixtures")
        linger(2)
        let saturday = reveal("Hemel Hempstead Town v ", timeout: 20)
        if saturday.exists {
            saturday.tap()
            XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 15))
            linger(2)
            let going = app.buttons["Going"]
            if going.waitForExistence(timeout: 5) { going.tap() }
            linger()
            let board = element(containing: "Selection board")
            if board.waitForExistence(timeout: 5) {
                board.tap()
                linger(2.5)
                back()
            }
            back()
        }
        app.buttons["Calendar"].tap()
        linger(2.5)
        app.buttons["Scores"].tap()
        linger(1.5)
        let finished = app.buttons["Finished"].firstMatch
        XCTAssertTrue(finished.waitForExistence(timeout: 15), "no way to see finished matches")
        finished.tap()
        linger(2)
        let result = reveal("won by", timeout: 20)
        XCTAssertTrue(result.exists, "no results among the scores")
        result.tap()
        XCTAssertTrue(app.buttons["Full scorecard"].waitForExistence(timeout: 20), "a result has no scorecard")
        linger(1.5)
        app.buttons["Full scorecard"].tap()
        linger(2)
        app.swipeUp()
        linger(1.5)
        back()
        back()
        app.buttons["List"].tap()

        // Chats: the club thread, and a message into it.
        tab("Chats")
        let thread = element(containing: world.club_chat)
        XCTAssertTrue(thread.waitForExistence(timeout: 20), "the club chat is not listed")
        linger()
        thread.tap()
        let message = app.textFields["Message"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 15))
        linger(2)
        message.tap()
        message.typeText("Super 5s v Watford Town tonight — whites off, club colours on. See you at 5:30.")
        app.buttons["Send"].tap()
        XCTAssertTrue(element(containing: "See you at 5:30").waitForExistence(timeout: 15), "the message did not send")
        linger(2)
        back()

        // Clubs: the club, its players, its figures and its QR code.
        tab("Clubs")
        let clubName = world.hero.club ?? "Hemel Hempstead Town CC"
        let club = element(containing: clubName)
        XCTAssertTrue(club.waitForExistence(timeout: 20), "\(clubName) is not listed")
        linger()
        club.tap()
        XCTAssertTrue(app.navigationBars[clubName].waitForExistence(timeout: 15))
        linger(2)

        let stats = element(containing: "Runs, wickets")
        if stats.waitForExistence(timeout: 10) {
            stats.tap()
            linger(3)
            app.swipeUp()
            linger(1.5)
            back()
        }

        let members = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'members'")).firstMatch
        if members.waitForExistence(timeout: 10) {
            members.tap()
            linger(2)
            let teammate = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS 'Open their profile'")).element(boundBy: 1)
            if teammate.waitForExistence(timeout: 10) {
                teammate.tap()
                linger(3)
                back()
            }
            back()
        }

        let more = app.navigationBars.buttons.matching(NSPredicate(format: "label == 'More'")).firstMatch
        if more.waitForExistence(timeout: 5) {
            more.tap()
            let qr = app.buttons["QR code"]
            if qr.waitForExistence(timeout: 5) {
                qr.tap()
                XCTAssertTrue(app.navigationBars["Club QR code"].waitForExistence(timeout: 10))
                linger(2.5)
                back()
            }
        }
        back()

        // Profile: a season's figures, worked out from the ball-by-ball log.
        tab("Profile")
        let sections = app.segmentedControls.firstMatch
        XCTAssertTrue(sections.waitForExistence(timeout: 20), "the profile never loaded")
        linger(2.5)
        for section in ["Batting", "Bowling", "Overview"] {
            sections.buttons[section].tap()
            linger(2.2)
        }
        tab("Home")
        linger(2)
    }

    // MARK: 2 · Five overs, ball by ball

    /// Hemel Hempstead Town v Watford Town, five overs a side, scored through
    /// the app: terms, the toss, both team sheets, every ball, a wide, a no ball
    /// and its free hit, bowled, caught, stumped and LBW, a correction, the
    /// innings break, the chase, the award and the card. Then the server's
    /// copy of the match is checked against what was scored.
    func testFiveOverMatchBallByBall() throws {
        try skipWithoutAnAPI()
        let world = try manifest()
        let fixture = world.super5s
        let home = try XCTUnwrap(fixture.home)
        let away = try XCTUnwrap(fixture.away)
        // An over each: five overs needs five bowlers a side, and a manifest
        // that cannot name them would fail somewhere far less obvious.
        for side in [home, away] {
            try XCTSkipUnless(side.bowlers.count >= 5 && side.batting.count >= 11,
                              "\(side.name) cannot field 11 with five bowlers — reseed")
        }
        // Plot boundaries only: every single on the wheel makes for a long evening.
        app.launchArguments += ["-cricket_wheel_mode", "boundaries"]
        try signIn(world.hero.email, password: world.password)

        tab("Fixtures")
        let row = reveal(fixture.title, timeout: 20)
        XCTAssertTrue(row.exists, "tonight's fixture is not in the list")
        linger()
        row.tap()
        let start = app.buttons["Start match"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "the captain is not offered the match to score")
        linger(1.5)
        start.tap()

        // The terms: five overs, one each.
        XCTAssertTrue(app.navigationBars["Start match"].waitForExistence(timeout: 20))
        linger()
        pick("Overs", "5")
        linger()
        let propose = reveal("Propose these terms")
        linger()
        propose.tap()

        let agree = app.buttons["Agree"].firstMatch
        XCTAssertTrue(agree.waitForExistence(timeout: 15), "no agreement for the visitors")
        linger()
        agree.tap()
        let captain = app.textFields["Name"]
        XCTAssertTrue(captain.waitForExistence(timeout: 10))
        captain.tap()
        captain.typeText(away.captain)
        linger(0.8)
        app.navigationBars.buttons["Agree"].tap()
        let toToss = app.buttons["Continue to the toss"]
        XCTAssertTrue(toToss.waitForExistence(timeout: 10))
        linger(1.2)
        toToss.tap()

        // Watford call correctly and put Hemel in.
        XCTAssertTrue(app.buttons["Record toss"].waitForExistence(timeout: 10))
        app.buttons[away.name].firstMatch.tap()
        app.buttons["Bowl"].firstMatch.tap()
        linger(1.5)
        app.buttons["Record toss"].tap()

        pickSide(home, confirm: "Confirm \(home.name)")
        turnPage()
        pickSide(away, confirm: "Confirm \(away.name)")

        // Openers, and Watford's opening bowler.
        XCTAssertTrue(app.buttons["Start innings"].waitForExistence(timeout: 20), "both sheets in, but no openers")
        pick("Bowler", away.bowlers[0])
        linger(1.5)
        app.buttons["Start innings"].tap()
        XCTAssertTrue(app.navigationBars["LIVE"].waitForExistence(timeout: 15), "the innings did not start")
        linger(1.5)

        // First innings — Hemel Hempstead Town.
        let k = home.keeper, wk = away.keeper
        over(bowler: nil, [.runs(1), .runs(0), .four(.cover), .wide, .runs(0), .runs(2), .runs(1)])
        over(bowler: away.bowlers[1], [.runs(0), .six(.straight), .runs(1), .out("Bowled", nil), .runs(0), .runs(1)])
        over(bowler: away.bowlers[3], [.runs(2), .runs(3), .undo, .runs(1), .runs(1), .four(.midwicket), .runs(0), .runs(1)])
        over(bowler: away.bowlers[2], [.runs(1), .noBall, .six(.squareLeg), .runs(1), .out("Caught", wk), .runs(2), .runs(0)])
        over(bowler: away.bowlers[4], [.four(.point), .runs(1), .runs(1), .runs(0), .runs(2), .six(.longOn)])
        XCTAssertTrue(element(containing: "51/2").waitForExistence(timeout: 10), "first innings is not 51/2")

        // The break, and Hemel's opening bowler.
        let second = app.buttons["Start second innings"]
        XCTAssertTrue(second.waitForExistence(timeout: 15), "no innings break")
        linger(3)
        second.tap()
        XCTAssertTrue(app.navigationBars["Second innings"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(containing: "need 52 to win").exists, "the target is not 52")
        pick("Bowler", home.bowlers[0])
        linger(1.5)
        app.navigationBars.buttons["Start"].tap()
        linger(1.5)

        // Second innings — Watford Town need 52.
        over(bowler: nil, [.runs(0), .runs(1), .four(.cover), .runs(0), .runs(1), .runs(1)])
        over(bowler: home.bowlers[1], [.out("Bowled", nil), .runs(2), .runs(1), .wide, .four(.fineLeg), .runs(0), .runs(1)])
        over(bowler: home.bowlers[3], [.runs(1), .runs(1), .six(.longOff), .runs(0), .out("Stumped", k), .runs(1)])
        over(bowler: home.bowlers[2], [.runs(2), .runs(1), .four(.midwicket), .runs(1), .runs(0), .out("LBW", nil)])
        over(bowler: home.bowlers[4], [.runs(1), .four(.cover), .runs(2), .runs(1), .six(.straight), .runs(0)])

        let margin = "\(home.name) won by 4 runs"
        XCTAssertTrue(element(containing: margin).waitForExistence(timeout: 15), "the result is not \(margin)")
        linger(3)

        // Player of the match, and the card.
        app.buttons["Award"].tap()
        // Defended nineteen in the last over.
        let potm = app.buttons[home.bowlers[4]].firstMatch
        XCTAssertTrue(potm.waitForExistence(timeout: 10))
        linger()
        potm.tap()
        XCTAssertTrue(element(containing: "Player of the match").waitForExistence(timeout: 10))
        linger(2)
        app.buttons["Scorecard"].tap()
        XCTAssertTrue(app.navigationBars["Scorecard"].waitForExistence(timeout: 10))
        linger(2.5)
        for _ in 0..<4 {
            app.swipeUp()
            linger(1.5)
        }
        app.navigationBars.buttons["Done"].tap()
        linger(1.5)

        // The server replayed the same log to the same result.
        let deadline = Date().addingTimeInterval(45)
        var serverMargin: String?
        let login = try api("POST", "/auth/login", token: nil,
                            body: ["identifier": world.hero.email, "password": world.password])
        let token = try XCTUnwrap(login["access_token"] as? String)
        while Date() < deadline {
            if let match = try? api("GET", "/events/\(fixture.event_id)/cricket-match", token: token, body: nil),
               let state = match["state"] as? [String: Any], state["status"] as? String == "complete" {
                serverMargin = state["margin"] as? String
                let innings = state["innings"] as? [[String: Any]] ?? []
                XCTAssertEqual(innings.first?["runs"] as? Int, 51)
                XCTAssertEqual(innings.last?["runs"] as? Int, 47)
                XCTAssertEqual(innings.last?["wickets"] as? Int, 3)
                break
            }
            Thread.sleep(forTimeInterval: 2)
        }
        XCTAssertEqual(serverMargin, margin, "the server's scorecard disagrees with the phone's")

        app.buttons["Done"].firstMatch.tap()
        let card = app.buttons["Full scorecard"]
        if card.waitForExistence(timeout: 15) {
            linger(2)
            card.tap()
            linger(3)
        }
    }

    // MARK: Scoring helpers

    enum Region {
        case cover, point, straight, longOn, longOff, midwicket, squareLeg, fineLeg

        /// Where to tap on the wheel: the top is straight down the ground, the
        /// right-hand side is the leg side for a right-hander.
        var offset: CGVector {
            switch self {
            case .straight: return CGVector(dx: 0.52, dy: 0.1)
            case .longOn: return CGVector(dx: 0.68, dy: 0.12)
            case .longOff: return CGVector(dx: 0.32, dy: 0.12)
            case .cover: return CGVector(dx: 0.16, dy: 0.32)
            case .point: return CGVector(dx: 0.1, dy: 0.55)
            case .midwicket: return CGVector(dx: 0.86, dy: 0.34)
            case .squareLeg: return CGVector(dx: 0.92, dy: 0.56)
            case .fineLeg: return CGVector(dx: 0.76, dy: 0.86)
            }
        }
    }

    enum Ball {
        case runs(Int)
        case four(Region)
        case six(Region)
        case wide
        case noBall
        case out(String, String?)
        case undo
    }

    /// One over. A new bowler first, unless it is the first over of the innings.
    private func over(bowler: String?, _ balls: [Ball], file: StaticString = #filePath, line: UInt = #line) {
        if let bowler { chooseBowler(bowler, file: file, line: line) }
        for ball in balls {
            switch ball {
            case .runs(let n):
                tapRuns(n, file: file, line: line)
            case .four(let region):
                tapRuns(4, file: file, line: line)
                plot(region)
            case .six(let region):
                tapRuns(6, file: file, line: line)
                plot(region)
            case .wide:
                extra("Wide", file: file, line: line)
            case .noBall:
                extra("No ball", file: file, line: line)
            case .out(let how, let fielder):
                wicket(how, fielder: fielder, file: file, line: line)
            case .undo:
                let undo = app.buttons["Undo last ball"]
                linger(1)
                undo.tap()
            }
            linger(0.5)
        }
    }

    private func tapRuns(_ n: Int, file: StaticString, line: UInt) {
        let run = app.buttons["\(n) run\(n == 1 ? "" : "s")"]
        XCTAssertTrue(run.waitForExistence(timeout: 10), "no \(n) button", file: file, line: line)
        // Waits out a banner or a sheet going away before the next ball.
        let deadline = Date().addingTimeInterval(10)
        while !run.isHittable || !run.isEnabled, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        run.tap()
    }

    private func plot(_ region: Region) {
        let wheel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Wagon wheel'")).firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 10), "a boundary did not ask where it went")
        linger(0.6)
        wheel.coordinate(withNormalizedOffset: region.offset).tap()
        linger(0.9)
        app.navigationBars.buttons["Save"].tap()
    }

    private func extra(_ kind: String, file: StaticString, line: UInt) {
        app.buttons["Extras"].tap()
        XCTAssertTrue(app.navigationBars["Extras"].waitForExistence(timeout: 10), file: file, line: line)
        if kind != "Wide" { app.buttons[kind].firstMatch.tap() }
        linger(0.8)
        app.navigationBars.buttons["Add"].tap()
    }

    private func wicket(_ how: String, fielder: String?, file: StaticString, line: UInt) {
        app.buttons["Wicket"].tap()
        XCTAssertTrue(app.navigationBars["Wicket"].waitForExistence(timeout: 10), file: file, line: line)
        if how != "Bowled" { pick("Dismissal", how, file: file, line: line) }
        if let fielder { pick("Fielder", fielder, file: file, line: line) }
        linger(1.2)
        app.navigationBars.buttons["Out"].tap()
        linger(0.8)
    }

    /// The sheet opens itself when an over ends on a scoring shot; after a
    /// wicket the gate above the buttons is the way in.
    private func chooseBowler(_ name: String, file: StaticString, line: UInt) {
        if !app.navigationBars["Bowler"].waitForExistence(timeout: 6) {
            let gate = element(containing: "who bowls next")
            XCTAssertTrue(gate.waitForExistence(timeout: 10), "the over ended with no way to change bowler",
                          file: file, line: line)
            gate.tap()
        }
        XCTAssertTrue(app.navigationBars["Bowler"].waitForExistence(timeout: 10), file: file, line: line)
        let row = scrollTo(app.buttons[name].firstMatch)
        XCTAssertTrue(row.exists, "\(name) is not offered to bowl", file: file, line: line)
        linger(0.8)
        row.tap()
        linger(0.8)
    }

    // MARK: Team sheet helpers

    /// Picks a side in batting order from the club's squad, names the keeper,
    /// and confirms it.
    private func pickSide(_ side: Side, confirm: String) {
        XCTAssertTrue(app.staticTexts["From the club"].waitForExistence(timeout: 30),
                      "\(side.name)'s squad is not offered")
        linger()
        for name in side.batting {
            let player = scrollTo(button(startingWith: name))
            XCTAssertTrue(player.exists && player.isHittable, "\(name) is not in \(side.name)'s squad")
            player.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
        pick("Wicketkeeper", side.keeper)
        linger(1.2)
        let done = button(startingWith: confirm)
        XCTAssertTrue(done.waitForExistence(timeout: 5), "no way to confirm \(side.name)")
        done.tap()
        linger(1.2)
    }

    /// A list only builds the rows on screen, and picking a player moves the
    /// rest, so look down the list and then back up it.
    @discardableResult
    private func scrollTo(_ target: XCUIElement) -> XCUIElement {
        if target.waitForExistence(timeout: 1.5), target.isHittable { return target }
        for direction in [true, false] {
            for _ in 0..<10 {
                if direction { app.swipeUp(velocity: .slow) } else { app.swipeDown(velocity: .slow) }
                if target.exists, target.isHittable { return target }
            }
        }
        return target
    }

    /// The sheets are pages; the indicator is the one place a swipe cannot
    /// delete a player by mistake.
    private func turnPage() {
        let dots = app.pageIndicators.firstMatch
        if dots.waitForExistence(timeout: 5) {
            dots.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        } else {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'batting order'")).firstMatch.swipeLeft()
        }
        linger(1)
    }
}
