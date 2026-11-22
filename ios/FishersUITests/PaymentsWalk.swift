import XCTest

/// A picture of every payment screen, from each person's phone, for looking
/// at rather than asserting on: a player paying, a parent paying for two
/// juniors, the secretary's money screens and the treasurer's.
///
/// Runs against the demo club from `.dev/payments/seed_demo.py`, and only
/// when `WALK_SHOTS` names a folder on the Mac: pictures go there and to the
/// result bundle. Signed, not CODE_SIGNING_ALLOWED=NO (the test token lives
/// in the Keychain):
///   TEST_RUNNER_WALK_SHOTS=/tmp/shots TEST_RUNNER_FISHERS_API_URL=http://127.0.0.1:7312 \
///     xcodebuild test -scheme FishersUI -only-testing:FishersUITests/PaymentsWalk …
/// The treasurer's walk reads a statement from Files: put a CSV in the
/// simulator's "On My iPhone" first (the FileProvider.LocalStorage group
/// container's `File Provider Storage`), or it photographs the picker only.
final class PaymentsWalk: APITourCase {

    private static let demoPassword = "password123"
    private static let demoClub = "Riverside Strikers (demo)"
    private static let shotsDir = ProcessInfo.processInfo.environment["WALK_SHOTS"]
    private var shotCount = 0
    private var prefix = ""

    /// Only when asked for: the walk changes the demo club (claims, All arrived) and
    /// takes the best part of half an hour, which the everyday tour run shouldn't.
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(Self.shotsDir == nil, "set TEST_RUNNER_WALK_SHOTS=<dir> to walk the payment screens")
    }

    override func setUp() {
        super.setUp()
        // A walk, not a check: keep going past a missing button and photograph the rest.
        continueAfterFailure = true
    }

    // MARK: Helpers

    private func demo(_ email: String) throws -> Account {
        let tokens = try api("POST", "/auth/login", token: nil,
                             body: ["identifier": email, "password": Self.demoPassword])
        let access = try XCTUnwrap(tokens["access_token"] as? String, "no demo account \(email) — run seed_demo.py")
        return Account(access: access, refresh: tokens["refresh_token"] as? String ?? "", email: email)
    }

    private func clubId(_ account: Account) throws -> String {
        let dues = try api("GET", "/me/dues", token: account.access, body: nil)["clubs"] as? [[String: Any]] ?? []
        if let id = dues.first(where: { $0["club_name"] as? String == Self.demoClub })?["club_id"] as? String { return id }
        let clubs = try apiList("/clubs?mine=true", token: account.access)
        return try XCTUnwrap(clubs.first { $0["name"] as? String == Self.demoClub }?["id"] as? String)
    }

    /// Undo every "I've paid" this person has waiting, so the walk starts from "you owe".
    private func undoClaims(_ account: Account, club: String) throws {
        let screen = try api("GET", "/clubs/\(club)/pay", token: account.access, body: nil)
        for claim in screen["claims"] as? [[String: Any]] ?? [] {
            if let id = claim["id"] as? String {
                try? api("DELETE", "/payments/\(id)", token: account.access, body: nil)
            }
        }
    }

    private func claim(_ account: Account, club: String) {
        var request = URLRequest(url: URL(string: Self.apiBase + "/api/v1/clubs/\(club)/payments")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(account.access)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["method": "transfer"])
        let done = expectation(description: "claim")
        URLSession.shared.dataTask(with: request) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 20)
    }

    private func shot(_ name: String) {
        shotCount += 1
        let full = String(format: "%@-%02d-%@", prefix, shotCount, name)
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = full
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = Self.shotsDir {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(full + ".png"))
        }
    }

    /// Photograph a screen top to bottom: a picture, half a screen down, again, until it stops moving.
    private func shootDown(_ name: String, max: Int = 10) {
        var last = Data()
        for page in 0..<max {
            let now = app.screenshot().pngRepresentation
            if now == last { break }
            last = now
            shot("\(name)-\(page)")
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
            linger(0.6)
        }
    }

    private func scrollToTop() {
        var last = Data()
        for _ in 0..<12 {
            let now = app.screenshot().pngRepresentation
            if now == last { break }
            last = now
            app.swipeDown(velocity: .fast)
            linger(0.4)
        }
    }

    private func openClubPayments() {
        tab("Clubs")
        if !element(containing: Self.demoClub).waitForExistence(timeout: 10) { tab("Clubs") }
        reveal(Self.demoClub).tap()
        let members = app.buttons.matching(NSPredicate(format: "label ENDSWITH ' members'")).firstMatch
        scrollTo(members).tap()
        let payments = app.buttons["Payments"].firstMatch
        XCTAssertTrue(payments.waitForExistence(timeout: 20), "no Payments tab")
        payments.tap()
        linger(2)
    }

    private func openPayScreen() {
        let card = element(containing: "You owe")
        XCTAssertTrue(card.waitForExistence(timeout: 25), "Home does not say what is owed")
        shot("home")
        card.tap()
        linger(1.5)
        shot("dues-list")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'You owe'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no row to open the pay screen")
        row.tap()
        // The list builds rows as they come on screen: the headline, not the button below it.
        XCTAssertTrue(element(containing: "You owe").waitForExistence(timeout: 15), "no pay screen")
        linger(1.5)
    }

    // MARK: 1. Ravi pays

    func test1RaviPays() throws {
        try skipWithoutAnAPI()
        prefix = "1-ravi"
        let ravi = try demo("ravi@pay.test")
        let club = try clubId(ravi)
        try undoClaims(ravi, club: club)

        launch(as: ravi)
        openPayScreen()
        shootDown("pay-screen")
        scrollToTop()

        // Copy the account number.
        let copy = app.buttons["Copy account number"].firstMatch
        if scrollTo(copy).exists {
            copy.tap()
            linger(0.4)
            shot("copied-account-number")
        }

        // The guide, open or folded.
        let guide = element(containing: "First time?")
        if scrollTo(guide).exists { shot("guide") }

        let paid = scrollTo(app.buttons["I've paid"].firstMatch)
        paid.tap()
        XCTAssertTrue(element(containing: "Waiting for the club to confirm").waitForExistence(timeout: 15))
        linger(1.5)
        scrollToTop()
        shootDown("after-ive-paid")

        // Add a screenshot: open the picker.
        let add = scrollTo(app.buttons["Add a screenshot"].firstMatch)
        if add.exists {
            add.tap()
            linger(3)
            shot("photo-picker")
            let photo = app.images.firstMatch
            if photo.waitForExistence(timeout: 5), photo.isHittable {
                photo.tap()
                linger(4)
                shot("after-photo")
            } else {
                app.buttons["Cancel"].firstMatch.tap()
                linger(1)
            }
        }

        let undo = scrollTo(app.buttons["Undo"].firstMatch)
        if undo.exists {
            undo.tap()
            linger(2)
            shot("after-undo")
        }
        scrollToTop()
        shootDown("final")
    }

    // MARK: 2. Neha pays for Jas and Arjun

    func test2NehaPaysForEveryone() throws {
        try skipWithoutAnAPI()
        prefix = "2-neha"
        let neha = try demo("neha@pay.test")
        let club = try clubId(neha)
        try undoClaims(neha, club: club)

        launch(as: neha)
        let card = element(containing: "You owe")
        XCTAssertTrue(card.waitForExistence(timeout: 25))
        shot("home")
        card.tap()
        linger(1.5)
        shootDown("dues-list")

        let everyone = scrollTo(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Pay for everyone'")).firstMatch)
        XCTAssertTrue(everyone.exists, "no Pay for everyone")
        everyone.tap()
        linger(2)
        shootDown("pay-for-everyone")
        let paid = scrollTo(app.buttons["I've paid for everyone"].firstMatch)
        paid.tap()
        linger(3)
        scrollToTop()
        shootDown("paid-for-everyone")
        back()
        linger(1.5)
        scrollToTop()
        shootDown("dues-after")

        let row = scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'You owe' OR label CONTAINS 'waiting'")).firstMatch)
        if row.exists {
            row.tap()
            linger(2)
            shootDown("pay-screen-after")
            let forJas = element(containing: "For Jas")
            if scrollTo(forJas).exists { shot("for-jas") }
        }
    }

    // MARK: 3. Aman, the secretary

    func test3AmanSecretary() throws {
        try skipWithoutAnAPI()
        prefix = "3-aman"
        let aman = try demo("aman@pay.test")
        launch(as: aman)
        openClubPayments()
        shootDown("payments")

        // A billed session from Recent bills.
        let friday = scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Friday nets'")).firstMatch)
        if friday.exists {
            friday.tap()
            linger(2.5)
            shootDown("billed-event")
            let share = scrollTo(app.buttons["Share the bill"].firstMatch)
            if share.exists {
                share.tap()
                linger(3)
                shot("share-sheet")
                let close = app.buttons.matching(NSPredicate(format: "label IN {'Close', 'Cancel'}")).firstMatch
                if close.waitForExistence(timeout: 3) { close.tap() } else {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
                }
                linger(1.5)
            }
            let cash = scrollTo(app.buttons["Who paid cash?"].firstMatch)
            if cash.exists {
                cash.tap()
                linger(2)
                shootDown("who-paid-cash")
                app.navigationBars.buttons["Cancel"].firstMatch.tap()
                linger(1)
            }
            back()
            linger(1.5)
        }

        // Passes, from a template.
        let passes = scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Passes'")).firstMatch)
        passes.tap()
        linger(2)
        shootDown("passes")
        scrollToTop()
        let newPass = scrollTo(app.buttons["New pass"].firstMatch)
        newPass.tap()
        linger(1.5)
        shootDown("new-pass-templates")
        let template = scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Junior membership'")).firstMatch)
        template.tap()
        linger(1.5)
        shootDown("new-pass-form")
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        linger(1)
        // One that exists: who is on it.
        let monthly = scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Monthly nets'")).firstMatch)
        if monthly.exists {
            monthly.tap()
            linger(2)
            shootDown("pass-detail")
            back()
        }
        back()
        linger(1)

    }

    // MARK: 3b. Group fees and prices

    func test3bAmanGroupFeesAndPrices() throws {
        try skipWithoutAnAPI()
        prefix = "3b-aman"
        let aman = try demo("aman@pay.test")
        let club = try clubId(aman)
        let title = "Walk test kit \(stamp % 1000)"
        launch(as: aman)
        openClubPayments()

        // Group fees: a new one, sent, then shared.
        let fees = scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Group fees'")).firstMatch)
        fees.tap()
        linger(2)
        app.buttons["New group fee"].firstMatch.tap()
        linger(1.5)
        let name = app.textFields.firstMatch
        if name.waitForExistence(timeout: 5) {
            name.tap()
            name.typeText(title)
        }
        let amount = scrollTo(app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'pays' OR placeholderValue CONTAINS 'Total'")).firstMatch)
        if amount.exists {
            amount.tap()
            amount.typeText("3")
        }
        shot("new-group-fee-filled")
        let send = app.navigationBars.buttons["Send"].firstMatch
        if send.exists, send.isEnabled {
            send.tap()
            linger(3)
            shootDown("group-fee-sent")
            let share = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Share'")).firstMatch
            if share.waitForExistence(timeout: 3) {
                share.tap()
                linger(3)
                shot("group-fee-share-sheet")
                let close = app.buttons.matching(NSPredicate(format: "label IN {'Close', 'Cancel'}")).firstMatch
                if close.waitForExistence(timeout: 3) { close.tap() }
                linger(1.5)
            }
            let done = app.buttons["Done"].firstMatch
            if done.waitForExistence(timeout: 3) { done.tap() }
            linger(2)
            shot("group-fees-after")
            let made = scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch)
            if made.exists {
                made.tap()
                linger(2.5)
                shootDown("group-fee-detail")
                back()
            }
        } else {
            shot("send-not-enabled")
            app.navigationBars.buttons["Cancel"].firstMatch.tap()
        }
        back()
        linger(1)

        // Prices for juniors.
        let prices = scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Prices for juniors'")).firstMatch)
        prices.tap()
        linger(2)
        shootDown("price-groups")
        let another = scrollTo(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Another group'")).firstMatch)
        if another.exists {
            another.tap()
            linger(1.5)
            shot("add-group-sheet")
            app.navigationBars.buttons["Cancel"].firstMatch.tap()
            linger(1)
        }
        let junior = scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Junior'")).firstMatch)
        if junior.exists {
            junior.tap()
            linger(1.5)
            shot("edit-group-sheet")
            app.navigationBars.buttons["Cancel"].firstMatch.tap()
            linger(1)
        }
        back()
        linger(1)

        // Who pays for whom: set a group, add a junior by name.
        let whom = scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Who pays for whom'")).firstMatch)
        whom.tap()
        linger(2)
        shootDown("who-pays")
        let josh = scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Josh Turner'")).firstMatch)
        if josh.exists {
            josh.tap()
            linger(1.5)
            shot("member-sheet")
            let price = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Their price'")).firstMatch
            if price.waitForExistence(timeout: 3) {
                price.tap()
                linger(1)
                shot("member-price-menu")
                let pick = app.buttons["Junior"].firstMatch
                if pick.exists { pick.tap() }
                linger(0.8)
                shot("member-price-picked")
            }
            let save = app.navigationBars.buttons["Save"].firstMatch
            if save.exists { save.tap() } else { app.navigationBars.buttons["Cancel"].firstMatch.tap() }
            linger(2)
            shot("who-pays-after-save")
        }
        let addJunior = scrollTo(app.buttons["Add a junior by name"].firstMatch)
        if addJunior.exists {
            addJunior.tap()
            linger(1.5)
            shot("add-junior")
            let field = app.textFields.firstMatch
            if field.waitForExistence(timeout: 3) {
                field.tap()
                field.typeText("Walk Junior")
            }
            let payer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Who pays for them'")).firstMatch
            if payer.exists {
                payer.tap()
                linger(1)
                shot("add-junior-payer-menu")
                let neha = app.buttons["Neha Gill"].firstMatch
                if neha.exists { neha.tap() }
                linger(0.8)
            }
            shot("add-junior-filled")
            let add = app.navigationBars.buttons["Add them"].firstMatch
            if add.exists { add.tap() } else { app.navigationBars.buttons["Cancel"].firstMatch.tap() }
            linger(2.5)
            shootDown("who-pays-after-junior")
        }

        // Put the demo club back as it was.
        if let fee = try? apiList("/clubs/\(club)/collections", token: aman.access)
            .first(where: { $0["title"] as? String == title }), let id = fee["bill_id"] as? String ?? fee["id"] as? String {
            try? api("POST", "/collections/\(id)/void", token: aman.access, body: ["reason": "Walk test"])
        }
        if let members = try? apiList("/clubs/\(club)/payments/members", token: aman.access) {
            if let joshId = members.first(where: { $0["name"] as? String == "Josh Turner" })?["user_id"] as? String {
                try? api("PUT", "/clubs/\(club)/members/\(joshId)/price-type", token: aman.access, body: ["price_type_id": NSNull()])
            }
            for walk in members where walk["name"] as? String == "Walk Junior" {
                if let id = walk["user_id"] as? String {
                    try? api("DELETE", "/clubs/\(club)/members/\(id)", token: aman.access, body: nil)
                }
            }
        }
    }

    // MARK: 4. Tara, the treasurer: a bank statement read, then All arrived

    func test4TaraTreasurer() throws {
        try skipWithoutAnAPI()
        prefix = "4-tara"
        let tara = try demo("tara@pay.test")
        let club = try clubId(tara)
        claim(try demo("ravi@pay.test"), club: club)

        launch(as: tara)
        openClubPayments()
        shootDown("payments")
        scrollToTop()

        // Import a bank statement: the sheet, the file picker, the statement
        // the run put in Files (On My iPhone), and what it matched.
        let importer = scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Import a bank statement'")).firstMatch)
        importer.tap()
        linger(1.5)
        shot("statement-empty")
        app.buttons["Choose the CSV file"].firstMatch.tap()
        linger(3)
        shot("file-picker")
        let browse = app.buttons["Browse"].firstMatch
        if browse.waitForExistence(timeout: 3) { browse.tap(); linger(1.5) }
        let onPhone = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'On My iPhone'")).firstMatch
        if onPhone.waitForExistence(timeout: 3) { onPhone.tap(); linger(2) }
        // The file's icon, top left of the grid: the picker's cells don't take a tap on their label.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.177, dy: 0.274)).tap()
        linger(5)
        shot("preview-top")
        let toggle = app.switches.firstMatch
        if toggle.exists, toggle.isHittable {
            toggle.tap(); linger(0.6); shot("unticked")
            toggle.tap(); linger(0.6)
        }
        shootDown("preview")
        let unknown = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Not recognised'")).firstMatch
        if unknown.exists, unknown.isHittable {
            unknown.tap(); linger(1); shot("not-recognised-open")
        }
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        linger(2.5)

        let all = scrollTo(app.buttons.matching(NSPredicate(format: "label CONTAINS 'All arrived'")).firstMatch)
        XCTAssertTrue(all.exists, "no All arrived")
        shot("before-all-arrived")
        all.tap()
        linger(1)
        shot("all-arrived-confirm")
        let yes = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Yes, they all arrived'")).firstMatch
        if yes.waitForExistence(timeout: 3) {
            yes.tap()
            linger(3)
            shot("after-all-arrived")
        }
    }

    // MARK: 5. The largest text

    func test5BigTextPayScreen() throws {
        try skipWithoutAnAPI()
        prefix = "5-bigtext"
        let ravi = try demo("ravi@pay.test")
        let club = try clubId(ravi)
        try undoClaims(ravi, club: club)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch(as: ravi)
        openPayScreen()
        shootDown("pay-screen", max: 30)
        scrollToTop()
        let paid = scrollTo(app.buttons["I've paid"].firstMatch, swipes: 20)
        if paid.exists {
            paid.tap()
            linger(3)
            scrollToTop()
            shootDown("after-ive-paid", max: 30)
            let undo = scrollTo(app.buttons["Undo"].firstMatch, swipes: 20)
            if undo.exists { undo.tap(); linger(2) }
        }
    }
}
