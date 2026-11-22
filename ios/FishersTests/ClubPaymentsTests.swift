import XCTest
@testable import Fishers

/// Paying the club by bank transfer. The fixtures are real responses from the
/// local API (`.dev/payments/examples`, demo club "Riverside Strikers"), so a
/// change in what the server sends shows up here before it shows up as an
/// empty screen on somebody's phone.
final class ClubPaymentsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Strings.setCurrent(.en)
        HeaderStub.reset()
    }

    override func tearDown() {
        HeaderStub.reset()
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

    /// A fixture with one string swapped, to stand in for a newer server.
    private func decode<T: Decodable>(_ type: T.Type, _ name: String, replacing old: String, with new: String) throws -> T {
        let text = try XCTUnwrap(String(data: fixture(name), encoding: .utf8))
        XCTAssertTrue(text.contains(old), "\(name) no longer contains \(old)")
        return try FishersJSONDecoder.make().decode(T.self, from: Data(text.replacingOccurrences(of: old, with: new).utf8))
    }

    // MARK: - Decoding what the API sends

    func testAnAdminsBillDecodes() throws {
        let page = try decode(EventBillPage.self, "pay_bill_billed_admin")
        XCTAssertEqual(page.title, "Friday nets")
        XCTAssertTrue(page.canBill)
        XCTAssertTrue(page.canManageMoney)
        XCTAssertEqual(page.cost?.mode, .splitTotal)
        XCTAssertEqual(page.cost?.amountCents, 6000)
        let bill = try XCTUnwrap(page.bill)
        XCTAssertEqual(bill.version, 1)
        XCTAssertEqual(bill.totalCents, 6000)
        XCTAssertEqual(bill.paidCents, 1500)
        XCTAssertEqual(bill.waitingCents, 1500)
        XCTAssertEqual(bill.owedCents, 3000)
        XCTAssertEqual(page.shares.map(\.state), [.owed, .paid, .owed, .waiting])
        XCTAssertEqual(page.myShare?.name, "Aman Gill")
        XCTAssertEqual(page.myShare?.state, .owed)
        // Re-splitting starts from who is on the bill, not from the RSVPs.
        XCTAssertEqual(page.billedMembers.count, 4)
        XCTAssertFalse(page.billedMembers.contains(UUID(uuidString: "6fc1c369-7289-47c9-9398-186c9f50250c")!))
        XCTAssertTrue(page.isRelevant)
    }

    func testAPlayerSeesOnlyTheirOwnShare() throws {
        let page = try decode(EventBillPage.self, "pay_bill_billed_player")
        XCTAssertFalse(page.canBill)
        XCTAssertFalse(page.canManageMoney)
        XCTAssertEqual(page.shares.count, 1)
        XCTAssertEqual(page.myShare?.name, "Ravi Sharma")
        XCTAssertEqual(page.myShare?.leftCents, 1500)
        XCTAssertTrue(page.candidates.isEmpty)
        XCTAssertTrue(page.isRelevant)
    }

    func testAnUnbilledEventSuggestsWhoSaidGoing() throws {
        let page = try decode(EventBillPage.self, "pay_bill_unbilled_admin")
        XCTAssertNil(page.bill)
        XCTAssertEqual(page.cost?.mode, .perPlayer)
        XCTAssertEqual(page.cost?.summary, "£5.00 each")
        XCTAssertEqual(page.suggestedMembers.count, 3)
        XCTAssertTrue(page.candidates.allSatisfy(\.wasInvited))
        XCTAssertEqual(page.candidates.first { $0.name == "Josh Turner" }?.answer, "Said they'd come")
        XCTAssertEqual(page.candidates.first { $0.name == "Tara Treasurer" }?.answer, "Didn't answer")
    }

    /// Since 21 Nov the candidates include every active member: those never
    /// asked come last as `not_invited`, unticked.
    func testAMemberWhoWasNeverAskedIsListedApart() throws {
        let json = """
        {"user_id":"\(UUID().uuidString)","name":"Walk In","rsvp":"not_invited","attended":null,"suggested":false}
        """
        let candidate = try FishersJSONDecoder.make().decode(BillCandidate.self, from: Data(json.utf8))
        XCTAssertFalse(candidate.wasInvited)
        XCTAssertFalse(candidate.suggested)
        XCTAssertNil(candidate.answer)
    }

    func testThePreviewSaysWhatEachPays() throws {
        let preview = try decode(BillPreview.self, "pay_bill_preview")
        XCTAssertEqual(preview.totalCents, 2000)
        XCTAssertEqual(preview.shares.count, 4)
        XCTAssertNil(preview.shares.last?.userId, "the guest has no account")
        XCTAssertEqual(preview.summary, "4 people · £20.00 in all · £5.00 each")
    }

    func testPenniesThatDoNotDivideAreSaid() throws {
        let json = """
        {"shares":[{"user_id":null,"name":"A","amount_cents":667},{"user_id":null,"name":"B","amount_cents":667},
                   {"user_id":null,"name":"C","amount_cents":666}],
         "total_cents":2000,"surplus_cents":0,"currency":"GBP"}
        """
        let preview = try FishersJSONDecoder.make().decode(BillPreview.self, from: Data(json.utf8))
        XCTAssertEqual(preview.summary, "3 people · £20.00 in all · 2 pay £6.67 · 1 pays £6.66")
    }

    func testDuesDecode() throws {
        let dues = try decode(MyDues.self, "pay_me_dues")
        XCTAssertEqual(dues.clubs.count, 1)
        XCTAssertEqual(dues.owing.first?.clubName, "Riverside Strikers (demo)")
        XCTAssertEqual(dues.owedSummary, "£15.00")
        XCTAssertEqual(dues.clubs.first?.shares.first?.state, .owed)
    }

    func testOwedAcrossCurrenciesIsNotAddedUp() throws {
        let club = { (currency: String, owed: Int) in
            """
            {"club_id":"\(UUID().uuidString)","club_name":"X","currency":"\(currency)","owed_cents":\(owed),
             "waiting_cents":0,"credit_cents":0,"shares":[]}
            """
        }
        let json = #"{"clubs":["# + [club("GBP", 1500), club("INR", 50000), club("GBP", 500)].joined(separator: ",") + "]}"
        let dues = try FishersJSONDecoder.make().decode(MyDues.self, from: Data(json.utf8))
        XCTAssertEqual(dues.owedSummary, "£20.00 + ₹500.00")
    }

    func testThePayScreenDecodesWithTheDetailsToCopy() throws {
        let screen = try decode(PayScreen.self, "pay_pay_screen")
        XCTAssertEqual(screen.accountState, .active)
        XCTAssertEqual(screen.owedCents, 1500)
        XCTAssertEqual(screen.reference, "8VF52 SHARMA")
        let account = try XCTUnwrap(screen.payableAccount)
        XCTAssertEqual(account.holderName, "Riverside Strikers CC")
        XCTAssertEqual(account.sortCode, "20-00-00")
        XCTAssertFalse(account.debugDescription.contains("55779911"), "a description must not carry the full number")

        let all = try XCTUnwrap(screen.detailsToSend)
        XCTAssertTrue(all.contains("Riverside Strikers CC"))
        XCTAssertTrue(all.contains("20-00-00"))
        XCTAssertTrue(all.contains("55779911"))
        XCTAssertTrue(all.contains("8VF52 SHARMA"))
        XCTAssertTrue(all.contains("£15.00"))
    }

    func testNothingOwedShowsNoDetails() throws {
        let screen = try decode(PayScreen.self, "pay_pay_screen_nothing_owed")
        XCTAssertEqual(screen.accountState, .nothingOwed)
        XCTAssertNil(screen.payableAccount)
        XCTAssertNil(screen.detailsToSend)
        XCTAssertEqual(screen.accountState.explanation, "You're all paid up.")
    }

    func testAClaimWaitingForTheTreasurer() throws {
        let screen = try decode(PayScreen.self, "pay_pay_screen_waiting")
        XCTAssertEqual(screen.owedCents, 0)
        XCTAssertEqual(screen.waitingCents, 1500)
        XCTAssertEqual(screen.claims.count, 1)
        XCTAssertEqual(screen.claims.first?.status, .claimed)
        XCTAssertEqual(screen.claims.first?.methodLabel, "Bank transfer")
        XCTAssertEqual(screen.shares.first?.state, .waiting)
        XCTAssertEqual(screen.shares.first?.state.label, "Waiting for the club to confirm")
    }

    func testTheTreasurersOverviewDecodes() throws {
        let overview = try decode(MoneyOverview.self, "pay_money_overview")
        XCTAssertEqual(overview.currency, "GBP")
        XCTAssertTrue(overview.settings.autoBill)
        XCTAssertEqual(overview.settings.autoBillAfterHours, 24)
        XCTAssertFalse(overview.settings.roundSharesUp)
        XCTAssertTrue(overview.account.canManage)
        XCTAssertEqual(overview.account.current?.masked, "20-00-00 · ••••9911")
        XCTAssertEqual(overview.account.current?.state, .active)
        XCTAssertNil(overview.account.pending)
        XCTAssertEqual(overview.toCheck.map(\.reference), ["DS69N BENNETT"])
        XCTAssertEqual(overview.members.count, 3)
        XCTAssertEqual(overview.totals?.owedCents, 3000)
        XCTAssertEqual(overview.bills.first?.unpaid, 2)
        XCTAssertEqual(overview.bills.first?.waiting, 1)
    }

    func testPaymentsAndBankDetailsDecode() throws {
        let claimed = try decode([ClubPayment].self, "pay_payments_claimed")
        XCTAssertEqual(claimed.first?.amountCents, 1500)
        let admin = try decode(PayoutAccounts.self, "pay_payout_account_admin")
        XCTAssertTrue(admin.canManage)
        XCTAssertTrue(admin.isOwner)
        let member = try decode(PayoutAccounts.self, "pay_payout_account_member")
        XCTAssertFalse(member.canManage)
        XCTAssertFalse(member.isOwner)
        XCTAssertEqual(member.current?.last4, "9911")
    }

    // MARK: - A newer server

    /// One unknown value must never fail the whole response: that is how a
    /// whole list once went blank on iOS.
    func testAnUnknownShareStateDecodes() throws {
        let dues = try decode(MyDues.self, "pay_me_dues", replacing: #""state": "owed""#, with: #""state": "written_off""#)
        let share = try XCTUnwrap(dues.clubs.first?.shares.first)
        XCTAssertEqual(share.state, .unknown("written_off"))
        XCTAssertEqual(share.state.label, "Written Off")
        XCTAssertFalse(share.state.stillOwed)
        XCTAssertEqual(dues.owedSummary, "£15.00", "the rest of the response is intact")
    }

    func testAnUnknownAccountStateShowsNoDetails() throws {
        let screen = try decode(PayScreen.self, "pay_pay_screen", replacing: #""account_state": "active""#, with: #""account_state": "upi_only""#)
        XCTAssertEqual(screen.accountState, .unknown("upi_only"))
        XCTAssertNil(screen.payableAccount, "only `active` details are offered to pay into")
        XCTAssertNotNil(screen.accountState.explanation)
        XCTAssertEqual(screen.owedCents, 1500)
    }

    func testUnknownPaymentAndPayoutStatesDecode() throws {
        let overview = try decode(
            MoneyOverview.self, "pay_money_overview",
            replacing: #""status": "claimed""#, with: #""status": "bounced""#
        )
        XCTAssertEqual(overview.toCheck.first?.status, .unknown("bounced"))
        let accounts = try decode(
            PayoutAccounts.self, "pay_payout_account_admin",
            replacing: #""state": "active""#, with: #""state": "verifying""#
        )
        XCTAssertEqual(accounts.current?.state, .unknown("verifying"))
    }

    func testAnUnknownCostModeDecodes() throws {
        let page = try decode(
            EventBillPage.self, "pay_bill_unbilled_admin",
            replacing: #""mode": "per_player""#, with: #""mode": "half_price_juniors""#
        )
        XCTAssertEqual(page.cost?.mode, .unknown("half_price_juniors"))
        XCTAssertEqual(page.cost?.summary, "£5.00 each")
    }

    func testStatesRoundTripTheirRawValue() throws {
        for raw in ["owed", "part_paid", "waiting", "paid", "waived", "void", "brand_new"] {
            XCTAssertEqual(ShareState(raw: raw).raw, raw)
        }
        let encoded = try JSONEncoder().encode([CostMode.perPlayer, .splitTotal])
        XCTAssertEqual(String(data: encoded, encoding: .utf8), #"["per_player","split_total"]"#)
    }

    /// The pay screen's words are the website's, so they read in Punjabi
    /// wherever the shared dictionary has them. Skipped when the bundled
    /// tables predate the payment words.
    func testThePayScreenSpeaksPunjabi() throws {
        try XCTSkipUnless(Strings.key(forEnglish: "I've paid") != nil, "string tables not regenerated with the payment words yet")
        Strings.setCurrent(.pa)
        defer { Strings.setCurrent(.en) }
        for english in ["I've paid", "I paid cash", "Copy all", "You're all paid up."] {
            let said = tr(english)
            XCTAssertTrue(said.unicodeScalars.contains { (0x0A00...0x0A7F).contains($0.value) }, "\(english) -> \(said)")
        }
    }

    // MARK: - Money

    func testMoneyIsFormattedInItsOwnCurrency() {
        XCTAssertEqual(Money.format(1500, "GBP"), "£15.00")
        XCTAssertEqual(Money.format(100_000, "GBP"), "£1,000.00")
        XCTAssertEqual(Money.format(5, "gbp"), "£0.05")
        XCTAssertEqual(Money.format(10_000_000, "INR"), "₹1,00,000.00")
    }

    func testTypedAmountsBecomeMinorUnits() {
        XCTAssertEqual(Money.parse("60", currency: "GBP"), 6000)
        XCTAssertEqual(Money.parse("7.5", currency: "GBP"), 750)
        XCTAssertEqual(Money.parse(" £1,000.50 ", currency: "GBP"), 100_050)
        XCTAssertEqual(Money.parse(".99", currency: "GBP"), 99)
        XCTAssertNil(Money.parse("7.505", currency: "GBP"), "a third decimal place is a typo")
        XCTAssertNil(Money.parse("", currency: "GBP"))
        XCTAssertNil(Money.parse("abc", currency: "GBP"))
        XCTAssertNil(Money.parse("1.2.3", currency: "GBP"))
        XCTAssertEqual(Money.parse("500", currency: "JPY"), 500)
        XCTAssertNil(Money.parse("5.5", currency: "JPY"))
    }

    func testAmountsEditAsPlainNumbers() {
        XCTAssertEqual(Money.plain(750, "GBP"), "7.50")
        XCTAssertEqual(Money.plain(6000, "GBP"), "60.00")
        XCTAssertEqual(Money.plain(5, "GBP"), "0.05")
        XCTAssertEqual(Money.parse(Money.plain(12_345, "GBP"), currency: "GBP"), 12_345)
    }

    // MARK: - The bank details form

    func testTheSortCodeIsFormattedAsItIsTyped() {
        XCTAssertEqual(BankDetailsCheck.formatSortCode("123456"), "12-34-56")
        XCTAssertEqual(BankDetailsCheck.formatSortCode("12345"), "12-34-5")
        XCTAssertEqual(BankDetailsCheck.formatSortCode("12-34-567"), "12-34-56")
    }

    func testTheAccountNumberHasToBeTypedTheSameTwice() {
        XCTAssertNil(BankDetailsCheck.problem(holder: "Riverside CC", sortCode: "20-00-00", account: "55779911", again: "55779911"))
        XCTAssertNil(BankDetailsCheck.problem(holder: "Riverside CC", sortCode: "200000", account: "5577991", again: "5577991"),
                     "seven digits is an older account; the server adds the zero")
        XCTAssertNotNil(BankDetailsCheck.problem(holder: "Riverside CC", sortCode: "20-00-00", account: "55779911", again: "55779912"))
        XCTAssertNotNil(BankDetailsCheck.problem(holder: "Riverside CC", sortCode: "20-00", account: "55779911", again: "55779911"))
        XCTAssertNotNil(BankDetailsCheck.problem(holder: " ", sortCode: "20-00-00", account: "55779911", again: "55779911"))
        XCTAssertNotNil(BankDetailsCheck.problem(holder: "Riverside CC", sortCode: "20-00-00", account: "557799", again: "557799"))
    }

    func testTheNewDetailsBodyUsesTheAPIsNames() throws {
        let body = NewPayoutAccount(
            holderName: "Riverside CC", sortCode: "200000", accountNumber: "55779911",
            label: nil, isPersonal: true, password: "pw"
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(object["holder_name"] as? String, "Riverside CC")
        XCTAssertEqual(object["sort_code"] as? String, "200000")
        XCTAssertEqual(object["account_number"] as? String, "55779911")
        XCTAssertEqual(object["is_personal"] as? Bool, true)
        XCTAssertEqual(object["password"] as? String, "pw")
    }

    // MARK: - Errors that are not failures

    func testErrorsThatMeanReloadOrRetypeThePassword() {
        let reauth = APIError.http(428, #"{"error":"Type your password to change the club's bank details","code":"reauth_required"}"#)
        XCTAssertTrue(reauth.wantsPassword)
        XCTAssertEqual(reauth.friendlyMessage, "Type your password to change the club's bank details")
        let wrong = APIError.http(403, #"{"error":"That password doesn't match","code":"wrong_password"}"#)
        XCTAssertTrue(wrong.wantsPassword)
        XCTAssertFalse(wrong.isStale)

        for code in ["version_conflict", "already_billed", "already_decided", "nothing_owed"] {
            let error = APIError.http(409, #"{"error":"Somebody got there first.","code":"\#(code)"}"#)
            XCTAssertTrue(error.isStale, code)
            XCTAssertEqual(error.friendlyMessage, "Somebody got there first.")
        }
        XCTAssertFalse(APIError.http(400, #"{"error":"x","code":"invalid_bank_details"}"#).isStale)
        XCTAssertFalse(APIError.unauthorized.isStale)
    }

    // MARK: - One attempt, one key

    func testARetryReusesTheKeyAndANewPaymentDoesNot() {
        var attempt = PaymentAttempt()
        let first = attempt.key(for: "claim:transfer")
        XCTAssertEqual(attempt.key(for: "claim:transfer"), first, "a retry of the same tap is the same request")
        XCTAssertNotEqual(attempt.key(for: "claim:cash"), first, "a different payment is a new attempt")
        let cash = attempt.key(for: "claim:cash")
        attempt.finished()
        XCTAssertNotEqual(attempt.key(for: "claim:cash"), cash, "after success the next tap is a new payment")
    }

    /// The key has to survive the refresh-and-retry inside NetworkService: a
    /// new key on the retry would let one tap make two claims.
    func testTheIdempotencyKeySurvivesASessionRefresh() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HeaderStub.self]
        let service = NetworkService(session: URLSession(configuration: config))
        await service.setTokens(access: "stale", refresh: "rt-1")
        HeaderStub.handler = { request in
            if request.url?.path.hasSuffix("/auth/refresh") == true {
                return (200, Data(#"{"access_token":"fresh","refresh_token":"rt-2"}"#.utf8))
            }
            HeaderStub.keys.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "none")
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer stale" {
                return (401, Data("{}".utf8))
            }
            return (200, Data(#"{"ok":true}"#.utf8))
        }
        struct Reply: Decodable { let ok: Bool }
        let key = UUID().uuidString
        let _: Reply = try await service.request(
            "POST", path: "/clubs/x/payments", body: ["method": "transfer"], headers: ["Idempotency-Key": key]
        )
        XCTAssertEqual(HeaderStub.keys, [key, key])
        await service.clearTokens()
    }

    // MARK: - Scheduling with a cost

    private let club = Club(
        id: UUID(), name: "Riverside", sportTypes: ["cricket"], visibility: "public",
        ownerId: UUID(), description: nil, isInformalGroup: false, role: nil
    )

    func testEveryWeekOfASeriesCarriesTheCost() {
        let bodies = ScheduleRequests.sessions(
            kind: .nets, club: club, teamId: nil, title: "Friday nets", venueId: nil,
            start: .now, minutes: 120, note: "", weeks: 3,
            cost: ScheduleCost(mode: .splitTotal, amountCents: 6000, note: "  ")
        )
        XCTAssertEqual(bodies.count, 3)
        for body in bodies {
            XCTAssertEqual(body.cost_mode, "split_total")
            XCTAssertEqual(body.cost_amount_cents, 6000)
            XCTAssertNil(body.cost_note, "a blank note is not sent")
        }
    }

    func testAMatchFeeIsSentAndNoCostSendsNothing() throws {
        let costed = ScheduleRequests.match(
            club: club, opponentClubId: nil, theirName: "Oakfield", venueId: nil, start: .now,
            cost: ScheduleCost(mode: .perPlayer, amountCents: 500)
        )
        XCTAssertEqual(costed.cost_mode, "per_player")
        XCTAssertEqual(costed.cost_amount_cents, 500)

        let plain = ScheduleRequests.match(club: club, opponentClubId: nil, theirName: "Oakfield", venueId: nil, start: .now)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        XCTAssertNil(object["cost_mode"], "an old-shaped body for an event with no cost")
        XCTAssertNil(object["cost_amount_cents"])
    }

    func testOnlyAHeftyFeeEachIsQuestioned() {
        XCTAssertTrue(ScheduleCost(mode: .perPlayer, amountCents: 10_001).needsConfirming)
        XCTAssertFalse(ScheduleCost(mode: .perPlayer, amountCents: 10_000).needsConfirming)
        XCTAssertFalse(ScheduleCost(mode: .splitTotal, amountCents: 50_000).needsConfirming)
    }

    // MARK: - Notifications

    private func notification(_ type: String, _ payload: [String: String]) throws -> AppNotification {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let json = """
        {"id":"\(UUID().uuidString)","type":"\(type)","payload":\(String(data: body, encoding: .utf8)!),
         "sent_at":"2026-11-21T10:41:35.123Z","read_at":null}
        """
        return try FishersJSONDecoder.make().decode(AppNotification.self, from: Data(json.utf8))
    }

    func testAnUnknownKindShowsItsStoredWords() throws {
        let item = try notification("something_new", ["title": "Riverside: a new thing", "body": "Something happened."])
        XCTAssertEqual(item.line, "Something happened.")
        XCTAssertEqual(item.heading, "Riverside: a new thing")
        let bare = try notification("something_new", [:])
        XCTAssertEqual(bare.line, "something new", "still readable with nothing stored")
        XCTAssertNil(bare.heading)
    }

    func testMoneyNotificationsOpenTheRightScreen() throws {
        let event = UUID(), club = UUID()
        XCTAssertEqual(
            try notification("bill_who_came", ["event_id": event.uuidString, "club_id": club.uuidString, "title": "t", "body": "b"]).moneyRoute,
            .event(event, whoCame: true)
        )
        XCTAssertEqual(
            try notification("bill_issued", ["event_id": event.uuidString, "club_id": club.uuidString, "title": "t", "body": "b"]).moneyRoute,
            .event(event, whoCame: false)
        )
        XCTAssertEqual(try notification("fee_reminder", ["club_id": club.uuidString, "title": "t", "body": "b"]).moneyRoute, .payScreen(club))
        XCTAssertEqual(try notification("payment_rejected", ["club_id": club.uuidString, "payment_id": UUID().uuidString, "title": "t", "body": "b"]).moneyRoute, .payScreen(club))
        XCTAssertEqual(try notification("payments_to_check", ["club_id": club.uuidString, "title": "t", "body": "b"]).moneyRoute, .overview(club))
        XCTAssertEqual(try notification("payout_details_changed", ["club_id": club.uuidString, "title": "t", "body": "b"]).moneyRoute, .overview(club))
        // Not money: an accepted invite mentions the club, with a link of its own.
        XCTAssertNil(try notification("invite_accepted", ["club_id": club.uuidString, "url": "/clubs/x#members", "player": "Sam"]).moneyRoute)
        XCTAssertNil(try notification("fixture_scheduled", ["event_id": event.uuidString, "title": "Sunday match"]).moneyRoute)
    }

    func testAMoneyPushOpensTheEventOrTheClub() {
        let event = UUID(), club = UUID()
        XCTAssertEqual(
            PushRegistrar.Target(["event_id": event.uuidString, "club_id": club.uuidString, "title": "t", "body": "b"]).money,
            .event(event)
        )
        XCTAssertEqual(PushRegistrar.Target(["club_id": club.uuidString, "title": "t", "body": "b"]).money, .club(club))
        // The season push mentions a club too, and goes to the season.
        let season = PushRegistrar.Target(["club_id": club.uuidString, "season": 2026, "url": "/stats?season=2026&club=\(club.uuidString)"])
        XCTAssertNotNil(season.season)
        XCTAssertNil(season.money)
        XCTAssertNil(PushRegistrar.Target(["club_id": club.uuidString, "url": "/tournaments/invite/x"]).money)
        XCTAssertNil(PushRegistrar.Target(["conversation_id": UUID().uuidString, "event_id": event.uuidString]).money)
    }
}

/// Answers requests from a closure, recording the Idempotency-Key each one
/// carried.
private final class HeaderStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var keys: [String] = []

    static func reset() {
        handler = nil
        keys = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = HeaderStub.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
