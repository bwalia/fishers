import UIKit
import XCTest
@testable import Fishers

/// Step A of club payments, "easy paying". The fixtures are real responses
/// from the local API (`.dev/payments/examples/stepA_*.json`, demo club
/// "Riverside Strikers"); the network ones answer from a stub.
final class EasyPayingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Strings.setCurrent(.en)
        EasyPayingStub.reset()
    }

    override func tearDown() {
        EasyPayingStub.reset()
        super.tearDown()
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
            "\(name).json is missing from the test bundle"
        )
        return try Data(contentsOf: url)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try FishersJSONDecoder.make().decode(T.self, from: fixture(name))
    }

    private func decode<T: Decodable>(_ type: T.Type, json: String) throws -> T {
        try FishersJSONDecoder.make().decode(T.self, from: Data(json.utf8))
    }

    private func object(_ value: some Encodable) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    // MARK: - Sharing the bill

    func testTheBillLinkDecodes() throws {
        let link = try decode(BillLink.self, "pay_stepA_bill_link")
        XCTAssertTrue(link.url.contains("/p/"))
        XCTAssertTrue(link.billMessage.hasPrefix("🏏 Friday nets"))
        XCTAssertTrue(link.billMessage.contains("Tap to pay: \(link.url)"))
        XCTAssertTrue(link.reminderMessage.hasPrefix("Still to pay for Friday nets"))
        XCTAssertEqual(link.stillToPay, ["Aman Gill", "Tom Bennett"])
        XCTAssertNotNil(link.expiresAt)
    }

    func testABillLinkWithLessInItStillDecodes() throws {
        let link = try decode(BillLink.self, json: #"{"url":"https://x.test/p/abc"}"#)
        XCTAssertEqual(link.billMessage, "https://x.test/p/abc", "nothing to say but the link: share the link")
        XCTAssertEqual(link.reminderMessage, link.billMessage)
        XCTAssertTrue(link.stillToPay.isEmpty)
    }

    /// The message arrives in WhatsApp exactly as the server wrote it — an
    /// "&" or "+" left bare in the query would cut it short or turn into a space.
    func testTheWhatsAppLinkCarriesTheWholeMessage() throws {
        let message = "🏏 Friday nets, Fri 20 Nov: £5.00 each & tea + cake.\nTap to pay: http://192.168.1.9:7311/p/UO0Z-uBs?x=1"
        let url = try XCTUnwrap(WhatsApp.sendURL(message))
        XCTAssertEqual(url.scheme, "whatsapp")
        XCTAssertEqual(url.host, "send")
        XCTAssertTrue(url.absoluteString.contains("%26"), "the & is encoded")
        XCTAssertTrue(url.absoluteString.contains("%2B"), "the + is encoded")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "text")
        XCTAssertEqual(items.first?.value, message)
    }

    func testCashAndAllArrivedSaySoPlainly() throws {
        let admin = try decode(CashRecorded.self, json: #"{"recorded":2,"total_cents":3000,"received":true}"#)
        XCTAssertEqual(EventMoneyStore.cashNotice(admin, currency: "GBP"), "£30.00 in cash, marked as paid.")
        let captain = try decode(CashRecorded.self, json: #"{"recorded":1,"total_cents":1500,"received":false}"#)
        XCTAssertEqual(EventMoneyStore.cashNotice(captain, currency: "GBP"),
                       "£15.00 in cash noted. The treasurer ticks it off once they have it.")
        let none = try decode(CashRecorded.self, json: #"{"recorded":0,"total_cents":0,"received":true}"#)
        XCTAssertEqual(EventMoneyStore.cashNotice(none, currency: "GBP"),
                       "Nothing new to note. They had already paid, or said they had.")

        let all = try decode(ConfirmedMany.self, json: #"{"confirmed":3,"skipped":0}"#)
        XCTAssertEqual(ClubMoneyStore.arrivedNotice(all), "3 marked as arrived.")
        let some = try decode(ConfirmedMany.self, json: #"{"confirmed":2,"skipped":1}"#)
        XCTAssertEqual(ClubMoneyStore.arrivedNotice(some), "2 marked as arrived. 1 had already been checked by someone else.")
    }

    // MARK: - The pay screen

    func testThePayScreenSaysWhoTheMoneyGoesTo() throws {
        let screen = try decode(PayScreen.self, "pay_stepA_pay_screen")
        XCTAssertEqual(screen.reference, "SHARMA", "a readable reference, not a code")
        let account = try XCTUnwrap(screen.payableAccount)
        XCTAssertEqual(account.payeeRole, "secretary")
        XCTAssertEqual(account.payeeSentence, "Pay Aman Gill, the club secretary.")
        XCTAssertEqual(account.ownAccountSentence, "This is Aman's own bank account. The club uses it to collect money.")
        XCTAssertEqual(account.payeeShortName, "Aman")
        XCTAssertFalse(account.debugDescription.contains("12345678"), "a description must not carry the full number")
        XCTAssertEqual(screen.claims.count, 3)
        XCTAssertTrue(screen.claims.allSatisfy { !$0.hasScreenshot && $0.shareId == nil && $0.viaLink == nil })
    }

    func testAClubAccountIsPaidByItsName() {
        XCTAssertEqual(Payee.sentence("Riverside Strikers CC", role: nil), "Pay Riverside Strikers CC.")
        XCTAssertNil(Payee.ownAccountSentence("Riverside Strikers CC", isPersonal: false))
        XCTAssertEqual(Payee.shortName("Riverside Strikers CC", isPersonal: false), "Riverside Strikers CC")
        XCTAssertEqual(Payee.sentence("Tara Treasurer", role: "treasurer"), "Pay Tara Treasurer, the club treasurer.")
        XCTAssertEqual(Payee.sentence("Aman Gill", role: "owner"), "Pay Aman Gill, who runs the club.")
        XCTAssertEqual(Payee.sentence("Aman Gill", role: "chairman"), "Pay Aman Gill.", "a role this build doesn't know")
    }

    func testOneThingOwedIsNamedInTheHeadline() throws {
        let one = try decode(PayScreen.self, "pay_pay_screen")
        XCTAssertEqual(one.owedShares.count, 1)
        XCTAssertEqual(one.owedHeadline, "You owe £15.00 for \(one.owedShares[0].title).")

        let share = { (title: String) in
            """
            {"id":"\(UUID().uuidString)","bill_id":"\(UUID().uuidString)","event_id":"\(UUID().uuidString)",
             "title":"\(title)","event_start_at":"2026-11-20T08:41:00Z","name":"Ravi Sharma",
             "amount_cents":500,"paid_cents":0,"waiting_cents":0,"currency":"GBP","state":"owed"}
            """
        }
        let two = try decode(PayScreen.self, json: """
            {"club_id":"\(UUID().uuidString)","club_name":"Riverside","currency":"GBP","owed_cents":1000,
             "shares":[\(share("Friday nets")),\(share("Sunday match"))],"account_state":"none","reference":"SHARMA"}
            """)
        XCTAssertEqual(two.owedHeadline, "You owe £10.00.")
        XCTAssertNil(two.detailsToSend, "no details to send while the club has none")
    }

    func testTheDetailsToSendSomeoneUseThePayScreensWords() throws {
        let screen = try decode(PayScreen.self, "pay_pay_screen")
        let text = try XCTUnwrap(screen.detailsToSend)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "Please pay Riverside Strikers (demo) for me:")
        XCTAssertTrue(lines.contains("Amount: £15.00"))
        XCTAssertTrue(lines.contains("Name: Riverside Strikers CC"))
        XCTAssertTrue(lines.contains("Sort code: 20-00-00"))
        XCTAssertTrue(lines.contains("Account number: 55779911"))
        XCTAssertTrue(lines.contains("What to write in the reference box: 8VF52 SHARMA"))
        XCTAssertFalse(text.lowercased().contains("reference code"))
    }

    /// "First time? Here's how" until they've said they paid this club by
    /// transfer on this phone — per club, since each pays somebody different.
    func testTheGuideIsRememberedPerClubOnThisPhone() throws {
        let suite = "easy-paying-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let riverside = UUID(), oakfield = UUID()
        XCTAssertFalse(PayGuide.hasPaidBefore(clubId: riverside, defaults: defaults))
        PayGuide.rememberPaid(clubId: riverside, defaults: defaults)
        XCTAssertTrue(PayGuide.hasPaidBefore(clubId: riverside, defaults: defaults))
        XCTAssertFalse(PayGuide.hasPaidBefore(clubId: oakfield, defaults: defaults))
    }

    func testPaymentsCarryTheirScreenshotAndLink() throws {
        let link = UUID(), share = UUID()
        let payment = try decode(ClubPayment.self, json: """
            {"id":"\(UUID().uuidString)","club_id":"\(UUID().uuidString)","user_id":null,"guest_name":"Sam",
             "name":"Sam","amount_cents":500,"currency":"GBP","method":"transfer","reference":"SAM",
             "status":"claimed","created_at":"2026-11-21T12:40:20.851497Z",
             "share_id":"\(share.uuidString)","via_link":"\(link.uuidString)","has_screenshot":true}
            """)
        XCTAssertTrue(payment.hasScreenshot)
        XCTAssertEqual(payment.viaLink, link)
        XCTAssertEqual(payment.shareId, share)
        XCTAssertTrue(payment.isWaiting)

        // A server from before step A sends none of them.
        let old = try decode([ClubPayment].self, "pay_payments_claimed")
        XCTAssertEqual(old.first?.hasScreenshot, false)
        XCTAssertNil(old.first?.viaLink)
    }

    /// The new words come from the shared dictionary, so they read in
    /// Punjabi like the rest of the pay screen.
    func testTheNewWordsReadInPunjabi() {
        Strings.setCurrent(.pa)
        defer { Strings.setCurrent(.en) }
        for english in [
            "First time? Here's how", "What to write in the reference box", "Send these details to someone",
            "Add a screenshot", "Share the bill", "Tell the group", "All arrived", "Who paid cash?",
            "Set up payments", "Sign in with WhatsApp", "Type the code from WhatsApp",
        ] {
            let said = tr(english)
            XCTAssertTrue(said.unicodeScalars.contains { (0x0A00...0x0A7F).contains($0.value) }, "\(english) -> \(said)")
        }
        XCTAssertTrue(tr("Pay {name} as usual.", vars: ["name": "Aman"]).contains("Aman"), "the name survives translation")
    }

    // MARK: - Shares that aren't a session's (passes and group fees, next)

    func testALineWithNoEventAndANewStateDecodes() throws {
        let share = try decode(ClubShare.self, json: """
            {"id":"\(UUID().uuidString)","bill_id":"\(UUID().uuidString)","title":"November nets pass",
             "event_start_at":"2026-11-01T00:00:00Z","user_id":null,"guest_name":null,"name":"Ravi Sharma",
             "amount_cents":0,"paid_cents":0,"waiting_cents":0,"currency":"GBP","state":"covered",
             "reason":null,"kind":"pass","due_on":"2026-12-01"}
            """)
        XCTAssertNil(share.eventId)
        XCTAssertEqual(share.state, .covered)
        XCTAssertEqual(share.state.label, "Covered by your pass")
        XCTAssertFalse(share.state.stillOwed, "nothing to pay")
        XCTAssertFalse(share.state.canBeLetOff)
        XCTAssertEqual(share.kind, "pass")
        XCTAssertEqual(share.dueOn, "2026-12-01")
        XCTAssertEqual(ShareState(raw: "covered").raw, "covered")
    }

    /// The pay link's person is a share with more on it: the extras must not
    /// get in the way of reading it as one.
    func testALinkPersonReadsAsAShare() throws {
        let share = try decode(ClubShare.self, "pay_stepA_link_person")
        XCTAssertEqual(share.name, "Ravi Sharma")
        XCTAssertEqual(share.state, .paid)
        XCTAssertNotNil(share.eventId)
        XCTAssertNil(share.kind)
    }

    // MARK: - Usual prices, and setting up

    func testTheUsualPricesAreReadFromTheSettings() throws {
        let settings = try decode(PaymentSettings.self, "pay_stepA_settings")
        XCTAssertEqual(settings.usualPrices.nets, UsualPrices.Price(mode: .splitTotal, amountCents: 6000))
        XCTAssertEqual(settings.usualPrices.matchFeeCents, 500)
        // The schedule form starts from them.
        XCTAssertEqual(settings.usualPrices.cost(for: .nets), ScheduleCost(mode: .splitTotal, amountCents: 6000))
        XCTAssertEqual(settings.usualPrices.cost(for: .match), ScheduleCost(mode: .perPlayer, amountCents: 500))
        XCTAssertNil(settings.usualPrices.cost(for: .training))

        let before = try decode(PaymentSettings.self, json: #"{"auto_bill":true,"auto_bill_after_hours":24,"round_shares_up":false}"#)
        XCTAssertTrue(before.usualPrices.isEmpty, "a server from before step A")
        XCTAssertNil(before.usualPrices.cost(for: .nets))
    }

    /// The settings toggles save on every tap. Sending the prices with them —
    /// even as null — would clear them, so they are never sent from there.
    func testSavingTheSwitchesNeverTouchesThePrices() throws {
        let settings = try decode(PaymentSettings.self, "pay_stepA_settings")
        let sent = try object(settings)
        XCTAssertEqual(Set(sent.keys), ["auto_bill", "auto_bill_after_hours", "round_shares_up"])
    }

    func testSavingThePricesSendsBothAndNullClears() throws {
        let both = try object(UsualPricesBody(prices: UsualPrices(
            nets: .init(mode: .perPlayer, amountCents: 500), matchFeeCents: 700
        )))
        let nets = try XCTUnwrap(both["default_nets"] as? [String: Any])
        XCTAssertEqual(nets["mode"] as? String, "per_player")
        XCTAssertEqual(nets["amount_cents"] as? Int, 500)
        XCTAssertEqual(both["default_match_fee_cents"] as? Int, 700)
        XCTAssertNil(both["auto_bill"], "the switches are left as they are")

        let cleared = try object(UsualPricesBody(prices: UsualPrices()))
        XCTAssertTrue(cleared["default_nets"] is NSNull)
        XCTAssertTrue(cleared["default_match_fee_cents"] is NSNull)
    }

    func testThePricesFormRoundTripsAndCatchesAMissingAmount() {
        let usual = UsualPrices(nets: .init(mode: .splitTotal, amountCents: 6000), matchFeeCents: 500)
        var draft = UsualPricesDraft(usual, currency: "GBP")
        XCTAssertTrue(draft.netsOn)
        XCTAssertEqual(draft.netsAmount, "60.00")
        XCTAssertEqual(draft.matchAmount, "5.00")
        XCTAssertEqual(draft.prices(currency: "GBP"), usual)

        draft.matchOn = false
        XCTAssertEqual(draft.prices(currency: "GBP"), UsualPrices(nets: usual.nets), "switched off is cleared")

        draft.netsAmount = ""
        XCTAssertNil(draft.prices(currency: "GBP"), "switched on with no amount is not saved")
        draft.netsAmount = "7.505"
        XCTAssertNil(draft.prices(currency: "GBP"))

        let empty = UsualPricesDraft(UsualPrices(), currency: "GBP")
        XCTAssertFalse(empty.netsOn)
        XCTAssertFalse(empty.matchOn)
        XCTAssertEqual(empty.prices(currency: "GBP"), UsualPrices())
    }

    /// The wizard is offered to a money admin when the club has neither bank
    /// details nor usual prices.
    func testTheWizardIsOfferedOnlyWhenNothingIsSetUp() throws {
        let overview = { (settings: String, current: String) in
            """
            {"currency":"GBP","settings":\(settings),
             "account":{"can_manage":true,"is_owner":true,"current":\(current),"pending":null,"frozen":null,"changed_at":null},
             "to_check":[],"members":[],"bills":[]}
            """
        }
        let bare = #"{"auto_bill":true,"auto_bill_after_hours":24,"round_shares_up":false}"#
        let priced = #"{"auto_bill":true,"auto_bill_after_hours":24,"round_shares_up":false,"default_match_fee_cents":500}"#
        let account = #"{"id":"4dd8d3d4-21cb-4a16-9875-d98a03f66be4","label":"Club account","holder_name":"Riverside CC","is_personal":false,"sort_code":"20-00-00","last4":"9911","state":"active","live_from":"2026-11-21T10:41:35Z"}"#

        XCTAssertTrue(try decode(MoneyOverview.self, json: overview(bare, "null")).needsSetup)
        XCTAssertFalse(try decode(MoneyOverview.self, json: overview(priced, "null")).needsSetup, "prices set")
        XCTAssertFalse(try decode(MoneyOverview.self, json: overview(bare, account)).needsSetup, "bank details set")
        XCTAssertFalse(try decode(MoneyOverview.self, "pay_money_overview").needsSetup)
    }

    // MARK: - A screenshot of the payment

    /// A noisy picture JPEG can't squeeze: the worst case for the size limit.
    private func noise(width: Int, height: Int) throws -> UIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        arc4random_buf(&bytes, bytes.count)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let cg = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        return UIImage(cgImage: cg)
    }

    private func pixelSize(_ jpeg: Data) throws -> CGSize {
        let image = try XCTUnwrap(UIImage(data: jpeg))
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    func testABigPhotoBecomesAJPEGTheServerTakes() throws {
        let photo = try noise(width: 4032, height: 3024)
        let jpeg = try XCTUnwrap(PaymentScreenshot.jpeg(from: photo))
        XCTAssertLessThanOrEqual(jpeg.count, PaymentScreenshot.maxBytes)
        XCTAssertEqual([UInt8](jpeg.prefix(3)), [0xFF, 0xD8, 0xFF], "JPEG, whatever it started as")
        let size = try pixelSize(jpeg)
        XCTAssertLessThanOrEqual(max(size.width, size.height), PaymentScreenshot.maxPixels)
        XCTAssertEqual(size.width / size.height, 4032.0 / 3024.0, accuracy: 0.01, "the shape is kept")
    }

    func testASmallPNGScreenshotIsConvertedButNotEnlarged() throws {
        let screenshot = try noise(width: 390, height: 844)
        let png = try XCTUnwrap(screenshot.pngData())
        let jpeg = try XCTUnwrap(PaymentScreenshot.jpeg(from: png))
        XCTAssertEqual([UInt8](jpeg.prefix(3)), [0xFF, 0xD8, 0xFF])
        XCTAssertEqual(try pixelSize(jpeg), CGSize(width: 390, height: 844))
    }

    func testAHEICPhotoBecomesAJPEG() throws {
        let photo = try noise(width: 2000, height: 1500)
        let heic = NSMutableData()
        guard let cg = photo.cgImage,
              let destination = CGImageDestinationCreateWithData(heic, "public.heic" as CFString, 1, nil)
        else { throw XCTSkip("this simulator cannot write HEIC") }
        CGImageDestinationAddImage(destination, cg, nil)
        try XCTSkipUnless(CGImageDestinationFinalize(destination), "this simulator cannot write HEIC")
        let jpeg = try XCTUnwrap(PaymentScreenshot.jpeg(from: heic as Data))
        XCTAssertEqual([UInt8](jpeg.prefix(3)), [0xFF, 0xD8, 0xFF], "the server refuses HEIC")
        XCTAssertLessThanOrEqual(jpeg.count, PaymentScreenshot.maxBytes)
        XCTAssertLessThanOrEqual(try pixelSize(jpeg).width, PaymentScreenshot.maxPixels)
    }

    func testSomethingThatIsNotAPictureIsRefusedHere() {
        XCTAssertNil(PaymentScreenshot.jpeg(from: Data("not a picture".utf8)))
    }

    /// The bytes go up as they are, as image/jpeg, and the payment's
    /// Idempotency-Key survives a session refresh.
    func testTheScreenshotIsSentAsRawBytes() async throws {
        let service = stubbedService()
        await service.setTokens(access: "stale", refresh: "rt-1")
        let picture = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        EasyPayingStub.handler = { request, body in
            if request.url?.path.hasSuffix("/auth/refresh") == true {
                return (200, Data(#"{"access_token":"fresh","refresh_token":"rt-2"}"#.utf8))
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer stale" { return (401, Data("{}".utf8)) }
            return (204, Data())
        }
        let key = UUID().uuidString
        _ = try await service.data(
            "POST", path: "/payments/x/screenshot", rawBody: picture, contentType: "image/jpeg",
            headers: ["idempotency-key": key]
        )
        XCTAssertEqual(EasyPayingStub.seen.count, 2, "refused once, then sent again")
        for (request, body) in EasyPayingStub.seen {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), key)
            XCTAssertEqual(body, picture)
        }
        await service.clearTokens()
    }

    // MARK: - Signing in with WhatsApp

    private func stubbedService() -> NetworkService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EasyPayingStub.self]
        return NetworkService(session: URLSession(configuration: config))
    }

    private static let tokens = """
        {"access_token":"a","refresh_token":"r","token_type":"Bearer","expires_in":900,
         "user":{"id":"1053c505-eac3-4b82-a124-e0124e0550b9","name":"Ravi Sharma","sports_played":[]}}
        """

    private func refusal(_ status: Int, _ code: String, _ sentence: String) -> (Int, Data) {
        (status, Data(#"{"error":"\#(sentence)","code":"\#(code)"}"#.utf8))
    }

    @MainActor
    func testWhatsAppSignInIsOfferedOnlyWhenTheServerSaysSo() async {
        let store = WhatsAppSignInStore(network: stubbedService())
        EasyPayingStub.handler = { _, _ in (200, Data(#"{"enabled":true}"#.utf8)) }
        await store.checkEnabled()
        XCTAssertTrue(store.isEnabled)

        EasyPayingStub.handler = { _, _ in (200, Data(#"{"enabled":false}"#.utf8)) }
        await store.checkEnabled()
        XCTAssertFalse(store.isEnabled)

        // An older server has no such route: not offered.
        EasyPayingStub.handler = { _, _ in (404, Data(#"{"error":"not found"}"#.utf8)) }
        await store.checkEnabled()
        XCTAssertFalse(store.isEnabled)
    }

    @MainActor
    func testANumberThenTheCodeSignsIn() async throws {
        let store = WhatsAppSignInStore(network: stubbedService())
        EasyPayingStub.handler = { request, _ in
            switch request.url?.path ?? "" {
            case let path where path.hasSuffix("/auth/whatsapp"): return (200, Data(#"{"enabled":true}"#.utf8))
            case let path where path.hasSuffix("/start"):
                return (200, Data(#"{"sent":true,"expires_in":600,"resend_after":60}"#.utf8))
            default: return (200, Data(Self.tokens.utf8))
            }
        }
        await store.checkEnabled()
        XCTAssertFalse(store.canSendCode, "nothing typed yet")
        store.phone = "  +44 7700 900123 "
        let now = Date()
        await store.sendCode(now: now)
        XCTAssertEqual(store.step, .code)
        XCTAssertNil(store.problem)
        XCTAssertEqual(store.resendAt, now.addingTimeInterval(60))
        XCTAssertFalse(store.canResend(at: now.addingTimeInterval(30)))
        XCTAssertTrue(store.canResend(at: now.addingTimeInterval(60)))

        store.setCode("12 34-56789")
        XCTAssertEqual(store.code, "123456", "digits only, six at most")
        let verified = await store.verify()
        let signedIn = try XCTUnwrap(verified)
        XCTAssertEqual(signedIn.user.name, "Ravi Sharma")

        let bodies = EasyPayingStub.seen.compactMap { try? JSONSerialization.jsonObject(with: $0.1 ?? Data()) as? [String: String] }
        XCTAssertEqual(bodies.first?["phone"], "+44 7700 900123", "sent trimmed")
        XCTAssertEqual(bodies.last?["code"], "123456")
        XCTAssertTrue(EasyPayingStub.seen.allSatisfy { $0.0.value(forHTTPHeaderField: "Authorization") == nil },
                      "nobody is signed in yet")
    }

    @MainActor
    func testEachRefusalShowsTheServersSentence() async {
        let store = WhatsAppSignInStore(network: stubbedService())
        store.phone = "07700 900123"
        let cases: [(Int, String, String)] = [
            (400, "bad_phone", "That doesn't look like a mobile number. Put the country code first, like +44 7700 900123."),
            (429, "slow_down", "A code is already on its way. Wait a minute before asking for another."),
            (502, "not_sent", "We couldn't send the WhatsApp message just now. Try again in a minute."),
        ]
        for (status, code, sentence) in cases {
            EasyPayingStub.handler = { _, _ in self.refusal(status, code, sentence) }
            await store.sendCode()
            XCTAssertEqual(store.problem, sentence, code)
            XCTAssertEqual(store.step, .number, "\(code) keeps them on the number")
        }
    }

    @MainActor
    func testAWrongCodeClearsTheBoxes() async {
        let store = WhatsAppSignInStore(network: stubbedService())
        EasyPayingStub.handler = { request, _ in
            if request.url?.path.hasSuffix("/start") == true {
                return (200, Data(#"{"sent":true,"expires_in":600,"resend_after":60}"#.utf8))
            }
            return self.refusal(400, "wrong_code", "That code isn't right, or it has run out. Ask for a new one.")
        }
        store.phone = "+44 7700 900123"
        await store.sendCode()
        store.setCode("000000")
        let signedIn = await store.verify()
        XCTAssertNil(signedIn)
        XCTAssertEqual(store.problem, "That code isn't right, or it has run out. Ask for a new one.")
        XCTAssertEqual(store.code, "", "ready for the right one")
        XCTAssertEqual(store.step, .code)

        store.useAnotherNumber()
        XCTAssertEqual(store.step, .number)
        XCTAssertNil(store.problem)
    }

    @MainActor
    func testSwitchedOffOnTheServerTakesTheOptionAway() async {
        let store = WhatsAppSignInStore(network: stubbedService())
        EasyPayingStub.handler = { _, _ in (200, Data(#"{"enabled":true}"#.utf8)) }
        await store.checkEnabled()
        EasyPayingStub.handler = { _, _ in
            self.refusal(503, "whatsapp_off", "Signing in with WhatsApp isn't switched on yet. Use your email and password.")
        }
        store.phone = "+44 7700 900123"
        await store.sendCode()
        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(store.problem, "Signing in with WhatsApp isn't switched on yet. Use your email and password.")
    }
}

/// Answers from a closure and keeps what was sent, body included — which
/// URLSession hands a protocol as a stream rather than `httpBody`.
private final class EasyPayingStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest, Data?) -> (Int, Data))?
    nonisolated(unsafe) static var seen: [(URLRequest, Data?)] = []

    static func reset() {
        handler = nil
        seen = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = EasyPayingStub.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        if !(request.url?.path.hasSuffix("/auth/refresh") ?? false) {
            EasyPayingStub.seen.append((request, body))
        }
        let (status, data) = handler(request, body)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            guard n > 0 else { break }
            out.append(buffer, count: n)
        }
        return out
    }
}
