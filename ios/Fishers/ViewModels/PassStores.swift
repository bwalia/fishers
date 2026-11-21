import Foundation
import SwiftUI

// Passes, group fees, prices for juniors and others, and paying for other
// people. Like the step A stores, each reloads after a write rather than
// patching its copy: balances and standing are worked out on the server.

// MARK: - A player's passes, on the club's pay screen

@MainActor
final class PlayerPassesStore: ObservableObject {
    /// The club's passes, with the reader's own on each.
    @Published private(set) var plans: [PassPlan] = []
    /// The reader's passes here, and those of anybody they pay for.
    @Published private(set) var passes: [PassHolder] = []
    @Published private(set) var groups: [PriceType] = []
    /// Who the reader pays for in this club.
    @Published private(set) var people: [PersonDues] = []
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var notice: String?

    let clubId: UUID

    init(clubId: UUID) {
        self.clubId = clubId
    }

    var errorBinding: Binding<Bool> {
        Binding(get: { self.errorMessage != nil }, set: { if !$0 { self.errorMessage = nil } })
    }

    /// Each part on its own: a server without passes shows no section, and
    /// one that answers some of it shows what it can.
    func load() async {
        async let plans = try? FishersAPI.passes(clubId: clubId)
        async let mine = try? FishersAPI.myPasses()
        async let groups = try? FishersAPI.priceTypes(clubId: clubId)
        async let dues = try? FishersAPI.myDues()
        self.plans = await plans ?? self.plans
        self.passes = (await mine)?.filter { $0.clubId == clubId } ?? self.passes
        self.groups = await groups ?? self.groups
        if let dues = await dues { people = dues.people.filter { $0.clubId == clubId } }
    }

    /// The reader's own, as `mine` on each pass says.
    func isMine(_ holder: PassHolder) -> Bool {
        plans.contains { $0.mine?.id == holder.id } || !people.contains { $0.userId == holder.userId }
    }

    /// Passes somebody can still get here: offered, open, and not already
    /// held by everyone it could be for.
    var offered: [PassPlan] {
        plans.filter { plan in
            !plan.isArchived && plan.openToJoin && !whoCanGet(plan).isEmpty
        }
    }

    /// Who the reader could get it for: themselves (nil) and each person
    /// they pay for who isn't on it yet.
    func whoCanGet(_ plan: PassPlan) -> [PersonDues?] {
        var out: [PersonDues?] = []
        if plan.mine == nil { out.append(nil) }
        for person in people where !passes.contains(where: { $0.planId == plan.id && $0.userId == person.userId && !$0.isCancelled }) {
            out.append(person)
        }
        return out
    }

    /// A charge for this pass still owed: the reader's own lines for their
    /// pass, the dues of whoever they pay for for theirs.
    func chargeOwed(_ holder: PassHolder, myShares: [ClubShare]) -> Bool {
        let shares = isMine(holder)
            ? myShares
            : people.first { $0.userId == holder.userId }?.dues.shares ?? []
        return holder.hasChargeOwed(in: shares)
    }

    /// True when something changed, so the pay screen reloads what is owed.
    func join(_ plan: PassPlan, for person: UUID?) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        notice = nil
        do {
            _ = try await FishersAPI.joinPass(passId: plan.id, forUserId: person)
            notice = plan.joinedNotice
            await load()
            return true
        } catch let error as APIError where error.isStale {
            notice = error.friendlyMessage
            await load()
            return true
        } catch {
            // not_eligible, not_open: the server's sentence says why.
            errorMessage = paymentMessage(error)
            return false
        }
    }

    func cancel(_ holder: PassHolder) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        notice = nil
        do {
            let after = try await FishersAPI.cancelPass(holderId: holder.id)
            notice = after.cancelledNotice
            await load()
            return true
        } catch let error as APIError where error.isStale {
            notice = error.friendlyMessage
            await load()
            return true
        } catch {
            errorMessage = paymentMessage(error)
            return false
        }
    }
}

// MARK: - One payment for several people

/// "Pay for everyone" (a parent and their juniors) and "I'm paying for
/// friends too": one payment, one reference, through `for-others`.
///
/// The Idempotency-Key is made on the first tap and kept until the server
/// answers with success, so a retry after a dropped connection is the same
/// payment, not a second one. Asking for different people starts afresh.
@MainActor
final class PayForOthersStore: ObservableObject {
    @Published private(set) var isWorking = false
    @Published var problem: String?
    @Published private(set) var paid: PaidForOthers?
    @Published private(set) var notice: String?

    let clubId: UUID
    private let network: NetworkService
    private var attempt = PaymentAttempt()

    init(clubId: UUID, network: NetworkService = .shared) {
        self.clubId = clubId
        self.network = network
    }

    /// The same request, the same key: what a retry has to send.
    static func scope(method: String, people: [UUID], includeMe: Bool) -> String {
        let ids = people.map(\.uuidString).sorted().joined(separator: ",")
        return "for-others:\(method):\(includeMe):\(ids)"
    }

    func pay(method: String, people: [UUID], includeMe: Bool, note: String? = nil) async -> PaymentWrite {
        guard !isWorking else { return .failed(tr("Something went wrong. Try again.")) }
        isWorking = true
        defer { isWorking = false }
        problem = nil
        let sorted = people.sorted { $0.uuidString < $1.uuidString }
        let key = attempt.key(for: Self.scope(method: method, people: sorted, includeMe: includeMe))
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = FishersAPI.ForOthersBody(
            method: method, people: sorted, include_me: includeMe, note: (trimmed?.isEmpty ?? true) ? nil : trimmed
        )
        do {
            let result = try await FishersAPI.payForOthers(clubId: clubId, body, key: key, network: network)
            attempt.finished()
            paid = result
            notice = result.notice(method: method)
            if method == "transfer" { PayGuide.rememberPaid(clubId: clubId) }
            return .done
        } catch let error as APIError where error.isStale {
            // nothing_owed: somebody paid already. Not a failure.
            attempt.finished()
            notice = error.friendlyMessage
            return .stale
        } catch {
            // Kept: trying again sends the same key.
            let message = paymentMessage(error)
            problem = message
            return .failed(message)
        }
    }
}

// MARK: - For money admins

/// What every money admin screen here shares: a write that reloads after,
/// a failure as an alert, a stale answer as information.
@MainActor
class MoneyAdminStore: ObservableObject {
    @Published fileprivate(set) var isWorking = false
    @Published fileprivate(set) var hasLoaded = false
    @Published var errorMessage: String?
    @Published var notice: String?

    let clubId: UUID

    init(clubId: UUID) {
        self.clubId = clubId
    }

    var errorBinding: Binding<Bool> {
        Binding(get: { self.errorMessage != nil }, set: { if !$0 { self.errorMessage = nil } })
    }

    func load() async {}

    /// A failure is handed back for a sheet to show inside itself.
    func perform(_ work: () async throws -> Void) async -> PaymentWrite {
        guard !isWorking else { return .failed(tr("Something went wrong. Try again.")) }
        isWorking = true
        defer { isWorking = false }
        notice = nil
        do {
            try await work()
            await load()
            return .done
        } catch let error as APIError where error.isStale {
            notice = error.friendlyMessage
            await load()
            return .stale
        } catch {
            return .failed(paymentMessage(error))
        }
    }

    /// For actions on the screen itself: a failure is an alert.
    func performHere(_ work: () async throws -> Void) async {
        if case .failed(let message) = await perform(work) { errorMessage = message }
    }
}

/// Passes: make them, see who's on each and how they stand, add somebody,
/// cancel, keep covering.
@MainActor
final class PassesAdminStore: MoneyAdminStore {
    @Published private(set) var plans: [PassPlan] = []
    @Published private(set) var groups: [PriceType] = []
    @Published private(set) var members: [ClubMemberDetail] = []
    @Published private(set) var holders: [UUID: [PassHolder]] = [:]

    let currency: String

    init(clubId: UUID, currency: String) {
        self.currency = currency
        super.init(clubId: clubId)
    }

    override func load() async {
        defer { hasLoaded = true }
        async let plans = FishersAPI.passes(clubId: clubId, all: true)
        async let groups = try? FishersAPI.priceTypes(clubId: clubId)
        async let members = try? FishersAPI.clubMembers(clubId: clubId)
        do {
            self.plans = try await plans
        } catch {
            if hasLoaded { errorMessage = paymentMessage(error) }
        }
        self.groups = await groups ?? self.groups
        self.members = (await members)?.filter(\.isActive).sorted { $0.name < $1.name } ?? self.members
    }

    var offered: [PassPlan] { plans.filter { !$0.isArchived } }
    var stopped: [PassPlan] { plans.filter(\.isArchived) }

    func loadHolders(_ plan: PassPlan) async {
        do {
            holders[plan.id] = try await FishersAPI.passHolders(passId: plan.id)
        } catch {
            errorMessage = paymentMessage(error)
        }
    }

    func create(_ body: NewPassBody) async -> PaymentWrite {
        let outcome = await perform { _ = try await FishersAPI.createPass(clubId: clubId, body) }
        if outcome == .done { notice = tr("{pass} is ready. Players see it on the club's pay screen.", vars: ["pass": body.name]) }
        return outcome
    }

    func setOpen(_ plan: PassPlan, _ on: Bool) async {
        await performHere { _ = try await FishersAPI.updatePass(plan.id, openToJoin: on) }
    }

    func stopOffering(_ plan: PassPlan) async {
        await performHere { _ = try await FishersAPI.updatePass(plan.id, archived: true) }
    }

    func offerAgain(_ plan: PassPlan) async {
        await performHere { _ = try await FishersAPI.updatePass(plan.id, archived: false) }
    }

    /// From the "Add somebody" sheet, which shows its own failures.
    func add(_ member: ClubMemberDetail, to plan: PassPlan) async -> PaymentWrite {
        let outcome = await perform { _ = try await FishersAPI.addToPass(passId: plan.id, userId: member.userId) }
        if outcome.isFailure { return outcome }
        await loadHolders(plan)
        if outcome == .done {
            notice = tr("{name} is on {pass}. Their first payment is in what they owe.", vars: ["name": member.name, "pass": plan.name])
        }
        return outcome
    }

    func cancel(_ holder: PassHolder, on plan: PassPlan) async {
        await performHere { _ = try await FishersAPI.cancelPass(holderId: holder.id) }
        await loadHolders(plan)
    }

    func keepCovering(_ holder: PassHolder, on plan: PassPlan, _ on: Bool) async {
        await performHere { _ = try await FishersAPI.keepCovering(holderId: holder.id, on: on) }
        await loadHolders(plan)
    }
}

/// Prices for juniors, students, guests: the groups, each member's group,
/// who pays for whom, and juniors added by name. Each member's group and
/// payer are the server's (`/payments/members`), read again after a change.
@MainActor
final class PriceGroupsStore: MoneyAdminStore {
    @Published private(set) var groups: [PriceType] = []
    @Published private(set) var members: [MoneyMember] = []

    override func load() async {
        defer { hasLoaded = true }
        async let groups = FishersAPI.priceTypes(clubId: clubId)
        async let members = try? FishersAPI.moneyMembers(clubId: clubId)
        do {
            self.groups = try await groups
        } catch {
            if hasLoaded { errorMessage = paymentMessage(error) }
        }
        self.members = (await members)?.sorted { $0.name < $1.name } ?? self.members
    }

    /// Who can pay for somebody: a member who signs in themselves.
    var payers: [MoneyMember] { members.filter { !$0.managed } }

    func create(name: String, free: Bool, forGuests: Bool) async -> PaymentWrite {
        let clean = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return await perform {
            _ = try await FishersAPI.createPriceType(clubId: clubId, name: clean, free: free, forGuests: forGuests)
        }
    }

    func update(_ group: PriceType, name: String, free: Bool, forGuests: Bool) async -> PaymentWrite {
        let clean = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return await perform {
            _ = try await FishersAPI.updatePriceType(
                group.id, name: clean == group.name ? nil : clean, free: free, forGuests: forGuests
            )
        }
    }

    func stopUsing(_ group: PriceType) async -> PaymentWrite {
        await perform { _ = try await FishersAPI.updatePriceType(group.id, archived: true) }
    }

    func setGroup(_ member: MoneyMember, to group: UUID?) async -> PaymentWrite {
        await perform {
            try await FishersAPI.setMemberPriceType(clubId: clubId, userId: member.userId, priceTypeId: group)
        }
    }

    func setPayer(_ member: MoneyMember, to payer: UUID?) async -> PaymentWrite {
        await perform {
            try await FishersAPI.setPayer(clubId: clubId, memberId: member.userId, payerId: payer)
        }
    }

    /// A junior by name, looked after by whoever pays, on the juniors'
    /// price if one is picked.
    func addJunior(name: String, payer: UUID, group: UUID?) async -> PaymentWrite {
        let clean = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var added: ManagedMember?
        let outcome = await perform {
            let junior = try await FishersAPI.addJunior(clubId: clubId, name: clean, payerId: payer)
            added = junior
            if let group {
                try await FishersAPI.setMemberPriceType(clubId: clubId, userId: junior.userId, priceTypeId: group)
            }
        }
        if let added {
            notice = tr("{name} is in the club. Whoever pays for them sees what they owe.", vars: ["name": added.name])
            // The second step can fail after the first worked: the junior is
            // there, so say so rather than "try again", which would add them twice.
            if case .failed(let message) = outcome {
                errorMessage = message
                return .done
            }
        }
        return outcome
    }

    func groupName(_ id: UUID?) -> String {
        guard let id else { return tr("Standard price") }
        return groups.first { $0.id == id }?.name ?? ""
    }

    /// "Price: Junior", "Paid for by Neha Gill", "No sign-in of their own".
    func lines(_ member: MoneyMember) -> [String] {
        var out: [String] = []
        if member.priceTypeId != nil {
            out.append(tr("Price: {group}", vars: ["group": groupName(member.priceTypeId)]))
        }
        if let payer = member.payerName ?? members.first(where: { $0.userId == member.payerId })?.name {
            out.append(tr("Paid for by {name}", vars: ["name": payer]))
        }
        if member.managed { out.append(tr("No sign-in of their own")) }
        return out
    }
}

/// Group fees: the list, and a new one.
@MainActor
final class GroupFeesStore: MoneyAdminStore {
    @Published private(set) var fees: [GroupFee] = []
    @Published private(set) var teams: [Team] = []
    @Published private(set) var groups: [PriceType] = []
    @Published private(set) var members: [ClubMemberDetail] = []

    let currency: String
    private var attempt = PaymentAttempt()

    init(clubId: UUID, currency: String) {
        self.currency = currency
        super.init(clubId: clubId)
    }

    override func load() async {
        defer { hasLoaded = true }
        async let fees = FishersAPI.groupFees(clubId: clubId)
        async let teams = try? FishersAPI.teams(clubId: clubId)
        async let groups = try? FishersAPI.priceTypes(clubId: clubId)
        async let members = try? FishersAPI.clubMembers(clubId: clubId)
        do {
            self.fees = try await fees
        } catch {
            if hasLoaded { errorMessage = paymentMessage(error) }
        }
        self.teams = await teams ?? self.teams
        self.groups = await groups ?? self.groups
        self.members = (await members)?.filter(\.isActive).sorted { $0.name < $1.name } ?? self.members
    }

    /// The new group fee, to share straight away; nil after a failure,
    /// which comes back as the write's outcome.
    ///
    /// The Idempotency-Key is kept until the server has answered, so Send
    /// tapped again after a dropped connection doesn't bill everybody twice.
    /// A changed form is a different group fee.
    func create(_ body: NewGroupFeeBody) async -> (PaymentWrite, GroupFee?) {
        let key = attempt.key(for: Self.scope(body))
        var made: GroupFee?
        let outcome = await perform { made = try await FishersAPI.createGroupFee(clubId: clubId, body, key: key) }
        if !outcome.isFailure { attempt.finished() }
        return (outcome, made)
    }

    /// The same form, the same key.
    nonisolated static func scope(_ body: NewGroupFeeBody) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = (try? encoder.encode(body)).flatMap { String(data: $0, encoding: .utf8) } ?? UUID().uuidString
        return "group-fee:\(json)"
    }
}

/// One group fee: everyone's lines, sharing it to WhatsApp, cancelling it.
@MainActor
final class GroupFeeStore: ObservableObject {
    @Published private(set) var fee: GroupFee?
    /// The open pay link, once asked for; nil while there is none.
    @Published private(set) var link: BillLink?
    /// Whether `link` is the server's answer yet, rather than not asked.
    @Published private(set) var linkKnown = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var notice: String?

    let billId: UUID

    init(billId: UUID, fee: GroupFee? = nil) {
        self.billId = billId
        self.fee = fee
    }

    /// The link already open, if any: `GET` never makes one, so opening the
    /// page doesn't put a link into the world nobody asked for.
    func loadLink() async {
        do {
            link = try await FishersAPI.openGroupFeeLink(billId: billId)
            linkKnown = true
        } catch {
            // Not known: the share block offers everything, as it did
            // before servers could say.
        }
    }

    var errorBinding: Binding<Bool> {
        Binding(get: { self.errorMessage != nil }, set: { if !$0 { self.errorMessage = nil } })
    }

    func load() async {
        do {
            fee = try await FishersAPI.groupFee(billId: billId)
        } catch {
            errorMessage = paymentMessage(error)
        }
    }

    /// The open link, or a new one made when somebody taps to share —
    /// never on opening the page.
    func billLink() async -> BillLink? {
        if let link { return link }
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        notice = nil
        do {
            let made = try await FishersAPI.groupFeeLink(billId: billId)
            link = made
            linkKnown = true
            return made
        } catch let error as APIError where error.isStale {
            notice = error.friendlyMessage
            await load()
        } catch {
            errorMessage = paymentMessage(error)
        }
        return nil
    }

    func switchLinkOff() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await FishersAPI.disableGroupFeeLink(billId: billId)
            link = nil
            linkKnown = true
            notice = tr("The link is off. Sharing the bill again makes a new one.")
        } catch {
            errorMessage = paymentMessage(error)
        }
    }

    func cancel(reason: String) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            fee = try await FishersAPI.cancelGroupFee(billId: billId, reason: reason)
            // Cancelling closes its pay link.
            link = nil
            notice = tr("Cancelled. Anything already paid towards it becomes credit.")
        } catch let error as APIError where error.isStale {
            notice = error.friendlyMessage
            await load()
        } catch {
            errorMessage = paymentMessage(error)
        }
    }
}
