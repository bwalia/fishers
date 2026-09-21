import XCTest

/// The man-of-the-match vote, from the boundary.
///
/// One test rather than several, because they would all be about the same
/// poll and there is only one of it: a test that closes the vote leaves
/// nothing for a test that votes in it, and XCTest runs them in whatever
/// order it likes. The other tours in this repo are long narratives for the
/// same reason.
///
/// Needs an API with a finished match whose vote is still open:
///
///   ./scripts/start.sh --no-ios                       # then finish a match
///   FISHERS_API_URL=http://127.0.0.1:7312 \
///   TEST_RUNNER_MOTM_VOTER_EMAIL=someone@club.test \
///   TEST_RUNNER_MOTM_CAPTAIN_EMAIL=captain@club.test \
///   TEST_RUNNER_MOTM_THREAD="Their club chat" \
///     xcodebuild test -scheme FishersUI \
///       -only-testing:FishersUITests/ManOfTheMatchTour
///
/// Skips, saying so, without an API. Code signing must be left on: an
/// unsigned build cannot reach the Keychain, so the injected session never
/// persists and every tour fails at "never reached the tab bar".
final class ManOfTheMatchTour: APITourCase {

    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    private var ballot: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Vote for '"))
    }

    /// Signed in as `email`, in the club's thread, with the card on screen.
    ///
    /// The fixture comes from the environment rather than a constant: which
    /// game finished most recently changes with every seed, and a tour pinned
    /// to one club's Saturday stops working the next time anybody reseeds.
    private func openTheCard(as email: String) throws {
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

        // The card renders under the message that announced the result, and
        // the thread opens on it rather than on the message above it.
        XCTAssertTrue(reveal("Man of the match", timeout: 20).exists,
                      "no man-of-the-match card in the thread")
    }

    /// Onto the ballot. Twenty-two names is taller than a phone, so the card's
    /// heading and its team sheets are never both on screen — and scrolling by
    /// the side's name would find it in an older message further up instead.
    private func scrollToTheBallot() {
        for _ in 0..<10 where ballot.count == 0 || !ballot.element(boundBy: 0).isHittable {
            app.swipeUp()
            linger(0.4)
        }
    }

    func testTheClubVotesAndACaptainClosesIt() throws {
        try skipWithoutAnAPI()
        let member = try XCTUnwrap(environment["MOTM_VOTER_EMAIL"],
                                   "set MOTM_VOTER_EMAIL to a club member who did not play")
        let captain = try XCTUnwrap(environment["MOTM_CAPTAIN_EMAIL"],
                                    "set MOTM_CAPTAIN_EMAIL to a captain or secretary")

        // MARK: Somebody who watched rather than played

        try openTheCard(as: member)
        scrollToTheBallot()
        XCTAssertGreaterThan(ballot.count, 1, "the ballot has no names on it")
        linger(1)
        capture("1 · the vote, before voting")

        // Votes stay hidden until you have voted, so the card says so rather
        // than drawing a column of zeroes to be nudged by.
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

        // Tapping the same name takes the vote back — a mis-tap undone by the
        // tap that made it — and then it goes back on, to be counted below.
        element(containing: "\(pickedName), your vote").tap()
        linger(2)
        capture("3 · vote withdrawn")
        XCTAssertTrue(element(containing: "Vote for \(pickedName)").waitForExistence(timeout: 10),
                      "the vote was not withdrawn")
        element(containing: "Vote for \(pickedName)").tap()
        linger(2)

        // MARK: Closing it early is a captain's call

        let close = reveal("Close the vote", timeout: 15)
        XCTAssertTrue(close.exists, "no way to close the vote on the card")
        close.tap()
        linger(2.5)
        capture("4 · a member is told plainly that it is not theirs to close")
        XCTAssertTrue(
            element(containing: "Only a captain or club secretary").waitForExistence(timeout: 10),
            "closing was refused without saying why")
        // The shared RBAC sentence names the permission — right for an API,
        // wrong for a card every member of the club will tap once.
        XCTAssertFalse(element(containing: "manage_events").exists,
                       "the refusal is still showing the permission's internal name")
        // Refused, not closed: the ballot is still there to vote on.
        scrollToTheBallot()
        XCTAssertGreaterThan(ballot.count, 1, "a refused close emptied the ballot")

        // MARK: The captain ends it

        try openTheCard(as: captain)
        let captainsClose = reveal("Close the vote", timeout: 15)
        XCTAssertTrue(captainsClose.exists, "no way to close the vote on the card")
        captainsClose.tap()
        linger(3)
        capture("5 · closed, with the winner named")

        XCTAssertTrue(element(containing: "Closed").waitForExistence(timeout: 15),
                      "the card still reads as open after closing")
        XCTAssertEqual(ballot.count, 0, "the ballot is still votable after the vote closed")
        XCTAssertTrue(element(containing: pickedName).exists,
                      "the only person voted for is not named as the winner")
    }
}
