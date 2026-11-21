import Foundation

// MARK: - Paying the club by bank transfer

/// The calls behind docs/PAY_BY_BANK_TRANSFER.md §11. Errors come back as
/// `APIError.http` with the server's own sentence and a stable `code`; see
/// `APIError.wantsPassword` and `APIError.isStale` for the ones that are not
/// failures.
extension FishersAPI {
    private static func club(_ id: UUID) -> String { "/clubs/\(id.uuidString)" }

    /// One payment attempt. Made once per tap and kept until the server
    /// answers, so a retry on bad signal is the same request, not a second
    /// claim — the server answers a repeated key with the first payment.
    private static func idempotent(_ key: UUID) -> [String: String] {
        // Header names are case-insensitive; the server reads it lower-case.
        ["idempotency-key": key.uuidString]
    }

    // MARK: Bank details

    static func payoutAccounts(clubId: UUID) async throws -> PayoutAccounts {
        try await NetworkService.shared.request("GET", path: club(clubId) + "/payout-account")
    }

    /// A 428 `reauth_required` or 403 `wrong_password` means type the
    /// password; neither is the session ending.
    static func addPayoutAccount(clubId: UUID, _ details: NewPayoutAccount) async throws -> PayoutAccounts {
        try await NetworkService.shared.request("POST", path: club(clubId) + "/payout-account", body: details)
    }

    static func freezePayoutAccount(clubId: UUID, accountId: UUID, reason: String?) async throws -> PayoutAccounts {
        struct Body: Encodable { let reason: String? }
        return try await NetworkService.shared.request(
            "POST", path: club(clubId) + "/payout-account/\(accountId.uuidString)/freeze",
            body: Body(reason: reason)
        )
    }

    /// Owner only; anybody else gets `owner_only`.
    static func unfreezePayoutAccount(clubId: UUID, accountId: UUID) async throws -> PayoutAccounts {
        try await NetworkService.shared.request(
            "POST", path: club(clubId) + "/payout-account/\(accountId.uuidString)/unfreeze"
        )
    }

    /// Removes the details, or cancels a change still waiting to go live.
    static func retirePayoutAccount(clubId: UUID, accountId: UUID) async throws -> PayoutAccounts {
        try await NetworkService.shared.request(
            "POST", path: club(clubId) + "/payout-account/\(accountId.uuidString)/retire"
        )
    }

    // MARK: The treasurer's side

    /// A 403 means this person is not a money admin. That is how the app
    /// decides whether to show the Payments screen at all.
    static func moneyOverview(clubId: UUID) async throws -> MoneyOverview {
        try await NetworkService.shared.request("GET", path: club(clubId) + "/money")
    }

    static func updatePaymentSettings(clubId: UUID, _ settings: PaymentSettings) async throws {
        try await NetworkService.shared.requestVoid(
            "PUT", path: club(clubId) + "/payments/settings", body: settings
        )
    }

    static func confirmPayment(_ id: UUID) async throws -> ClubPayment {
        try await NetworkService.shared.request("POST", path: "/payments/\(id.uuidString)/confirm")
    }

    static func rejectPayment(_ id: UUID, reason: String) async throws -> ClubPayment {
        struct Body: Encodable { let reason: String }
        return try await NetworkService.shared.request(
            "POST", path: "/payments/\(id.uuidString)/reject", body: Body(reason: reason)
        )
    }

    /// Who paid: a member by id, or a guest by name — never both.
    struct PayerBody: Encodable {
        let user_id: UUID?
        let guest_name: String?
        let amount_cents: Int
        let method: String?
        let note: String?
    }

    /// Cash at the ground, or a transfer nobody claimed. Confirmed at once.
    static func recordPayment(clubId: UUID, _ body: PayerBody, key: UUID) async throws -> ClubPayment {
        try await NetworkService.shared.request(
            "POST", path: club(clubId) + "/payments/record", body: body, headers: idempotent(key)
        )
    }

    /// At most the credit they hold (`more_than_credit`).
    static func refundCredit(clubId: UUID, _ body: PayerBody, key: UUID) async throws -> ClubPayment {
        try await NetworkService.shared.request(
            "POST", path: club(clubId) + "/payments/refund", body: body, headers: idempotent(key)
        )
    }

    static func waiveShare(_ id: UUID, reason: String) async throws -> ClubShare {
        struct Body: Encodable { let reason: String }
        return try await NetworkService.shared.request(
            "POST", path: "/shares/\(id.uuidString)/waive", body: Body(reason: reason)
        )
    }

    // MARK: An event's cost and bill

    static func eventBill(eventId: UUID) async throws -> EventBillPage {
        try await NetworkService.shared.request("GET", path: "/events/\(eventId.uuidString)/bill")
    }

    /// `already_billed` once there is a bill: re-split instead.
    static func setEventCost(
        eventId: UUID, mode: CostMode, amountCents: Int, note: String?, applyToSeries: Bool
    ) async throws {
        struct Body: Encodable {
            let mode: String
            let amount_cents: Int
            let note: String?
            let apply_to_series: Bool
        }
        try await NetworkService.shared.requestVoid(
            "PUT", path: "/events/\(eventId.uuidString)/cost",
            body: Body(mode: mode.raw, amount_cents: amountCents, note: note, apply_to_series: applyToSeries)
        )
    }

    static func removeEventCost(eventId: UUID) async throws {
        try await NetworkService.shared.requestVoid("DELETE", path: "/events/\(eventId.uuidString)/cost")
    }

    static func previewBill(eventId: UUID, _ body: BillBody) async throws -> BillPreview {
        try await NetworkService.shared.request(
            "POST", path: "/events/\(eventId.uuidString)/bill/preview", body: body
        )
    }

    /// Sends a first bill, or re-splits one when `body.version` is set.
    static func sendBill(eventId: UUID, _ body: BillBody) async throws -> EventBillPage {
        try await NetworkService.shared.request(
            "POST", path: "/events/\(eventId.uuidString)/bill", body: body
        )
    }

    static func voidBill(eventId: UUID, reason: String) async throws -> EventBillPage {
        struct Body: Encodable { let reason: String }
        return try await NetworkService.shared.request(
            "POST", path: "/events/\(eventId.uuidString)/bill/void", body: Body(reason: reason)
        )
    }

    // MARK: The player's side

    static func myDues() async throws -> MyDues {
        try await NetworkService.shared.request("GET", path: "/me/dues")
    }

    static func payScreen(clubId: UUID) async throws -> PayScreen {
        try await NetworkService.shared.request("GET", path: club(clubId) + "/pay")
    }

    /// "I've paid" (`transfer`) or "I paid cash". The amount defaults to
    /// everything owed. `nothing_owed` is not a failure: refresh.
    static func claimPayment(clubId: UUID, method: String, key: UUID) async throws -> ClubPayment {
        struct Body: Encodable { let method: String }
        return try await NetworkService.shared.request(
            "POST", path: club(clubId) + "/payments", body: Body(method: method), headers: idempotent(key)
        )
    }

    /// Undo a claim nobody has confirmed yet.
    static func cancelClaim(_ id: UUID) async throws {
        try await NetworkService.shared.requestVoid("DELETE", path: "/payments/\(id.uuidString)")
    }
}
