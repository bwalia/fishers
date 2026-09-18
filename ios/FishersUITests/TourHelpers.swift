import XCTest

/// The handful of moves every tour makes: change tab, go back, find a row in a list that has not
/// been built yet, choose from a menu picker, and wait long enough for a screen to settle.
extension APITourCase {

    /// Long enough to read the screen on a recording.
    func linger(_ seconds: Double = 1.6) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func tab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.tabBars.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "no \(name) tab", file: file, line: line)
        button.tap()
    }

    /// Back, and only back. The first button in a navigation bar is the back button on a pushed
    /// screen and something else entirely on a root one — tapping that blindly opens Edit.
    func back() {
        let bar = app.navigationBars.firstMatch
        guard bar.waitForExistence(timeout: 5) else { return }
        let backButton = bar.buttons.matching(NSPredicate(
            format: "label IN {'Back', 'back'} OR identifier IN {'BackButton', 'Back'}")).firstMatch
        if backButton.exists, backButton.isHittable {
            backButton.tap()
        } else if bar.buttons.count > 0, bar.buttons.element(boundBy: 0).frame.minX < 80 {
            // An unlabelled chevron on the left is still the way back.
            bar.buttons.element(boundBy: 0).tap()
        } else {
            // Nothing to go back to, or nothing safe to press: swipe from the edge instead.
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            edge.press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        }
        linger(0.8)
    }

    func button(startingWith text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// A list only builds the rows on screen, and tapping one moves the rest, so look down the
    /// list and then back up it.
    @discardableResult
    func scrollTo(_ target: XCUIElement, swipes: Int = 10) -> XCUIElement {
        if target.waitForExistence(timeout: 1.5), target.isHittable { return target }
        for down in [true, false] {
            for _ in 0..<swipes {
                if down { app.swipeUp(velocity: .slow) } else { app.swipeDown(velocity: .slow) }
                if target.exists, target.isHittable { return target }
            }
        }
        return target
    }

    /// A menu-style picker in a form: open it, choose the option.
    func pick(_ picker: String, _ option: String, file: StaticString = #filePath, line: UInt = #line) {
        let control = scrollTo(button(startingWith: picker))
        XCTAssertTrue(control.exists, "no \(picker) picker", file: file, line: line)
        control.tap()
        let choice = app.buttons.matching(NSPredicate(format: "label == %@", option)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "\(picker) does not offer \(option)",
                      file: file, line: line)
        choice.tap()
    }

    /// A pull-to-refresh: a drag from the top, far enough for the list to take it. A short
    /// swipe only scrolls.
    func pullToRefresh() {
        // From just under the navigation bar: a drag that starts on a button is that button's,
        // not the list's.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.13))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        top.press(forDuration: 0.2, thenDragTo: bottom)
        linger(2.5)
        // A drag that landed on something anyway leaves a sheet open over the list.
        for label in ["Cancel", "Close", "Done"] where app.navigationBars.buttons[label].exists {
            app.navigationBars.buttons[label].tap()
            linger(0.8)
            break
        }
    }

    /// The address `scripts/seed-area.py` gives a player: their name, lower case, dots for spaces.
    func seedEmail(for name: String) -> String {
        let local = name.lowercased()
            .replacingOccurrences(of: " ", with: ".")
            .filter { $0.isLetter || $0 == "." || $0 == "-" }
        return "\(local)@fishers.test"
    }
}

// MARK: - Scoring a match through the app

/// Where a shot went, as a place on the wheel rather than an angle.
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

/// One ball as a tour types it.
enum Ball {
    case runs(Int)
    case four(Region)
    case six(Region)
    case wide
    case noBall
    case out(String, String?)
    case undo
}


extension APITourCase {
    /// One over. A new bowler first, unless it is the first over of the innings.
    func over(bowler: String?, _ balls: [Ball], file: StaticString = #filePath, line: UInt = #line) {
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

    func tapRuns(_ n: Int, file: StaticString, line: UInt) {
        let run = app.buttons["\(n) run\(n == 1 ? "" : "s")"]
        XCTAssertTrue(run.waitForExistence(timeout: 10), "no \(n) button", file: file, line: line)
        // Waits out a banner or a sheet going away before the next ball.
        let deadline = Date().addingTimeInterval(10)
        while !run.isHittable || !run.isEnabled, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        run.tap()
    }

    func plot(_ region: Region) {
        let wheel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Wagon wheel'")).firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 10), "a boundary did not ask where it went")
        linger(0.6)
        wheel.coordinate(withNormalizedOffset: region.offset).tap()
        linger(0.9)
        app.navigationBars.buttons["Save"].tap()
    }

    func extra(_ kind: String, file: StaticString, line: UInt) {
        app.buttons["Extras"].tap()
        XCTAssertTrue(app.navigationBars["Extras"].waitForExistence(timeout: 10), file: file, line: line)
        if kind != "Wide" { app.buttons[kind].firstMatch.tap() }
        linger(0.8)
        app.navigationBars.buttons["Add"].tap()
    }

    func wicket(_ how: String, fielder: String?, file: StaticString, line: UInt) {
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
    func chooseBowler(_ name: String, file: StaticString, line: UInt) {
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

}
