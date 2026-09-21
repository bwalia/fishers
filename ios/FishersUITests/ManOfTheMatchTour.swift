import XCTest

/// The man-of-the-match vote, seen by somebody who did not play.
///
/// That is the whole point of the feature, so it is the account the tour signs
/// in as: an ordinary club member who was not on either team sheet, opening
/// the club's thread after the game and voting from it.
///
/// Needs an API with a finished match whose vote is open:
///
///   ./scripts/start.sh --no-ios
///   FISHERS_API_URL=http://127.0.0.1:7312 \
///     xcodebuild test -scheme FishersUI -only-testing:FishersUITests/ManOfTheMatchTour
///
/// Skips, saying so, without an API or without an open vote to look at.
final class ManOfTheMatchTour: APITourCase {

    func testAMemberWhoDidNotPlayVotes() throws {
        try skipWithoutAnAPI()

        // Supplied by the runner, which knows which fixture it just finished.
        let environment = ProcessInfo.processInfo.environment
        let email = try XCTUnwrap(environment["MOTM_VOTER_EMAIL"],
                                  "set MOTM_VOTER_EMAIL to a club member who did not play")
        let password = environment["MOTM_VOTER_PASSWORD"] ?? "password123"
        let threadName = try XCTUnwrap(environment["MOTM_THREAD"],
                                       "set MOTM_THREAD to the thread the card was posted in")

        let tokens = try api("POST", "/auth/login", token: nil,
                             body: ["identifier": email, "password": password])
        launch(as: Account(access: try XCTUnwrap(tokens["access_token"] as? String),
                           refresh: try XCTUnwrap(tokens["refresh_token"] as? String),
                           email: email))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30),
                      "signing in never reached the tab bar")
        linger(1.5)

        tab("Chats")
        let thread = reveal(threadName, timeout: 20)
        XCTAssertTrue(thread.exists, "the club's thread is not in the chat list")
        thread.tap()
        linger(3)
        capture("0 · the thread as it opens")
        // What the thread is actually showing, when the card is not in it.
        let visible = app.descendants(matching: .any).allElementsBoundByIndex
            .prefix(60).map { "\($0.elementType.rawValue) \($0.label)" }.joined(separator: "\n")
        let dump = XCTAttachment(string: visible)
        dump.name = "0 · elements"
        dump.lifetime = .keepAlways
        add(dump)

        // The card sits under the message that announced the result, at the
        // bottom of the thread — which is where a thread opens.
        let heading = reveal("Man of the match", timeout: 20)
        XCTAssertTrue(heading.exists, "no man-of-the-match card in the thread")

        // Onto the ballot itself. Twenty-two names is taller than a phone, so
        // the card's heading and its team sheets are never on screen at once.
        // Scrolled to by the rows' own labels rather than by the side's name,
        // which also appears in older messages further up the thread.
        let ballot = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Vote for '"))
        for _ in 0..<10 where ballot.count == 0 || !ballot.element(boundBy: 0).isHittable {
            app.swipeUp()
            linger(0.4)
        }
        XCTAssertGreaterThan(ballot.count, 1, "the ballot has no names on it")
        linger(1)
        capture("1 · the vote, before voting")

        // Votes are hidden until you have voted, so the card says so rather
        // than drawing a column of zeroes.
        XCTAssertTrue(element(containing: "hidden until you have voted").exists,
                      "the card is showing a tally before this person has voted")
        let pick = ballot.element(boundBy: 0)
        let pickedName = pick.label.replacingOccurrences(of: "Vote for ", with: "")
        pick.tap()
        linger(2)

        capture("2 · after voting, with the tally out")
        XCTAssertTrue(element(containing: "\(pickedName), your vote").waitForExistence(timeout: 10),
                      "the vote was not recorded on the card")
        XCTAssertTrue(element(containing: "so far").exists,
                      "the tally is still hidden after voting")

        // Tapping the same name again takes the vote back — a mis-tap undone
        // by the tap that made it.
        element(containing: "\(pickedName), your vote").tap()
        linger(2)
        capture("3 · vote withdrawn")
        XCTAssertTrue(element(containing: "Vote for \(pickedName)").waitForExistence(timeout: 10),
                      "the vote was not withdrawn")
    }
}
