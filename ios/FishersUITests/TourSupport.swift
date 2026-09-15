import XCTest

/// What the tours that make their own accounts share: an app opened as a given
/// account, the API to set the stage with, and Mailpit for the codes.
///
/// Needs the local API with verification on and email going to Mailpit:
///   VERIFICATION_REQUIRED=true SMTP_HOST=mailpit SMTP_PORT=1025 SMTP_TLS=none \
///     ./scripts/start.sh --no-ios
/// Tests skip, saying so, when either is missing.
class APITourCase: XCTestCase {
    var app: XCUIApplication!

    static let apiBase =
        ProcessInfo.processInfo.environment["FISHERS_API_URL"] ?? "http://127.0.0.1:7312"
    static let mailpit =
        ProcessInfo.processInfo.environment["FISHERS_MAILPIT_URL"] ?? "http://127.0.0.1:8025"
    static let password = "onboarding-tour-1"

    struct Account {
        let access: String
        let refresh: String
        let email: String
    }

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["FISHERS_API_URL"] = Self.apiBase
        app.launchArguments += ["-FishersSignOutOnLaunch"]
    }

    /// Opens the app signed in as `account`, or signed out.
    func launch(as account: Account? = nil) {
        if let account {
            app.launchEnvironment["FISHERS_UITEST_ACCESS_TOKEN"] = account.access
            app.launchEnvironment["FISHERS_UITEST_REFRESH_TOKEN"] = account.refresh
        }
        app.launch()
    }

    var stamp: Int { Int(Date().timeIntervalSince1970 * 1000) % 100_000_000 }

    /// Signed up, with a player profile finished and a role chosen.
    /// `profile: false` leaves it as it is straight after signing up — the
    /// quick start still to come.
    func makeAccount(_ tag: String, name: String, role: String, verified: Bool = false, profile: Bool = true) throws -> Account {
        let email = "ios-\(tag)-\(stamp)@fishers.test"
        let tokens = try api("POST", "/auth/signup", token: nil,
                             body: ["name": name, "email": email, "password": Self.password])
        let token = try XCTUnwrap(tokens["access_token"] as? String)
        let refresh = try XCTUnwrap(tokens["refresh_token"] as? String)
        try api("PATCH", "/me", token: token, body: profile ? [
            "primary_sport": "cricket",
            "sport_profiles": [["sport": "cricket", "position": "batter", "skill_level": "club", "stats": [:]]],
            "role_intent": role,
        ] : ["role_intent": role])
        let account = Account(access: token, refresh: refresh, email: email)
        if verified {
            try skipUnlessVerificationIsOn(token)
            try confirmByAPI(account)
        }
        return account
    }

    func confirmByAPI(_ account: Account) throws {
        let code = try codeFromMailpit(for: account.email)
        try api("POST", "/me/verification/email/confirm", token: account.access, body: ["code": code])
    }

    func skipUnlessVerificationIsOn(_ token: String) throws {
        let status = try api("GET", "/me/verification", token: token, body: nil)
        try XCTSkipUnless(status["enabled"] as? Bool == true,
                          "verification is off on this API — see the note on APITourCase")
    }

    /// The newest code sent to this address. The subject is "123456 is your Fishers code".
    func codeFromMailpit(for email: String) throws -> String {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let messages = try? json(URLRequest(url: URL(string: "\(Self.mailpit)/api/v1/messages?limit=50")!))["messages"] as? [[String: Any]] {
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
    func api(_ method: String, _ path: String, token: String?, body: [String: Any]?) throws -> [String: Any] {
        try json(request(method, path, token: token, body: body))
    }

    /// For the endpoints that answer with a list.
    func apiList(_ path: String, token: String) throws -> [[String: Any]] {
        let data = try send(request("GET", path, token: token, body: nil))
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func request(_ method: String, _ path: String, token: String?, body: [String: Any]?) throws -> URLRequest {
        var request = URLRequest(url: URL(string: Self.apiBase + "/api/v1" + path)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return request
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        let data = try send(request)
        return (data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func send(_ request: URLRequest) throws -> Data {
        var result: Result<Data, Error> = .success(Data())
        let done = expectation(description: request.url?.path ?? "request")
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { done.fulfill() }
            if let error { result = .failure(error); return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = data ?? Data()
            result = (200..<300).contains(status)
                ? .success(body)
                : .failure(NSError(domain: "api", code: status, userInfo: [
                    NSLocalizedDescriptionKey: "\(request.httpMethod ?? "") \(request.url?.path ?? ""): \(status) \(String(data: body, encoding: .utf8) ?? "")",
                ]))
        }.resume()
        wait(for: [done], timeout: 20)
        return try result.get()
    }

    func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func skipWithoutAnAPI() throws {
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

    /// Any element whose label contains `text` — a SwiftUI row surfaces as a
    /// button, a cell or a link depending on the OS version.
    func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The same, scrolled to. A list only builds the rows on screen, so a row
    /// below the fold is not in the tree at all until the list is moved.
    @discardableResult
    func reveal(_ text: String, timeout: TimeInterval = 15) -> XCUIElement {
        let target = element(containing: text)
        let deadline = Date().addingTimeInterval(timeout)
        while !target.exists || !target.isHittable {
            guard Date() < deadline else { break }
            if target.waitForExistence(timeout: 1.5), target.isHittable { break }
            app.swipeUp()
        }
        return target
    }
}
