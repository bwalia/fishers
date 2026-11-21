import XCTest
@testable import Fishers

/// Step D of club payments (importing a bank statement) and the changes after
/// the security review (§13 of docs/CLUB_PAYMENTS_V2_PLAN.md). The fixtures
/// are real responses from the local API: `pay_stepD_*.json`, most from the
/// demo club "Riverside Strikers"; the network ones answer from a stub.
final class StatementImportTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Strings.setCurrent(.en)
        StatementStub.reset()
    }

    override func tearDown() {
        Strings.setCurrent(.en)
        StatementStub.reset()
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

    private func decode<T: Decodable>(_ type: T.Type, _ name: String, replacing pairs: [(String, String)]) throws -> T {
        var text = try XCTUnwrap(String(data: fixture(name), encoding: .utf8))
        for (old, new) in pairs {
            XCTAssertTrue(text.contains(old), "\(old) is not in \(name)")
            text = text.replacingOccurrences(of: old, with: new)
        }
        return try FishersJSONDecoder.make().decode(T.self, from: Data(text.utf8))
    }

    private func decode<T: Decodable>(_ type: T.Type, json: String) throws -> T {
        try FishersJSONDecoder.make().decode(T.self, from: Data(json.utf8))
    }

    private func stubbedService() -> NetworkService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StatementStub.self]
        return NetworkService(session: URLSession(configuration: config))
    }

    private func refusal(_ status: Int, _ code: String, _ sentence: String) -> (Int, Data) {
        (status, Data(#"{"error":"\#(sentence)","code":"\#(code)"}"#.utf8))
    }

    private var busy: (Int, Data) {
        refusal(409, "busy", "Hold on, that's still being saved. Try again in a moment.")
    }

    // MARK: - busy: one quiet retry, the same key

    @MainActor
    func testBusyIsRetriedOnceWithTheSameKey() async throws {
        let paid = try fixture("pay_stepBC_pay_for_others")
        var calls = 0
        StatementStub.handler = { _, _ in
            calls += 1
            return calls == 1 ? self.busy : (200, paid)
        }
        let store = PayForOthersStore(clubId: UUID(), network: stubbedService())
        let outcome = await store.pay(method: "transfer", people: [UUID()], includeMe: true)

        XCTAssertEqual(outcome, .done, "a double tap's busy isn't the person's problem")
        XCTAssertNil(store.problem)
        XCTAssertEqual(store.paid?.totalCents, 1500)
        let keys = StatementStub.seen.map { $0.0.value(forHTTPHeaderField: "Idempotency-Key") }
        XCTAssertEqual(keys.count, 2)
        XCTAssertNotNil(keys[0])
        XCTAssertEqual(keys[0], keys[1], "the retry asks for the first payment, not a second")
    }

    @MainActor
    func testBusyTwiceIsShownAndTheKeyIsKeptForTheNextTap() async throws {
        StatementStub.handler = { _, _ in self.busy }
        let store = PayForOthersStore(clubId: UUID(), network: stubbedService())
        let friend = UUID()
        let outcome = await store.pay(method: "cash", people: [friend], includeMe: false)
        XCTAssertEqual(outcome, .failed("Hold on, that's still being saved. Try again in a moment."))
        XCTAssertEqual(StatementStub.seen.count, 2, "once, quietly, and no more")

        StatementStub.handler = { _, _ in (200, Data(#"{"payments":[],"total_cents":0}"#.utf8)) }
        _ = await store.pay(method: "cash", people: [friend], includeMe: false)
        let keys = Set(StatementStub.seen.compactMap { $0.0.value(forHTTPHeaderField: "Idempotency-Key") })
        XCTAssertEqual(keys.count, 1, "the person's own retry is still the same payment")
    }

    func testAClaimRetriesBusyWithTheSameKeyAndOtherErrorsAreNotRetried() async throws {
        let screen = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("pay_stepD_pay_screen_friends")) as? [String: Any])
        let claims = try XCTUnwrap(screen["claims"] as? [[String: Any]])
        let one = try JSONSerialization.data(withJSONObject: claims[0])
        var calls = 0
        StatementStub.handler = { _, _ in
            calls += 1
            return calls == 1 ? self.busy : (200, one)
        }
        let key = UUID()
        let made = try await FishersAPI.claimPayment(clubId: UUID(), method: "transfer", key: key, network: stubbedService())
        XCTAssertEqual(made.name, "Ravi Sharma")
        XCTAssertEqual(StatementStub.seen.map { $0.0.value(forHTTPHeaderField: "Idempotency-Key") }, [key.uuidString, key.uuidString])
        XCTAssertTrue(StatementStub.seen.allSatisfy { $0.0.url?.path.hasSuffix("/payments") == true })

        StatementStub.reset()
        StatementStub.handler = { _, _ in self.refusal(409, "nothing_owed", "You're all paid up") }
        do {
            _ = try await FishersAPI.claimPayment(clubId: UUID(), method: "transfer", key: key, network: stubbedService())
            XCTFail("nothing_owed is the caller's to word")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "nothing_owed")
        }
        XCTAssertEqual(StatementStub.seen.count, 1, "only busy is retried")
    }

    func testAGroupFeeIsTheSameRequestUntilTheFormChanges() {
        var draft = GroupFeeDraft()
        draft.title = "Match balls"
        draft.amount = "15"
        let body = draft.body(currency: "GBP")!
        XCTAssertEqual(GroupFeesStore.scope(body), GroupFeesStore.scope(draft.body(currency: "GBP")!))
        draft.amount = "16"
        XCTAssertNotEqual(GroupFeesStore.scope(body), GroupFeesStore.scope(draft.body(currency: "GBP")!))
    }

    // MARK: - The statement: decoding and grouping

    func testThePreviewDecodesIntoItsGroups() throws {
        let preview = try decode(StatementPreview.self, "pay_stepD_statement_preview")
        XCTAssertEqual(preview.currency, "GBP")
        XCTAssertEqual(preview.lines.count, 6)
        XCTAssertEqual(preview.toApply.map(\.who), ["Rohit Sharma", "Josh Turner", "Neha Patel"])
        XCTAssertEqual(preview.toCheck.map(\.who), ["Tom Bennett", "R SHARMA SHARMA"],
                       "nobody's name on a shared surname: the bank's words instead")
        XCTAssertEqual(preview.notRecognised.map(\.text), ["INTEREST"])
        XCTAssertTrue(preview.alreadyDone.isEmpty)

        let rohit = preview.toApply[0]
        XCTAssertEqual(rohit.action, .confirm)
        XCTAssertEqual(rohit.paymentIds, [UUID(uuidString: "85ea6e49-7983-4196-828e-fc0830d72c94")!])
        XCTAssertEqual(rohit.amountCents, 600)
        XCTAssertEqual(rohit.day, DayDate.short("2026-11-22"))
        XCTAssertEqual(rohit.applyWords, "Said they'd paid: this ticks it off")
        XCTAssertEqual(preview.toApply[2].applyWords, "Hadn't said they'd paid: recorded as paid")
        XCTAssertEqual(preview.toCheck.map(\.why), [.differentAmount, .sharedName])

        // Everything ticked to start with; unticking leaves it out, in order.
        let all = Set(preview.toApply.map(\.hash))
        XCTAssertEqual(preview.hashes(ticked: all), preview.toApply.map(\.hash))
        var some = all
        some.remove(preview.toApply[1].hash)
        some.insert(preview.toCheck[0].hash) // never applied, whatever is ticked
        XCTAssertEqual(preview.hashes(ticked: some), [preview.toApply[0].hash, preview.toApply[2].hash])
    }

    func testOneTransferForTwoJuniorsAndAnOlderServer() throws {
        let line = { (ids: String) in
            #"{"hash":"h","row":2,"date":"2026-11-22","amount_cents":1500,"text":"GILL","action":"confirm","user_id":null,"name":"Neha Gill",\#(ids),"why":null}"#
        }
        let two = try decode(StatementLine.self, json: line(#""payment_ids":["\#(UUID())","\#(UUID())"]"#))
        XCTAssertEqual(two.paymentIds.count, 2)
        XCTAssertEqual(two.applyWords, "Said they'd paid, for 2 people: this ticks them off")
        let id = UUID()
        let old = try decode(StatementLine.self, json: line(#""payment_id":"\#(id)""#))
        XCTAssertEqual(old.paymentIds, [id], "payment_id from before the review still reads")
        let unknown = try decode(StatementPreview.self, json: #"""
        {"currency":"GBP","lines":[{"hash":"x","row":3,"date":"2026-11-22","amount_cents":5,"text":"REFUND","action":"refund","why":"odd"}]}
        """#)
        XCTAssertEqual(unknown.notRecognised.count, 1, "an action this build doesn't know is never applied")
        XCTAssertTrue(unknown.toApply.isEmpty)
    }

    func testWhyItNeedsALookInWords() throws {
        let preview = try decode(StatementPreview.self, "pay_stepD_statement_preview")
        let tom = preview.toCheck[0], shared = preview.toCheck[1]
        let members = ["Rohit Sharma", "Ravi Sharma", "Tom Bennett", "Josh Turner"]

        XCTAssertEqual(shared.whyWords(currency: "GBP", memberNames: members, waiting: []),
                       "Two members called SHARMA — the number was left off")
        XCTAssertEqual(shared.whyWords(currency: "GBP", memberNames: members + ["Asha Sharma"], waiting: []),
                       "3 members called SHARMA — the number was left off")
        XCTAssertEqual(shared.whyWords(currency: "GBP", memberNames: [], waiting: []),
                       "Two members share this name — the number was left off")
        XCTAssertNil(StatementLine.sharedSurname(in: "T BENNETT BENNETT", memberNames: members), "one Bennett isn't shared")
        XCTAssertEqual(StatementLine.sharedSurname(in: "gill 2 nets", memberNames: ["Neha Gill", "Jas Gill", "Aman Gill"])?.surname,
                       "GILL")

        // What Tom said he sent: his transfer waiting to be checked.
        let tomId = try XCTUnwrap(tom.userId)
        func said(_ cents: [Int]) throws -> [ClubPayment] {
            try cents.map { amount in
                try decode(ClubPayment.self, json: """
                {"id":"\(UUID())","club_id":"\(UUID())","user_id":"\(tomId)","name":"Tom Bennett",
                 "amount_cents":\(amount),"currency":"GBP","method":"transfer","status":"claimed",
                 "created_by":"\(tomId)","created_at":"2026-11-22T10:00:00Z"}
                """)
            }
        }
        XCTAssertEqual(tom.whyWords(currency: "GBP", memberNames: members, waiting: try said([600])), "Said £6.00, sent £9.00")
        XCTAssertEqual(tom.whyWords(currency: "GBP", memberNames: members, waiting: try said([600, 600])), "Said £6.00, sent £9.00")
        XCTAssertEqual(tom.whyWords(currency: "GBP", memberNames: members, waiting: try said([600, 400])),
                       "Sent £9.00: not what they said they'd paid", "two amounts can't be one sentence")
        XCTAssertEqual(tom.whyWords(currency: "GBP", memberNames: members, waiting: []),
                       "Sent £9.00: not what they said they'd paid")
        // Somebody else's transfer isn't what Tom said.
        let ravis = try decode(MoneyOverview.self, "pay_stepD_money_overview").toCheck
        XCTAssertEqual(tom.whyWords(currency: "GBP", memberNames: members, waiting: ravis),
                       "Sent £9.00: not what they said they'd paid")
    }

    func testWhatApplyingSays() throws {
        let many = try decode(StatementApplied.self, json: #"{"confirmed":5,"recorded":3,"skipped":0}"#)
        XCTAssertEqual(many.headline, "8 payments ticked off.")
        XCTAssertNil(many.skippedWords)
        let one = try decode(StatementApplied.self, json: #"{"confirmed":0,"recorded":1,"skipped":2}"#)
        XCTAssertEqual(one.headline, "1 payment ticked off.")
        XCTAssertEqual(one.skippedWords, "2 had changed since, so they were left alone.")
        let skippedOne = try decode(StatementApplied.self, json: #"{"confirmed":2,"recorded":0,"skipped":1}"#)
        XCTAssertEqual(skippedOne.skippedWords, "1 had changed since, so it was left alone.")
    }

    func testTheFileReadsHoweverTheBankWroteIt() throws {
        let csv = "Date,Description,Paid in\n22/11/2026,R SHARMA SHARMA £6,6.00\n"
        XCTAssertEqual(StatementFile.text(from: Data(csv.utf8)), csv)
        XCTAssertEqual(StatementFile.text(from: try XCTUnwrap(csv.data(using: .windowsCP1252))), csv, "an older export's £")
        XCTAssertEqual(StatementFile.text(from: try XCTUnwrap(csv.data(using: .utf16))), csv)
        XCTAssertEqual(StatementFile.text(from: Data()), "", "empty is the server's to say")
    }

    // MARK: - The import, end to end against the stub

    @MainActor
    func testPreviewThenApplyWhatIsStillTicked() async throws {
        let preview = try fixture("pay_stepD_statement_preview")
        let members = try fixture("pay_stepD_money_members")
        StatementStub.handler = { request, _ in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/payments/members") { return (200, members) }
            if path.hasSuffix("/statement/preview") { return (200, preview) }
            if path.hasSuffix("/statement/apply") { return (200, Data(#"{"confirmed":1,"recorded":1,"skipped":0}"#.utf8)) }
            return (404, Data())
        }
        let csv = "Date,Description,Paid in\n22/11/2026,R SHARMA SHARMA 2,6.00\n"
        let store = StatementImportStore(clubId: UUID(), network: stubbedService())
        await store.loadPreview(csv)

        XCTAssertNil(store.problem)
        let lines = try XCTUnwrap(store.preview).toApply
        XCTAssertEqual(store.tickedCount, 3, "Ticked off: everything the server matched")
        XCTAssertTrue(store.memberNames.contains("Neha Gill"))
        let sent = try XCTUnwrap(StatementStub.seen.first { $0.0.url?.path.hasSuffix("/statement/preview") == true })
        XCTAssertEqual(sent.1.flatMap { String(data: $0, encoding: .utf8) }, csv, "the file itself is the body")
        XCTAssertEqual(sent.0.value(forHTTPHeaderField: "Content-Type"), "text/csv")

        store.toggle(lines[1], false)
        XCTAssertEqual(store.tickedCount, 2)
        await store.apply()

        let apply = try XCTUnwrap(StatementStub.seen.first { $0.0.url?.path.hasSuffix("/statement/apply") == true })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: apply.1 ?? Data()) as? [String: Any])
        XCTAssertEqual(body["csv"] as? String, csv, "the server reads the statement again")
        XCTAssertEqual(body["lines"] as? [String], [lines[0].hash, lines[2].hash])
        XCTAssertEqual(store.applied?.headline, "2 payments ticked off.")
        XCTAssertNil(store.preview, "nothing of the statement is held once it's applied")
        XCTAssertEqual(store.tickedCount, 0)
    }

    @MainActor
    func testAStatementTheServerCantReadSaysWhy() async {
        StatementStub.handler = { request, _ in
            request.url?.path.hasSuffix("/statement/preview") == true
                ? self.refusal(422, "unknown_statement",
                               "Couldn't find the date and amount column. Export the statement as CSV from your bank and try again.")
                : (403, Data())
        }
        let store = StatementImportStore(clubId: UUID(), network: stubbedService())
        await store.loadPreview("foo,bar\n1,2\n")
        XCTAssertNil(store.preview)
        XCTAssertEqual(store.problem,
                       "That doesn't look like a bank statement. Download it from your bank as a CSV file, then try again.",
                       "the app's own words, so they read in Punjabi too")

        StatementStub.handler = { _, _ in self.refusal(422, "empty_statement", "That file is empty.") }
        await store.loadPreview("")
        XCTAssertEqual(store.problem, "That file is empty. Download the statement from your bank again.")

        StatementStub.handler = { _, _ in self.refusal(422, "statement_too_long", "That statement is too long") }
        await store.loadPreview("x")
        XCTAssertEqual(store.problem, "That statement is too long. Download a shorter one: a month or two.")

        StatementStub.handler = { _, _ in self.refusal(403, "not_money_admin", "Only the club owner, a secretary or a treasurer can look after the club's money") }
        await store.loadPreview("x")
        XCTAssertEqual(store.problem, "Only the club owner, a secretary or a treasurer can look after the club's money",
                       "anything else is the server's sentence")
        store.startAgain()
        XCTAssertNil(store.problem)
    }

    // MARK: - I'm paying for friends too

    func testFriendsComeFromThePayScreenWithWhatTheyOwe() throws {
        let screen = try decode(PayScreen.self, "pay_stepD_pay_screen_friends")
        XCTAssertEqual(screen.friends.count, 7)
        let jas = try XCTUnwrap(screen.friends.first { $0.name == "Jas Gill" })
        XCTAssertEqual(jas.owedCents, 863)
        let arjun = try XCTUnwrap(screen.friends.first { $0.name == "Arjun Gill" })

        let payment = FriendsPayment(mineCents: screen.owedCents, friends: [jas, arjun], currency: screen.currency)
        XCTAssertTrue(payment.includeMe)
        XCTAssertEqual(payment.totalCents, screen.owedCents + 863 + 563)
        XCTAssertEqual(payment.whoWords, "you, Jas and Arjun")
        XCTAssertEqual(payment.sentence, "One payment of £39.88 for you, Jas and Arjun, with one reference.")

        let justThem = FriendsPayment(mineCents: 0, friends: [jas], currency: "GBP")
        XCTAssertFalse(justThem.includeMe)
        XCTAssertEqual(justThem.whoWords, "Jas")

        // An older server sends no friends: the button isn't offered.
        let old = try decode(PayScreen.self, "pay_stepA_pay_screen")
        XCTAssertTrue(old.friends.isEmpty)
    }

    func testAPaymentMadeForSomebodyElseSaysSo() throws {
        let ravi = "1053c505-eac3-4b82-a124-e0124e0550b9"
        let neha = "1f3fbd34-b865-4fd2-a4ac-64383a5148d6"
        let screen = try decode(PayScreen.self, "pay_stepD_pay_screen_friends", replacing: [
            (#""created_by": "\#(ravi)",\#n            "created_at": "2026-11-21T12:40:20.851497Z""#,
             #""created_by": "\#(neha)",\#n            "created_at": "2026-11-21T12:40:20.851497Z""#),
        ])
        let made = try XCTUnwrap(screen.claims.first)
        XCTAssertEqual(made.createdBy?.uuidString.lowercased(), neha)
        XCTAssertEqual(made.payerId?.uuidString.lowercased(), neha, "a statement line names whoever paid")
        XCTAssertEqual(screen.claims[1].payerId?.uuidString.lowercased(), ravi)
    }

    // MARK: - Bank details for whoever has something to pay

    func testOnlyNoneFrozenOrUnreadableLeaveTheDetailsOut() throws {
        let screen = try decode(PayScreen.self, "pay_stepD_pay_screen_friends")
        XCTAssertNotNil(screen.payableAccount)
        XCTAssertNil(screen.noDetailsReason)
        for (state, words) in [
            ("none", "Your club hasn't added bank details yet. Pay your secretary directly."),
            ("frozen", "The club's bank details are being checked. Don't pay yet."),
            ("unreadable", "Ask your secretary to enter the bank details again."),
        ] {
            let other = try decode(PayScreen.self, "pay_stepD_pay_screen_friends",
                                   replacing: [(#""account_state": "active""#, #""account_state": "\#(state)""#)])
            XCTAssertNil(other.payableAccount)
            XCTAssertEqual(other.noDetailsReason, words, state)
        }
        let nothing = try decode(PayScreen.self, "pay_stepD_pay_screen_friends",
                                 replacing: [(#""account_state": "active""#, #""account_state": "nothing_owed""#)])
        XCTAssertNil(nothing.noDetailsReason, "nothing to pay is nothing to ask the secretary for")
    }

    // MARK: - Covered lines, worded from `cover`

    func testCoveredLinesAreWordedFromCoverNotTheReason() throws {
        let coach = try decode(EventBillPage.self, "pay_stepBC_bill_priced", replacing: [
            (#""reason": "Free: Coach""#, #""reason": "Gratis: Trainer""#),
        ]).shares.first { $0.name == "Tom Bennett" }
        XCTAssertEqual(coach?.cover, "free")
        XCTAssertEqual(coach?.coveredWords(), "Free ✓", "the English reason isn't read")
        XCTAssertEqual(coach?.coveredByWords, "Free")

        let ravi = try decode(EventBillPage.self, "pay_stepBC_bill_with_pass_cover").shares.first { $0.name == "Ravi Sharma" }
        XCTAssertEqual(ravi?.cover, "pass")
        XCTAssertEqual(ravi?.coveredWords(), "Covered by your pass ✓")
        XCTAssertEqual(ravi?.coveredWords(forSomeoneElse: true), "Covered by their pass ✓")
        XCTAssertEqual(ravi?.coveredByWords, "Covered by a pass")

        // A free line whose reason happens to start "Free" but whose cover
        // says pass reads as a pass.
        let odd = try decode(EventBillPage.self, "pay_stepBC_bill_with_pass_cover", replacing: [
            (#""reason": "Covered by Monthly nets""#, #""reason": "Free nets""#),
        ]).shares.first { $0.name == "Ravi Sharma" }
        XCTAssertEqual(odd?.coveredWords(), "Covered by your pass ✓")
    }

    // MARK: - Passes, prices and who pays

    func testMyPassCarriesItsTermsAndTheStandingOrderPaysWhatsOwed() throws {
        let pass = try XCTUnwrap(try decode([PassHolder].self, "pay_stepD_me_passes").first)
        XCTAssertEqual(pass.covers, [.nets, .training])
        XCTAssertNil(pass.validUntil)
        XCTAssertNil(pass.sessions)
        XCTAssertEqual(pass.coverWords, "Covers nets and training.")
        XCTAssertEqual(pass.standingOrder?.reference, "SHARMA")

        let screen = try decode(PayScreen.self, "pay_stepD_pay_screen_friends")
        XCTAssertTrue(pass.hasChargeOwed(in: screen.shares), "Monthly nets — November 2026 is still owed")
        XCTAssertFalse(pass.hasChargeOwed(in: screen.shares.filter { $0.kind != "pass" }))
        let paid = try decode(PayScreen.self, "pay_stepD_pay_screen_friends", replacing: [
            (#""title": "Monthly nets \u2014 November 2026""#, #""title": "Winter nets pass""#),
        ])
        XCTAssertFalse(pass.hasChargeOwed(in: paid.shares), "another pass's charge isn't this one's")

        // A card from an older server says nothing of its terms.
        let older = try XCTUnwrap(try decode([PassHolder].self, "pay_stepBC_me_passes").first)
        XCTAssertNil(older.coverWords)
    }

    /// The month the standing order pays reads as that on the pay screen, not
    /// "Owed": the total above it leaves it out.
    func testTheStandingOrdersMonthIsSaidApartFromWhatsOwed() throws {
        let pass = try XCTUnwrap(try decode([PassHolder].self, "pay_stepD_me_passes").first)
        let screen = try decode(PayScreen.self, "pay_stepD_pay_screen_friends")
        let november = try XCTUnwrap(screen.shares.first { $0.kind == "pass" })
        let before = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-22T12:00:00Z"))
        let after = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-12-01T12:00:00Z"))
        XCTAssertTrue(pass.standingOrderPays(november, today: before))
        XCTAssertFalse(pass.standingOrderPays(november, today: after), "past its due day it's caught up by hand")
        XCTAssertFalse(screen.shares.filter { $0.kind != "pass" }.contains { pass.standingOrderPays($0, today: before) },
                       "a session or a group fee is still owed")

        // Something already paid towards it isn't the standing order's to pay.
        let started = try decode(PayScreen.self, "pay_stepD_pay_screen_friends", replacing: [
            (#""paid_cents": 0,\#n            "waiting_cents": 0,\#n            "currency": "GBP",\#n            "state": "owed""#,
             #""paid_cents": 0,\#n            "waiting_cents": 562,\#n            "currency": "GBP",\#n            "state": "part_paid""#),
        ])
        let part = try XCTUnwrap(started.shares.first { $0.kind == "pass" })
        XCTAssertEqual(part.state, .partPaid)
        XCTAssertFalse(pass.standingOrderPays(part, today: before))
    }

    func testWhoPaysForWhomIsTheServers() throws {
        let members = try decode([MoneyMember].self, "pay_stepD_money_members")
        XCTAssertEqual(members.count, 8)
        let jas = try XCTUnwrap(members.first { $0.name == "Jas Gill" })
        XCTAssertEqual(jas.payerName, "Neha Gill")
        XCTAssertEqual(jas.payerId?.uuidString.lowercased(), "1f3fbd34-b865-4fd2-a4ac-64383a5148d6")
        XCTAssertNotNil(jas.priceTypeId)
        XCTAssertFalse(jas.managed)
        let arjun = try XCTUnwrap(members.first { $0.name == "Arjun Gill" })
        XCTAssertTrue(arjun.managed)
        XCTAssertNil(members.first { $0.name == "Ravi Sharma" }?.payerId)
    }

    func testAGroupFeeOnTheOverviewOpensTheGroupFee() throws {
        let overview = try decode(MoneyOverview.self, "pay_stepD_money_overview")
        let balls = try XCTUnwrap(overview.bills.first { $0.title == "Match balls" })
        XCTAssertEqual(balls.kind, "collection")
        XCTAssertTrue(balls.isGroupFee)
        XCTAssertNil(balls.eventId)
        let pass = try XCTUnwrap(overview.bills.first { $0.kind == "pass" })
        XCTAssertFalse(pass.isGroupFee)
        XCTAssertNil(pass.eventId, "a pass charge opens nothing")
        XCTAssertTrue(overview.bills.filter { $0.kind == "event" }.allSatisfy { $0.eventId != nil })
    }

    func testAGroupFeeLinkMayNotBeOpen() throws {
        XCTAssertNil(try decode(BillLink?.self, json: "null"))
        XCTAssertEqual(try decode(BillLink?.self, "pay_stepBC_collection_link")?.stillToPay.count, 3)
    }

    // MARK: - Words

    func testTheNewWordsReadInPunjabi() {
        Strings.setCurrent(.pa)
        for english in [
            "Import a bank statement", "Choose the CSV file", "Ticked off: {n}", "Needs a look: {n}",
            "Not recognised: {n}", "Already done: {n}", "Apply {n}", "{n} payments ticked off.",
            "That file couldn't be opened. Try choosing it again.", "Each person is told their payment arrived.",
            "Your standing order pays this month too. Don't pay it by hand.",
            "Two members called {name} — the number was left off", "Said {said}, sent {sent}",
            "Undone. {name} still owes it.", "No sign-in of their own", "Covered by a pass",
        ] {
            XCTAssertNotEqual(tr(english), english, english)
        }
    }

    /// The words a player must never meet, in what a player reads here.
    func testAPlayerNeverReadsTheSystemsWords() throws {
        let screen = try decode(PayScreen.self, "pay_stepD_pay_screen_friends")
        let payment = FriendsPayment(mineCents: screen.owedCents, friends: screen.friends, currency: screen.currency)
        let said = [
            payment.sentence,
            tr("Your standing order pays this month too. Don't pay it by hand."),
            tr("Undone. {name} still owes it.", vars: ["name": "Jas"]),
            tr("Tick who you're paying for. What each of them owes is added to your total: send it all in one transfer, with your reference."),
        ] + (try decode([PassHolder].self, "pay_stepD_me_passes")).compactMap(\.coverWords)
        for line in said {
            for banned in ["subscription", "collection", "holder", "dependent", "price type", "claim", "waived", "payout"] {
                XCTAssertFalse(line.lowercased().contains(banned), "\(banned) in: \(line)")
            }
        }
    }
}

/// Answers from a closure and keeps what was sent, body included — which
/// URLSession hands a protocol as a stream rather than `httpBody`.
private final class StatementStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest, Data?) -> (Int, Data))?
    nonisolated(unsafe) static var seen: [(URLRequest, Data?)] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handler = nil
        seen = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        Self.lock.lock()
        let handler = Self.handler
        Self.seen.append((request, body))
        let answer = handler?(request, body)
        Self.lock.unlock()
        guard let (status, data) = answer else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
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
