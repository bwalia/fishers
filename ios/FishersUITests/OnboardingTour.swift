import XCTest

/// The first minutes of a new account, driven through the real app.
///
/// Accounts are made through the API with a finished player profile — the
/// profile setup screens have their own coverage — and then everything the
/// guide asks for is done by tapping: the code from the email, the club, the
/// profile link, the invite.
///
/// Needs the local API with verification on and email going to Mailpit:
///   VERIFICATION_REQUIRED=true SMTP_HOST=mailpit SMTP_PORT=1025 SMTP_TLS=none \
///     ./scripts/start.sh --no-ios
/// Skips, saying so, when either is missing.
final class OnboardingTour: XCTestCase {
    private var app: XCUIApplication!

    private static let apiBase =
        ProcessInfo.processInfo.environment["FISHERS_API_URL"] ?? "http://127.0.0.1:7312"
    private static let mailpit =
        ProcessInfo.processInfo.environment["FISHERS_MAILPIT_URL"] ?? "http://127.0.0.1:8025"
    private static let password = "onboarding-tour-1"

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["FISHERS_API_URL"] = Self.apiBase
        app.launchArguments += ["-FishersSignOutOnLaunch"]
    }

    /// Opens the app signed in as `account`, or signed out.
    private func launch(as account: Account? = nil) {
        if let account {
            app.launchEnvironment["FISHERS_UITEST_ACCESS_TOKEN"] = account.access
            app.launchEnvironment["FISHERS_UITEST_REFRESH_TOKEN"] = account.refresh
        }
        app.launch()
    }

    private struct Account {
        let access: String
        let refresh: String
    }

    // MARK: Tests

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
        let email = "ios-sec-\(Int(Date().timeIntervalSince1970))@fishers.test"
        let account = try makeAccount(email: email, name: "Sam Secretary", role: "secretary")
        try skipUnlessVerificationIsOn(account.access)
        launch(as: account)

        XCTAssertTrue(app.staticTexts["Let's set up your club"].waitForExistence(timeout: 20),
                      "a new secretary is not shown the guide")
        let codeField = app.textFields["Verification code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 10), "the first step is not the code")
        capture("Guide-1-verify")

        codeField.tap()
        codeField.typeText(try codeFromMailpit(for: email))

        let start = app.buttons["Start your club"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "confirming the code did not move the guide on")
        capture("Guide-2-start-club")
        start.tap()

        let name = app.textFields["Fishers CC"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the new club form did not open")
        name.tap()
        name.typeText("Tour CC \(Int(Date().timeIntervalSince1970) % 10000)")
        app.buttons["Create"].tap()

        XCTAssertTrue(app.buttons["Add a team"].waitForExistence(timeout: 20)
                      || app.staticTexts["Add your first team"].waitForExistence(timeout: 5),
                      "after the club, the guide should ask for a team")
        capture("Guide-3-add-team")
    }

    func testPlayerSharesTheirLinkThenAcceptsTheInvite() throws {
        try skipWithoutAnAPI()
        let stamp = Int(Date().timeIntervalSince1970)
        let playerEmail = "ios-player-\(stamp)@fishers.test"
        let player = try makeAccount(email: playerEmail, name: "Pat Player", role: "player")
        try skipUnlessVerificationIsOn(player.access)
        try confirmByAPI(player.access, email: playerEmail)
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
        let secEmail = "ios-inviter-\(stamp)@fishers.test"
        let secretary = try makeAccount(email: secEmail, name: "Ivy Inviter", role: "secretary").access
        try confirmByAPI(secretary, email: secEmail)
        let club = try api("POST", "/clubs", token: secretary,
                           body: ["name": "Invite Test \(stamp % 10000)", "sport_types": ["cricket"]])
        _ = try api("POST", "/invites", token: secretary,
                    body: ["target_type": "club", "target_id": club["id"] as! String, "invited_email": playerEmail])

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

    // MARK: Helpers

    /// Signed up, with a player profile finished and a role chosen.
    private func makeAccount(email: String, name: String, role: String) throws -> Account {
        let tokens = try api("POST", "/auth/signup", token: nil,
                             body: ["name": name, "email": email, "password": Self.password])
        let token = try XCTUnwrap(tokens["access_token"] as? String)
        let refresh = try XCTUnwrap(tokens["refresh_token"] as? String)
        _ = try api("PATCH", "/me", token: token, body: [
            "primary_sport": "cricket",
            "sport_profiles": [["sport": "cricket", "position": "batter", "skill_level": "club", "stats": [:]]],
            "role_intent": role,
        ])
        return Account(access: token, refresh: refresh)
    }

    private func confirmByAPI(_ token: String, email: String) throws {
        let code = try codeFromMailpit(for: email)
        _ = try api("POST", "/me/verification/email/confirm", token: token, body: ["code": code])
    }

    private func skipUnlessVerificationIsOn(_ token: String) throws {
        let status = try api("GET", "/me/verification", token: token, body: nil)
        try XCTSkipUnless(status["enabled"] as? Bool == true,
                          "verification is off on this API — see the note at the top of OnboardingTour")
    }

    /// The newest code sent to this address. The subject is "123456 is your Fishers code".
    private func codeFromMailpit(for email: String) throws -> String {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let messages = try? json(URL(string: "\(Self.mailpit)/api/v1/messages?limit=50")!)["messages"] as? [[String: Any]] {
                for message in messages {
                    let to = (message["To"] as? [[String: Any]])?.compactMap { $0["Address"] as? String } ?? []
                    if to.contains(email), let subject = message["Subject"] as? String,
                       let range = subject.range(of: #"\d{6}"#, options: .regularExpression) {
                        return String(subject[range])
                    }
                }
            }
            Thread.sleep(forTimeInterval: 1)
        }
        throw XCTSkip("no code reached Mailpit at \(Self.mailpit) for \(email)")
    }

    @discardableResult
    private func api(_ method: String, _ path: String, token: String?, body: [String: Any]?) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: Self.apiBase + "/api/v1" + path)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return try json(request)
    }

    private func json(_ url: URL) throws -> [String: Any] { try json(URLRequest(url: url)) }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        var result: Result<[String: Any], Error> = .success([:])
        let done = expectation(description: request.url?.path ?? "request")
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { done.fulfill() }
            if let error { result = .failure(error); return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            result = (200..<300).contains(status)
                ? .success(object)
                : .failure(NSError(domain: "api", code: status, userInfo: [NSLocalizedDescriptionKey: "\(status) \(object)"]))
        }.resume()
        wait(for: [done], timeout: 20)
        return try result.get()
    }

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
