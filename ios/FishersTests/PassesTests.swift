import XCTest
@testable import Fishers

/// Steps B and C of club payments: passes, prices for juniors and others,
/// group fees, and paying for other people. The fixtures are real responses
/// from the local API (`.dev/payments/examples/stepBC_*.json`); the network
/// ones answer from a stub.
final class PassesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Strings.setCurrent(.en)
        PassesStub.reset()
    }

    override func tearDown() {
        Strings.setCurrent(.en)
        PassesStub.reset()
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

    private func decode<T: Decodable>(_ type: T.Type, _ name: String, replacing old: String, with new: String) throws -> T {
        let text = try XCTUnwrap(String(data: fixture(name), encoding: .utf8))
        XCTAssertTrue(text.contains(old), "\(old) is not in \(name)")
        return try FishersJSONDecoder.make().decode(T.self, from: Data(text.replacingOccurrences(of: old, with: new).utf8))
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

    private func object(_ value: some Encodable) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    /// The day the fixtures were made after, so "in the future" holds still.
    private let today = DayDate.date("2026-11-22")!

    // MARK: - Prices for juniors and others

    func testTheGroupsDecode() throws {
        let groups = try decode([PriceType].self, "pay_stepBC_price_types")
        XCTAssertEqual(groups.map(\.name), ["Junior", "Coach", "Guest", "junior"])
        XCTAssertEqual(groups[1].tags, ["Free"])
        XCTAssertEqual(groups[2].tags, ["For guests"])
        XCTAssertEqual(groups.junior?.name, "Junior", "the first named for juniors, in the club's order")
        XCTAssertNil([PriceType]().junior)
    }

    func testASessionsOwnPricesAndAFreeCoach() throws {
        let page = try decode(EventBillPage.self, "pay_stepBC_bill_priced")
        XCTAssertEqual(page.prices.map(\.name), ["Junior", "Guest"])
        XCTAssertEqual(page.prices.map { $0.describe("GBP") }, ["Junior £3.00", "Guest £8.00"])
        XCTAssertEqual(TypePrice(priceTypeId: UUID(), name: "Coach", amountCents: 0).describe("GBP"), "Coach free")
        let tom = try XCTUnwrap(page.shares.first { $0.name == "Tom Bennett" })
        XCTAssertEqual(tom.state, .covered)
        XCTAssertEqual(tom.reason, "Free: Coach")
        XCTAssertEqual(tom.coveredWords(), "Free ✓", "a free price isn't a pass")
        XCTAssertEqual(tom.state.shortLabel, "Covered")
        XCTAssertFalse(tom.state.stillOwed)
        XCTAssertEqual(page.shares.first { $0.name == "Jas Gill" }?.amountCents, 300, "a junior at the junior price")
    }

    func testAPassCoversASession() throws {
        let page = try decode(EventBillPage.self, "pay_stepBC_bill_with_pass_cover")
        XCTAssertTrue(page.prices.isEmpty)
        let ravi = try XCTUnwrap(page.shares.first { $0.name == "Ravi Sharma" })
        XCTAssertEqual(ravi.state, .covered)
        XCTAssertEqual(ravi.reason, "Covered by Monthly nets")
        XCTAssertEqual(ravi.coveredWords(), "Covered by your pass ✓")
        XCTAssertEqual(ravi.coveredWords(forSomeoneElse: true), "Covered by their pass ✓")
        XCTAssertTrue(ravi.isSessionLine)
        XCTAssertEqual(ravi.kind, "event")
    }

    func testThePreviewSaysWhoIsCovered() throws {
        let preview = try decode(BillPreview.self, "pay_stepBC_bill_preview_priced")
        XCTAssertEqual(preview.coveredLines.map(\.name), ["Tom Bennett"])
        XCTAssertEqual(preview.coveredLines.first?.covered, "Free: Coach")
        XCTAssertEqual(
            preview.summary,
            "4 people · £17.00 in all · 1 pays £8.00 · 1 pays £6.00 · 1 pays £3.00 · 1 covered",
            "nobody covered is counted as paying"
        )
    }

    func testDifferentPricesForJuniorsOnTheCostForm() throws {
        let groups = try decode([PriceType].self, "pay_stepBC_price_types").inUse.filter { !$0.free }
        let junior = groups[0]
        let existing = [TypePrice(priceTypeId: junior.id, name: "Junior", amountCents: 300)]

        var fresh = SessionPricesDraft(existing: [], currency: "GBP")
        XCTAssertFalse(fresh.on)
        XCTAssertNil(fresh.body(mode: .perPlayer, groups: groups, existing: [], currency: "GBP").prices,
                     "never asked: the session's prices are left alone")
        fresh.on = true
        fresh.typed[junior.id] = "3"
        XCTAssertEqual(fresh.body(mode: .perPlayer, groups: groups, existing: [], currency: "GBP").prices,
                       [TypePriceBody(priceTypeId: junior.id, amountCents: 300)], "an empty one is the usual price")
        fresh.typed[junior.id] = "0"
        XCTAssertEqual(fresh.body(mode: .perPlayer, groups: groups, existing: [], currency: "GBP").prices?.first?.amountCents, 0,
                       "0 makes it free for them")
        fresh.typed[junior.id] = "three"
        XCTAssertEqual(fresh.body(mode: .perPlayer, groups: groups, existing: [], currency: "GBP").problem, "Check the price for Junior.")

        var had = SessionPricesDraft(existing: existing, currency: "GBP")
        XCTAssertTrue(had.on)
        XCTAssertEqual(had.typed[junior.id], "3.00")
        had.on = false
        XCTAssertEqual(had.body(mode: .perPlayer, groups: groups, existing: existing, currency: "GBP").prices, [],
                       "switched off: cleared")
        XCTAssertNil(had.body(mode: .splitTotal, groups: groups, existing: existing, currency: "GBP").prices,
                     "a total is split evenly; the server drops them")
        XCTAssertNil(had.body(mode: .perPlayer, groups: [], existing: existing, currency: "GBP").prices,
                     "groups not loaded: nothing changes")
    }

    // MARK: - Passes, for a player

    func testOffersReadInPlainWords() throws {
        let plans = try decode([PassPlan].self, "pay_stepBC_passes_member")
        let groups = try decode([PriceType].self, "pay_stepBC_price_types")
        XCTAssertEqual(plans.count, 4)

        let monthly = plans[0]
        XCTAssertEqual(monthly.billing, .monthly)
        XCTAssertEqual(monthly.priceWords, "£20.00 a month")
        XCTAssertEqual(monthly.coverWords, "Covers nets and training.")
        XCTAssertNotNil(monthly.mine, "Ravi is on it")
        XCTAssertEqual(monthly.joinQuestion, "Get Monthly nets?")
        XCTAssertEqual(monthly.joinExplanation,
                       "£20.00 a month. You set up a standing order in your banking app, and it pays itself.")
        XCTAssertEqual(monthly.joinedNotice, "You're on Monthly nets. Set up the standing order below, and it pays itself.")

        let card = plans[1]
        XCTAssertEqual(card.priceWords, "£25.00")
        XCTAssertEqual(card.coverWords, "Covers 2 sessions of nets.")
        XCTAssertEqual(card.joinExplanation, "Pay £25.00 once, and you're covered.")

        let season = plans[2]
        XCTAssertEqual(season.priceWords, "£100.00, in 3 monthly parts of £33.34")
        XCTAssertEqual(season.coverWords, "Covers league matches.")
        XCTAssertEqual(season.joinExplanation, "£33.34 now, then each month until it's paid.")
        XCTAssertFalse(season.openToJoin)

        let junior = plans[3]
        XCTAssertEqual(junior.onlyFor(groups), "Only for Junior members.")
        XCTAssertNil(monthly.onlyFor(groups))
    }

    func testAMembershipAndAPassToADate() throws {
        let membership = try decode(PassPlan.self, "pay_stepBC_pass_created_instalments", replacing: #""league_match""#, with: "")
        XCTAssertEqual(membership.coverWords, "A membership. Sessions are paid as usual.")
        let winter = try decode(PassPlan.self, "pay_stepBC_pass_created_instalments",
                                replacing: #""valid_until": null"#, with: #""valid_until": "2027-03-31""#)
        XCTAssertEqual(winter.coverWords, "Covers league matches until \(DayDate.short("2027-03-31")!).")
        XCTAssertEqual(winter.chargeCents, 3334)
        XCTAssertEqual(winter.holders, 0)
        XCTAssertNil(winter.mine)
    }

    func testAPlayersPassStandsInWords() throws {
        let mine = try XCTUnwrap(try decode([PassHolder].self, "pay_stepBC_me_passes").first)
        XCTAssertEqual(mine.clubName?.hasPrefix("Step BC"), true)
        XCTAssertEqual(mine.standing, .upToDate)
        XCTAssertTrue(mine.running)
        XCTAssertTrue(mine.isInGoodStanding)
        XCTAssertEqual(mine.standingWords(today: today), "Covered. Next payment \(DayDate.short("2026-12-21")!).")
        // The pass's own end comes with it from /me/passes now.
        let toMarch = try decode([PassHolder].self, "pay_stepD_me_passes",
                                 replacing: #""valid_until": null"#, with: #""valid_until": "2027-03-31""#)[0]
        XCTAssertEqual(toMarch.standingWords(today: today), "Covered until \(DayDate.short("2027-03-31")!).")
        XCTAssertEqual(mine.adminStanding, "Up to date")

        let paused = try XCTUnwrap(try decode([PassHolder].self, "pay_stepBC_me_passes_suspended").first)
        XCTAssertEqual(paused.standing, .suspended)
        XCTAssertFalse(paused.isInGoodStanding)
        XCTAssertEqual(paused.standingWords(today: today),
                       "Payments are missing, so it isn't covering sessions. Pay what you owe to start again.")
        XCTAssertEqual(paused.adminStanding, "Payments missing: not covering")

        let late = try decode([PassHolder].self, "pay_stepBC_me_passes",
                              replacing: #""standing": "up_to_date""#, with: #""standing": "behind""#)[0]
        XCTAssertEqual(late.standingWords(today: today), "A payment is late: pay it to stay covered.")
        XCTAssertEqual(late.adminStanding, "A payment is late")

        let kept = try decode([PassHolder].self, "pay_stepBC_me_passes_suspended",
                              replacing: #""keep_covering": false"#, with: #""keep_covering": true"#)[0]
        XCTAssertEqual(kept.adminStanding, "Payments missing, still covered")
    }

    func testACardCountsDown() throws {
        func card(_ left: Int) throws -> PassHolder {
            try decode([PassHolder].self, "pay_stepBC_me_passes",
                       replacing: #""sessions_left": null"#, with: #""sessions_left": \#(left)"#)[0]
        }
        XCTAssertEqual(try card(9).standingWords(today: today), "9 sessions left")
        XCTAssertEqual(try card(1).standingWords(today: today), "1 session left")
        XCTAssertEqual(try card(0).standingWords(today: today), "All its sessions are used. Your next sessions are paid as usual.")
        XCTAssertEqual(try card(1).adminStanding, "Up to date · 1 session left")
    }

    func testCancellingSaysWhatHappensAndAboutTheBank() throws {
        let monthly = try XCTUnwrap(try decode([PassHolder].self, "pay_stepBC_me_passes").first)
        XCTAssertEqual(monthly.cancelQuestion(forSomeoneElse: false), "Cancel Monthly nets?")
        XCTAssertEqual(monthly.cancelQuestion(forSomeoneElse: true), "Cancel Monthly nets for Ravi Sharma?")
        XCTAssertTrue(monthly.cancelWarning.contains("Cancel the standing order in your banking app too"),
                      "the bank keeps paying otherwise")

        let once = try decode([PassHolder].self, "pay_stepBC_me_passes",
                              replacing: #""billing": "monthly""#, with: #""billing": "once""#)[0]
        XCTAssertEqual(once.cancelWarning, "It stops covering today. Anything already charged stays as it is.")
        XCTAssertEqual(once.cancelledNotice, "Cancelled.")

        let cancelled = try decode([PassHolder].self, "pay_stepBC_me_passes", replacing: [
            (#""ends_on": null"#, #""ends_on": "2026-12-20""#),
            (#""cancelled_at": null"#, #""cancelled_at": "2026-11-22T10:00:00Z""#),
        ])[0]
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertFalse(cancelled.isInGoodStanding)
        let end = DayDate.short("2026-12-20")!
        XCTAssertEqual(cancelled.standingWords(today: today), "Cancelled. It covers you until \(end).")
        XCTAssertEqual(cancelled.cancelledNotice,
                       "Cancelled. It covers until \(end). Now cancel the standing order in your banking app too.")
        XCTAssertEqual(cancelled.standingWords(today: DayDate.date("2027-01-05")!), "Cancelled.")
    }

    func testTheStandingOrderToType() throws {
        let mine = try XCTUnwrap(try decode([PassHolder].self, "pay_stepBC_me_passes").first)
        let order = try XCTUnwrap(mine.standingOrder)
        XCTAssertEqual(order.amountCents, 2000)
        XCTAssertEqual(order.howOften, "Every month")
        XCTAssertEqual(order.firstPaymentOn, "2026-11-21")
        XCTAssertEqual(order.reference, "SHARMA")

        let bare = order.detailsToSend(club: "Riverside", currency: "GBP", account: nil)
        XCTAssertTrue(bare.hasPrefix("Please set up a standing order to Riverside for me:"))
        XCTAssertTrue(bare.contains("Amount: £20.00"))
        XCTAssertTrue(bare.contains("How often: Every month"))
        XCTAssertTrue(bare.contains("What to write in the reference box: SHARMA"))
        XCTAssertFalse(bare.contains("Account number"), "no details to send when the pay screen has none")

        let account = try XCTUnwrap(try decode(PayScreen.self, "pay_stepA_pay_screen").payableAccount)
        let full = order.detailsToSend(club: "Riverside", currency: "GBP", account: account)
        XCTAssertTrue(full.contains("Who to pay: \(account.holderName)"))
        XCTAssertTrue(full.contains("Sort code: \(account.sortCode)"))
        XCTAssertTrue(full.contains("Account number: \(account.accountNumber)"))

        // Only a monthly pass has one; a cancelled one has none.
        let holders = try decode([PassHolder].self, "pay_stepBC_pass_holders")
        XCTAssertNil(holders[0].standingOrder)
        XCTAssertNil(holders[0].clubName)
    }

    func testUnknownValuesNeverStopADecode() throws {
        let plan = try decode(PassPlan.self, json: """
            {"id":"\(UUID().uuidString)","club_id":"\(UUID().uuidString)","name":"Indoor winter","price_cents":5000,
             "currency":"GBP","billing":"weekly","covers":["indoor","nets"],"open_to_join":true,"charge_cents":5000,
             "holders":2,"mine":{"id":"not-a-uuid"}}
            """)
        XCTAssertEqual(plan.billing, .unknown("weekly"))
        XCTAssertEqual(plan.covers, [.unknown("indoor"), .nets])
        XCTAssertEqual(plan.coverWords, "Covers indoor and nets.")
        XCTAssertEqual(plan.priceWords, "£50.00")
        XCTAssertNil(plan.mine, "a holder this build can't read is dropped, not the pass")

        let holder = try decode([PassHolder].self, "pay_stepBC_pass_holders",
                                replacing: #""standing": "up_to_date""#, with: #""standing": "frozen""#)[0]
        XCTAssertEqual(holder.standing, .unknown("frozen"))
        XCTAssertEqual(holder.adminStanding, "Frozen")
        XCTAssertEqual(PassStanding(raw: "suspended").raw, "suspended")
        XCTAssertEqual(SessionKind(raw: "league_match").raw, "league_match")
    }

    // MARK: - Passes, for a money admin

    func testTemplatesMakeTheRightPass() throws {
        let groups = try decode([PriceType].self, "pay_stepBC_price_types")

        let monthly = try XCTUnwrap(PassTemplate.monthlyNets.draft(currency: "GBP", groups: groups, today: today).body(currency: "GBP"))
        XCTAssertEqual(monthly.billing, "monthly")
        XCTAssertEqual(monthly.priceCents, 2000)
        XCTAssertEqual(monthly.covers, ["nets"])
        let sent = try object(monthly)
        XCTAssertNil(sent["valid_until"], "a monthly pass runs until it's cancelled")
        XCTAssertNil(sent["sessions"])
        XCTAssertNil(sent["instalments"])
        XCTAssertEqual(sent["open_to_join"] as? Bool, true)

        let winter = try XCTUnwrap(PassTemplate.winterNets.draft(currency: "GBP", groups: groups, today: today).body(currency: "GBP"))
        XCTAssertEqual(winter.validUntil, "2027-03-31", "the next 31 March")
        XCTAssertEqual(winter.billing, "once")
        XCTAssertEqual(DayDate.string(PassTemplate.endOfMarch(after: DayDate.date("2027-02-01")!)), "2027-03-31")

        let card = try XCTUnwrap(PassTemplate.tenSessions.draft(currency: "GBP", groups: groups, today: today).body(currency: "GBP"))
        XCTAssertEqual(card.sessions, 10)
        XCTAssertNil(card.validUntil)

        let season = try XCTUnwrap(PassTemplate.seasonMembership.draft(currency: "GBP", groups: groups, today: today).body(currency: "GBP"))
        XCTAssertEqual(season.billing, "instalments")
        XCTAssertEqual(season.instalments, 3)
        XCTAssertEqual(season.priceCents, 12000)
        XCTAssertEqual(season.covers, [])
        XCTAssertFalse(season.openToJoin, "the secretary adds members")

        let junior = try XCTUnwrap(PassTemplate.juniorMembership.draft(currency: "GBP", groups: groups, today: today).body(currency: "GBP"))
        XCTAssertEqual(junior.priceTypeId, groups.junior?.id)
        XCTAssertEqual(junior.priceCents, 5000)

        // A monthly pass never sends an end, whatever was picked before.
        var draft = PassTemplate.winterNets.draft(currency: "GBP", groups: groups, today: today)
        draft.billing = .monthly
        XCTAssertNil(draft.body(currency: "GBP")?.validUntil)

        var empty = PassDraft()
        XCTAssertEqual(empty.problem(currency: "GBP"), "Give the pass a name, like Winter nets pass.")
        empty.name = "Nets"
        XCTAssertEqual(empty.problem(currency: "GBP"), "Put in what the pass costs.")
        XCTAssertNil(empty.body(currency: "GBP"))
    }

    // MARK: - Group fees

    func testAGroupFeeDecodes() throws {
        let fee = try decode(GroupFee.self, "pay_stepBC_collection_created")
        XCTAssertEqual(fee.title, "Match balls")
        XCTAssertEqual(fee.mode, .splitTotal)
        XCTAssertEqual(fee.people, 3)
        XCTAssertEqual(fee.owedCents, 4500)
        XCTAssertFalse(fee.isCancelled)
        let due = DayDate.short("2026-12-06")!
        XCTAssertEqual(fee.titleWithDue, "Match balls, by \(due)")
        XCTAssertEqual(fee.summary, "3 people · £45.00 still owed")
        XCTAssertEqual(fee.shares.count, 3)
        for share in fee.shares {
            XCTAssertNil(share.eventId, "a group fee has no session")
            XCTAssertEqual(share.kind, "collection")
            XCTAssertFalse(share.isSessionLine)
            XCTAssertEqual(share.whenWords, "by \(due)")
        }

        let list = try decode([GroupFee].self, "pay_stepBC_collections_list")
        XCTAssertEqual(list.map(\.title), ["Junior kit", "Match balls"])
        XCTAssertTrue(list.allSatisfy { $0.shares.isEmpty }, "the list has totals only")
        XCTAssertEqual(list[0].titleWithDue, "Junior kit", "no date, no 'by'")
        XCTAssertEqual(list[0].summary, "1 person · £15.00 still owed")

        let mine = try decode(GroupFee.self, "pay_stepBC_collection_member_view")
        XCTAssertEqual(mine.shares.map(\.name), ["Sam Student"], "a member sees only their own line")

        let cancelled = try decode(GroupFee.self, "pay_stepBC_collection_created",
                                   replacing: #""status": "issued""#, with: #""status": "void""#)
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertEqual(cancelled.summary, "Cancelled")

        let link = try decode(BillLink.self, "pay_stepBC_collection_link")
        XCTAssertTrue(link.billMessage.hasPrefix("💷 Match balls"))
        XCTAssertEqual(link.stillToPay.count, 3)
    }

    func testANewGroupFeeSaysWhoAndHowMuch() throws {
        var draft = GroupFeeDraft()
        XCTAssertEqual(draft.problem(currency: "GBP"), "Say what it's for, like League registration.")
        draft.title = "  League   registration "
        XCTAssertEqual(draft.problem(currency: "GBP"), "Put in how much.")
        draft.amount = "300"
        draft.mode = .splitTotal
        draft.hasDueDate = true
        draft.dueOn = DayDate.date("2026-12-06")!

        let everyone = try XCTUnwrap(draft.body(currency: "GBP"))
        XCTAssertEqual(everyone.title, "League registration")
        let sent = try object(everyone)
        XCTAssertEqual(sent["everyone"] as? Bool, true)
        XCTAssertEqual(sent["mode"] as? String, "split_total")
        XCTAssertEqual(sent["amount_cents"] as? Int, 30000)
        XCTAssertEqual(sent["due_on"] as? String, "2026-12-06")
        XCTAssertNil(sent["team_id"])
        XCTAssertNil(sent["user_ids"])
        XCTAssertNil(sent["note"])

        let team = UUID()
        draft.who = .team(team)
        let forTeam = try object(XCTUnwrap(draft.body(currency: "GBP")))
        XCTAssertEqual(forTeam["team_id"] as? String, team.uuidString)
        XCTAssertNil(forTeam["everyone"], "only one way of saying who")

        draft.who = .people
        XCTAssertEqual(draft.problem(currency: "GBP"), "Tick who it's for.")
        draft.guests = ["Gary Guest"]
        XCTAssertNil(draft.problem(currency: "GBP"), "guests alone are somebody")
        let a = UUID(), b = UUID()
        draft.picked = [a, b]
        draft.hasDueDate = false
        let picked = try XCTUnwrap(draft.body(currency: "GBP"))
        XCTAssertEqual(Set(picked.userIds ?? []), [a, b])
        XCTAssertEqual(picked.guests, ["Gary Guest"])
        XCTAssertNil(picked.dueOn)
    }

    // MARK: - Paying for others

    func testEachPersonPaidForIsTheirOwnBlock() throws {
        let dues = try decode(MyDues.self, "pay_stepBC_me_dues_with_people")
        XCTAssertTrue(dues.clubs.isEmpty)
        XCTAssertEqual(dues.people.map(\.name), ["Arjun Gill", "Jas Gill"])
        XCTAssertEqual(dues.people.map(\.managed), [true, false])
        XCTAssertEqual(dues.owedSummary, "£15.00", "what a parent pays for is what they owe")

        let group = try XCTUnwrap(dues.groups.first)
        XCTAssertEqual(dues.groups.count, 1)
        XCTAssertNil(group.mine)
        XCTAssertEqual(group.clubName, dues.people[0].dues.clubName)
        XCTAssertFalse(group.clubName.isEmpty)
        XCTAssertFalse(group.includeMe)
        XCTAssertTrue(group.canPayForEveryone)
        XCTAssertEqual(group.totalOwedCents, 1500)
        XCTAssertEqual(group.whoWords, "Arjun and Jas")

        // The parent owes something themselves too: one payment for all three.
        let club = dues.people[0].clubId.uuidString
        let withMine = try decode(MyDues.self, "pay_stepBC_me_dues_with_people", replacing: #""clubs": []"#, with: """
            "clubs": [{"club_id":"\(club)","club_name":"Step BC","currency":"GBP","owed_cents":562,
                       "waiting_cents":0,"credit_cents":0,"shares":[]}]
            """)
        let all = try XCTUnwrap(withMine.groups.first)
        XCTAssertEqual(withMine.groups.count, 1, "the parent's own and the juniors' are one club")
        XCTAssertTrue(all.includeMe)
        XCTAssertEqual(all.totalOwedCents, 2062)
        XCTAssertEqual(all.whoWords, "you, Arjun and Jas")
        XCTAssertEqual(withMine.owedSummary, "£20.62")

        // An older server sends no people.
        let old = try decode(MyDues.self, json: #"{"clubs":[]}"#)
        XCTAssertTrue(old.people.isEmpty)
        XCTAssertTrue(old.groups.isEmpty)
    }

    func testPayingForOthersDecodes() throws {
        let paid = try decode(PaidForOthers.self, "pay_stepBC_pay_for_others")
        XCTAssertEqual(paid.totalCents, 1500)
        XCTAssertEqual(paid.reference, "GILL")
        XCTAssertEqual(paid.payments.map(\.name), ["Jas Gill", "Arjun Gill"])
        XCTAssertTrue(paid.payments.allSatisfy { $0.reference == "GILL" && $0.isWaiting }, "one reference, still checked")
        XCTAssertEqual(paid.notice(method: "transfer"),
                       "Thanks. £15.00 for 2 people, with the reference GILL. The club will confirm it once the money shows up.")
        XCTAssertEqual(paid.notice(method: "cash"),
                       "Thanks. £15.00 in cash for 2 people. The club will confirm it once they've got the cash.")
    }

    private func stubbedService() -> NetworkService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PassesStub.self]
        return NetworkService(session: URLSession(configuration: config))
    }

    private func refusal(_ status: Int, _ code: String, _ sentence: String) -> (Int, Data) {
        (status, Data(#"{"error":"\#(sentence)","code":"\#(code)"}"#.utf8))
    }

    /// One tap is one payment: a retry after a failure sends the same key,
    /// so the server answers with what it already recorded.
    @MainActor
    func testPayForEveryoneRetriesWithTheSameKey() async throws {
        let paid = try fixture("pay_stepBC_pay_for_others")
        let store = PayForOthersStore(clubId: UUID(), network: stubbedService())
        let jas = UUID(), arjun = UUID()

        PassesStub.handler = { _, _ in (502, Data(#"{"error":"Something went wrong on our side."}"#.utf8)) }
        let first = await store.pay(method: "transfer", people: [jas, arjun], includeMe: false)
        XCTAssertTrue(first.isFailure)
        XCTAssertEqual(store.problem, "Something went wrong on our side.")

        PassesStub.handler = { _, _ in (200, paid) }
        let second = await store.pay(method: "transfer", people: [arjun, jas], includeMe: false)
        XCTAssertEqual(second, .done)
        XCTAssertNil(store.problem)
        XCTAssertEqual(store.paid?.totalCents, 1500)
        XCTAssertEqual(store.notice,
                       "Thanks. £15.00 for 2 people, with the reference GILL. The club will confirm it once the money shows up.")

        let keys = PassesStub.seen.map { $0.0.value(forHTTPHeaderField: "Idempotency-Key") }
        XCTAssertEqual(keys.count, 2)
        XCTAssertNotNil(keys[0])
        XCTAssertEqual(keys[0], keys[1], "the retry is the same payment, whichever order the names came in")
        XCTAssertTrue(PassesStub.seen[0].0.url?.path.hasSuffix("/payments/for-others") ?? false)
        XCTAssertEqual(PassesStub.seen[0].0.httpMethod, "POST")

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: PassesStub.seen[1].1 ?? Data()) as? [String: Any])
        XCTAssertEqual(body["method"] as? String, "transfer")
        XCTAssertEqual(body["include_me"] as? Bool, false)
        XCTAssertEqual(Set(body["people"] as? [String] ?? []), [jas.uuidString, arjun.uuidString])
        XCTAssertNil(body["note"])

        // Done: the next tap is a new payment.
        _ = await store.pay(method: "transfer", people: [jas, arjun], includeMe: false)
        XCTAssertNotEqual(PassesStub.seen[2].0.value(forHTTPHeaderField: "Idempotency-Key"), keys[0])

        // Different people, or cash, are a different payment too.
        XCTAssertNotEqual(PayForOthersStore.scope(method: "cash", people: [jas], includeMe: false),
                          PayForOthersStore.scope(method: "transfer", people: [jas], includeMe: false))
        XCTAssertEqual(PayForOthersStore.scope(method: "cash", people: [jas, arjun], includeMe: true),
                       PayForOthersStore.scope(method: "cash", people: [arjun, jas], includeMe: true))
    }

    @MainActor
    func testNothingOwedIsNotAFailureAndNotTheirPayerIs() async throws {
        let store = PayForOthersStore(clubId: UUID(), network: stubbedService())
        let friend = UUID()

        PassesStub.handler = { _, _ in self.refusal(409, "nothing_owed", "Nobody you picked owes anything") }
        let stale = await store.pay(method: "transfer", people: [friend], includeMe: true)
        XCTAssertEqual(stale, .stale)
        XCTAssertNil(store.problem)
        XCTAssertEqual(store.notice, "Nobody you picked owes anything")

        PassesStub.handler = { _, _ in
            self.refusal(403, "not_their_payer", "You can pay for the people you pay for, or friends on the same bill")
        }
        let refused = await store.pay(method: "transfer", people: [friend], includeMe: true)
        XCTAssertEqual(refused, .failed("You can pay for the people you pay for, or friends on the same bill"))
        XCTAssertEqual(store.problem, "You can pay for the people you pay for, or friends on the same bill")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: PassesStub.seen.last?.1 ?? Data()) as? [String: Any])
        XCTAssertEqual(body["include_me"] as? Bool, true)
        XCTAssertNotEqual(PassesStub.seen[0].0.value(forHTTPHeaderField: "Idempotency-Key"),
                          PassesStub.seen[1].0.value(forHTTPHeaderField: "Idempotency-Key"),
                          "nothing_owed finished that attempt")
    }

    // MARK: - Where a pass or group fee notification goes

    private func notification(_ type: String, _ payload: [String: String]) throws -> AppNotification {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let json = """
        {"id":"\(UUID().uuidString)","type":"\(type)","payload":\(String(data: body, encoding: .utf8)!),
         "sent_at":"2026-11-22T10:41:35.123Z","read_at":null}
        """
        return try FishersJSONDecoder.make().decode(AppNotification.self, from: Data(json.utf8))
    }

    func testPassAndGroupFeeNotificationsOpenThePayScreen() throws {
        let club = UUID()
        for kind in ["pass_started", "pass_charge", "pass_behind", "pass_cancelled", "pass_sessions_left",
                     "pass_price_changed", "collection_issued"] {
            let item = try notification(kind, ["club_id": club.uuidString, "title": "t", "body": "b"])
            XCTAssertEqual(item.moneyRoute, .payScreen(club), kind)
        }
        // Since the security review `pass_suspended` is the holder's only;
        // money admins get `pass_suspended_club`, which opens the overview.
        XCTAssertEqual(try notification("pass_suspended", ["club_id": club.uuidString, "title": "t", "body": "b"]).moneyRoute,
                       .payScreen(club))
        XCTAssertEqual(try notification("pass_suspended_club", ["club_id": club.uuidString, "pass_holder_id": UUID().uuidString,
                                                               "title": "t", "body": "b"]).moneyRoute,
                       .overview(club))
        XCTAssertEqual(try notification("paid_for_you", ["club_id": club.uuidString, "payment_id": UUID().uuidString,
                                                        "title": "t", "body": "b"]).moneyRoute,
                       .payScreen(club))
    }

    // MARK: - Words

    func testTheNewWordsReadInPunjabi() {
        Strings.setCurrent(.pa)
        for english in [
            "Covered by your pass ✓", "Get this pass", "Pay for everyone", "Set up your standing order",
            "Send to someone who pays for me", "Cancel my pass", "I'm paying for friends too",
            "Prices for juniors, students…", "Group fees", "Different price for juniors?",
        ] {
            XCTAssertNotEqual(tr(english), english, english)
        }
        XCTAssertEqual(tr("Covered by your pass ✓"), "ਤੁਹਾਡੇ ਪਾਸ ਵਿੱਚ ਸ਼ਾਮਲ ✓")
        XCTAssertEqual(tr("{n} sessions left", vars: ["n": 3]), "3 ਸੈਸ਼ਨ ਬਾਕੀ")
    }

    /// The words a player must never meet.
    func testAPlayerNeverReadsTheSystemsWords() throws {
        let plans = try decode([PassPlan].self, "pay_stepBC_passes_member")
        let holders = try decode([PassHolder].self, "pay_stepBC_me_passes")
            + decode([PassHolder].self, "pay_stepBC_me_passes_suspended")
        var said: [String] = plans.flatMap { [$0.priceWords, $0.coverWords, $0.joinQuestion, $0.joinExplanation, $0.joinedNotice] }
        said += holders.flatMap {
            [$0.standingWords(today: today), $0.cancelQuestion(forSomeoneElse: true), $0.cancelWarning, $0.cancelledNotice]
        }
        if let order = holders.first?.standingOrder {
            said.append(order.detailsToSend(club: "Riverside", currency: "GBP", account: nil))
        }
        for line in said {
            for banned in ["subscription", "collection", "holder", "dependent", "price type", "claim", "waived"] {
                XCTAssertFalse(line.lowercased().contains(banned), "\(banned) in: \(line)")
            }
        }
    }
}

/// Answers from a closure and keeps what was sent, body included — which
/// URLSession hands a protocol as a stream rather than `httpBody`.
private final class PassesStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest, Data?) -> (Int, Data))?
    nonisolated(unsafe) static var seen: [(URLRequest, Data?)] = []

    static func reset() {
        handler = nil
        seen = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = PassesStub.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        PassesStub.seen.append((request, body))
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
