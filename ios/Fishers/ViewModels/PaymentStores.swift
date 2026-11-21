import Foundation
import SwiftUI

// The screens of "pay the club by bank transfer": a player's pay screen and
// dues, an event's money section, and the treasurer's overview. Each store
// reloads after a write rather than patching its copy — the balances are
// worked out on the server, and a phone that worked them out too would one
// day disagree with it.

/// The idempotency key for one attempt at a payment.
///
/// Made on the first tap and kept until the server has answered with
/// success, so a retry after a dropped connection sends the same key and the
/// server answers with the payment it already made. Asking for a different
/// thing (another person, another amount) starts a new attempt.
struct PaymentAttempt {
    private var scope: String?
    private var key: UUID?

    mutating func key(for scope: String) -> UUID {
        if let key, self.scope == scope { return key }
        let fresh = UUID()
        self.scope = scope
        key = fresh
        return fresh
    }

    /// The server has it: the next tap is a new payment.
    mutating func finished() {
        scope = nil
        key = nil
    }
}

/// The sentence to show for a failure: the API's own when it sent one.
func paymentMessage(_ error: Error) -> String {
    (error as? APIError)?.friendlyMessage ?? error.localizedDescription
}

/// How a write went. A sheet shows `failed` inside itself: an alert raised
/// on the screen underneath cannot appear while the sheet covers it.
enum PaymentWrite: Equatable {
    case done
    /// Somebody got there first; the store reloaded and put the server's
    /// sentence in `notice`.
    case stale
    case failed(String)

    var isFailure: Bool { failure != nil }
    var failure: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

// MARK: - Pay screen

@MainActor
final class PayScreenStore: ObservableObject {
    @Published private(set) var screen: PayScreen?
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    /// Not a failure: "the club will confirm it", or the server saying
    /// somebody got there first.
    @Published var notice: String?

    let clubId: UUID
    private var attempt = PaymentAttempt()

    init(clubId: UUID) {
        self.clubId = clubId
    }

    var errorBinding: Binding<Bool> {
        Binding(get: { self.errorMessage != nil }, set: { if !$0 { self.errorMessage = nil } })
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            screen = try await FishersAPI.payScreen(clubId: clubId)
        } catch {
            errorMessage = paymentMessage(error)
        }
    }

    /// "I've paid" (`transfer`) or "I paid cash".
    func claim(method: String) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let key = attempt.key(for: "claim:\(method)")
        do {
            _ = try await FishersAPI.claimPayment(clubId: clubId, method: method, key: key)
            attempt.finished()
            notice = method == "cash"
                ? tr("Thanks. The club will confirm it once they've got the cash.")
                : tr("Thanks. The club will confirm it once the money shows up in their account.")
            await load()
        } catch let error as APIError where error.isStale {
            attempt.finished()
            notice = error.friendlyMessage
            await load()
        } catch {
            // Kept: a retry of this tap sends the same key.
            errorMessage = paymentMessage(error)
        }
    }

    func undo(_ claim: ClubPayment) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await FishersAPI.cancelClaim(claim.id)
            notice = tr("Undone. You still owe it.")
            await load()
        } catch let error as APIError where error.isStale {
            notice = error.friendlyMessage
            await load()
        } catch {
            errorMessage = paymentMessage(error)
        }
    }
}

// MARK: - What I owe

@MainActor
final class DuesStore: ObservableObject {
    @Published private(set) var dues: MyDues?
    @Published private(set) var failed: String?

    func load() async {
        do {
            dues = try await FishersAPI.myDues()
            failed = nil
        } catch {
            // The card is a nudge, not the only way in: an old server without
            // /me/dues simply shows no card.
            failed = paymentMessage(error)
        }
    }
}

// MARK: - An event's money

@MainActor
final class EventMoneyStore: ObservableObject {
    @Published private(set) var page: EventBillPage?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var notice: String?

    let eventId: UUID

    init(eventId: UUID) {
        self.eventId = eventId
    }

    var errorBinding: Binding<Bool> {
        Binding(get: { self.errorMessage != nil }, set: { if !$0 { self.errorMessage = nil } })
    }

    /// Asked once, whatever the answer — so the old card button does not
    /// flash up and vanish while the bill is on its way.
    @Published private(set) var hasLoaded = false

    /// Whether the old card-payment button should step aside: once an event
    /// has a cost or a bill, paying the club is this section's job.
    var ownsPayment: Bool { !hasLoaded || page?.cost != nil || page?.bill != nil }

    func load() async {
        defer { hasLoaded = true }
        // A 403 (not a member) or an API without bills leaves nothing to
        // show, and nothing worth an alert on the fixture page.
        if let fresh = try? await FishersAPI.eventBill(eventId: eventId) {
            page = fresh
        }
    }

    /// Runs a write, then reloads. A stale answer reloads and shows the
    /// server's sentence as information; a failure is handed back for the
    /// caller to show where the person is looking.
    private func perform(_ work: () async throws -> Void) async -> PaymentWrite {
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

    /// For the actions taken on the section itself: a failure is an alert.
    private func performHere(_ work: () async throws -> Void) async {
        if case .failed(let message) = await perform(work) { errorMessage = message }
    }

    /// From the cost sheet, which shows its own failures.
    func setCost(mode: CostMode, amountCents: Int, note: String?, applyToSeries: Bool) async -> PaymentWrite {
        await perform {
            try await FishersAPI.setEventCost(
                eventId: eventId, mode: mode, amountCents: amountCents,
                note: note, applyToSeries: applyToSeries
            )
        }
    }

    func removeCost() async {
        await performHere { try await FishersAPI.removeEventCost(eventId: eventId) }
    }

    /// For the live total on "Who came?". Errors come back as the sentence to
    /// show under the list (`no_attendees`, `amount_limit`), not as alerts.
    enum PreviewOutcome {
        case ready(BillPreview)
        case refused(String)
    }

    func preview(_ body: BillBody) async -> PreviewOutcome {
        do {
            return .ready(try await FishersAPI.previewBill(eventId: eventId, body))
        } catch {
            return .refused(paymentMessage(error))
        }
    }

    /// Sends the bill, or re-splits it when `body.version` is set. From the
    /// "Who came?" sheet, which shows its own failures.
    func send(_ body: BillBody) async -> PaymentWrite {
        await perform {
            page = try await FishersAPI.sendBill(eventId: eventId, body)
        }
    }

    func void(reason: String) async {
        await performHere {
            page = try await FishersAPI.voidBill(eventId: eventId, reason: reason)
        }
    }

    func waive(_ share: ClubShare, reason: String) async {
        await performHere { _ = try await FishersAPI.waiveShare(share.id, reason: reason) }
    }
}

// MARK: - The treasurer's overview

@MainActor
final class ClubMoneyStore: ObservableObject {
    @Published private(set) var overview: MoneyOverview?
    /// The server said no: this person does not look after the club's money.
    @Published private(set) var forbidden = false
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var notice: String?

    let clubId: UUID
    private var attempt = PaymentAttempt()
    private var settingsTask: Task<Void, Never>?

    init(clubId: UUID) {
        self.clubId = clubId
    }

    var errorBinding: Binding<Bool> {
        Binding(get: { self.errorMessage != nil }, set: { if !$0 { self.errorMessage = nil } })
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            overview = try await FishersAPI.moneyOverview(clubId: clubId)
            forbidden = false
        } catch let error as APIError where error.isForbidden {
            forbidden = true
            overview = nil
        } catch {
            if overview != nil { errorMessage = paymentMessage(error) }
        }
    }

    private func perform(_ work: () async throws -> Void) async -> PaymentWrite {
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

    /// For the actions taken on the screen itself: a failure is an alert.
    private func performHere(_ work: () async throws -> Void) async {
        if case .failed(let message) = await perform(work) { errorMessage = message }
    }

    // MARK: Bank details

    enum BankDetailsOutcome: Equatable {
        case saved
        /// Ask for the password: the session is fine.
        case needsPassword(String)
        case refused(String)
    }

    func saveBankDetails(_ details: NewPayoutAccount) async -> BankDetailsOutcome {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await FishersAPI.addPayoutAccount(clubId: clubId, details)
            await load()
            return .saved
        } catch let error as APIError where error.wantsPassword {
            return .needsPassword(error.friendlyMessage)
        } catch {
            return .refused(paymentMessage(error))
        }
    }

    func freeze(_ account: PayoutAccount, reason: String?) async {
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        await performHere {
            _ = try await FishersAPI.freezePayoutAccount(
                clubId: clubId, accountId: account.id, reason: (trimmed?.isEmpty ?? true) ? nil : trimmed
            )
        }
    }

    func unfreeze(_ account: PayoutAccount) async {
        await performHere { _ = try await FishersAPI.unfreezePayoutAccount(clubId: clubId, accountId: account.id) }
    }

    func retire(_ account: PayoutAccount) async {
        await performHere { _ = try await FishersAPI.retirePayoutAccount(clubId: clubId, accountId: account.id) }
    }

    // MARK: Payments to check

    func confirm(_ payment: ClubPayment) async {
        await performHere { _ = try await FishersAPI.confirmPayment(payment.id) }
    }

    func reject(_ payment: ClubPayment, reason: String) async {
        await performHere { _ = try await FishersAPI.rejectPayment(payment.id, reason: reason) }
    }

    // MARK: Who owes what

    /// Cash at the ground, or a transfer nobody claimed. From a sheet, which
    /// shows its own failures. The key is kept after a failure, so trying
    /// again is the same request.
    func record(for member: MemberBalance, amountCents: Int, method: String, note: String?) async -> PaymentWrite {
        let key = attempt.key(for: "record:\(member.id):\(amountCents):\(method)")
        let outcome = await perform {
            _ = try await FishersAPI.recordPayment(
                clubId: clubId, payer(member, amountCents, method: method, note: note), key: key
            )
        }
        if !outcome.isFailure { attempt.finished() }
        return outcome
    }

    func refund(for member: MemberBalance, amountCents: Int, note: String?) async -> PaymentWrite {
        let key = attempt.key(for: "refund:\(member.id):\(amountCents)")
        let outcome = await perform {
            _ = try await FishersAPI.refundCredit(
                clubId: clubId, payer(member, amountCents, method: nil, note: note), key: key
            )
        }
        if !outcome.isFailure { attempt.finished() }
        return outcome
    }

    private func payer(_ member: MemberBalance, _ amount: Int, method: String?, note: String?) -> FishersAPI.PayerBody {
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FishersAPI.PayerBody(
            user_id: member.userId,
            guest_name: member.userId == nil ? (member.guestName ?? member.name) : nil,
            amount_cents: amount,
            method: method,
            note: (note?.isEmpty ?? true) ? nil : note
        )
    }

    // MARK: Settings

    /// Applied at once on screen, saved once the taps stop — a stepper fires
    /// on every tap.
    func mutateSettings(_ change: (inout PaymentSettings) -> Void) {
        guard var current = overview?.settings, let overview else { return }
        change(&current)
        self.overview = overview.replacingSettings(current)
        settingsTask?.cancel()
        settingsTask = Task { [current, clubId] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            do {
                try await FishersAPI.updatePaymentSettings(clubId: clubId, current)
            } catch {
                errorMessage = paymentMessage(error)
                await load()
            }
        }
    }
}

private extension MoneyOverview {
    func replacingSettings(_ settings: PaymentSettings) -> MoneyOverview {
        var copy = self
        copy.settings = settings
        return copy
    }
}
