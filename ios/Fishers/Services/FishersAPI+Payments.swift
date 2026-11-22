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

    /// Every payment POST goes through this. A `busy` (409) means another
    /// request is saving a payment for the same person at that moment — a
    /// double tap, say. One quiet retry after about a second, with the same
    /// Idempotency-Key (the caller's closure carries it), gets the first
    /// payment back. Busy twice is shown like any other failure, and the key
    /// is kept for the person's own retry.
    static func retryingBusy<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as APIError where error.code == "busy" {
            try await Task.sleep(for: .seconds(1))
            return try await work()
        }
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

    /// The club's usual prices, readable by any member — a captain scheduling
    /// nets included, who can't open the money overview.
    static func usualPrices(clubId: UUID) async throws -> UsualPrices {
        let settings: PaymentSettings = try await NetworkService.shared.request(
            "GET", path: club(clubId) + "/payments/defaults")
        return settings.usualPrices
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
        try await retryingBusy {
            try await NetworkService.shared.request(
                "POST", path: club(clubId) + "/payments/record", body: body, headers: idempotent(key)
            )
        }
    }

    /// At most the credit they hold (`more_than_credit`).
    static func refundCredit(clubId: UUID, _ body: PayerBody, key: UUID) async throws -> ClubPayment {
        try await retryingBusy {
            try await NetworkService.shared.request(
                "POST", path: club(clubId) + "/payments/refund", body: body, headers: idempotent(key)
            )
        }
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
    static func claimPayment(
        clubId: UUID, method: String, key: UUID, network: NetworkService = .shared
    ) async throws -> ClubPayment {
        struct Body: Encodable { let method: String }
        return try await retryingBusy {
            try await network.request(
                "POST", path: club(clubId) + "/payments", body: Body(method: method), headers: idempotent(key)
            )
        }
    }

    /// Undo a claim nobody has confirmed yet: the reader's own, or one they
    /// made for somebody else.
    static func cancelClaim(_ id: UUID) async throws {
        try await NetworkService.shared.requestVoid("DELETE", path: "/payments/\(id.uuidString)")
    }

    // MARK: Easy paying (step A)

    /// The bill's pay link and the messages to post, reusing the open link.
    /// `no_bill` (409) until the bill is sent.
    static func billLink(eventId: UUID) async throws -> BillLink {
        try await NetworkService.shared.request("POST", path: "/events/\(eventId.uuidString)/bill/link")
    }

    /// Closes every open link for the bill. Sharing again makes a new one.
    static func disableBillLink(eventId: UUID) async throws {
        try await NetworkService.shared.requestVoid("POST", path: "/events/\(eventId.uuidString)/bill/link/disable")
    }

    /// Cash at the ground: who handed money over, by share.
    static func recordCash(eventId: UUID, shareIds: [UUID], key: UUID) async throws -> CashRecorded {
        struct Body: Encodable { let share_ids: [UUID] }
        return try await retryingBusy {
            try await NetworkService.shared.request(
                "POST", path: "/events/\(eventId.uuidString)/bill/cash",
                body: Body(share_ids: shareIds), headers: idempotent(key)
            )
        }
    }

    /// All arrived. One already checked by somebody else comes back skipped.
    static func confirmPayments(clubId: UUID, ids: [UUID], key: UUID) async throws -> ConfirmedMany {
        struct Body: Encodable { let ids: [UUID] }
        return try await retryingBusy {
            try await NetworkService.shared.request(
                "POST", path: club(clubId) + "/payments/confirm", body: Body(ids: ids), headers: idempotent(key)
            )
        }
    }

    /// The picture a payer attached, as bytes. Money admins only.
    static func paymentScreenshot(_ id: UUID) async throws -> Data {
        try await NetworkService.shared.data("GET", path: "/payments/\(id.uuidString)/screenshot")
    }

    /// The payer's own picture of the payment, a JPEG under 700 KB — see
    /// `PaymentScreenshot` — sent as JSON `{"image": base64}`: one brand's
    /// edge passes only JSON bodies to new paths.
    static func uploadPaymentScreenshot(_ id: UUID, jpeg: Data, key: UUID) async throws {
        let body = try JSONEncoder().encode(["image": jpeg.base64EncodedString()])
        _ = try await retryingBusy {
            try await NetworkService.shared.data(
                "POST", path: "/payments/\(id.uuidString)/screenshot",
                rawBody: body, contentType: "application/json", headers: idempotent(key)
            )
        }
    }

    /// The usual nets price and match fee, both at once; nil clears one.
    static func setUsualPrices(clubId: UUID, _ prices: UsualPrices) async throws -> PaymentSettings {
        try await NetworkService.shared.request(
            "PUT", path: club(clubId) + "/payments/settings", body: UsualPricesBody(prices: prices)
        )
    }

    // MARK: Importing a bank statement (step D)

    /// What each payment in the statement matches. Changes nothing. The body
    /// is the CSV file as text; it is sent and dropped, never written down
    /// or logged here. `empty_statement`, `unknown_statement` (no date or
    /// amount column) and `statement_too_long` (more than 5,000 lines) are
    /// 422s whose sentence says what to do.
    static func previewStatement(clubId: UUID, csv: String, network: NetworkService = .shared) async throws -> StatementPreview {
        // As JSON `{"csv": text}`: one brand's edge passes only JSON bodies to new paths.
        let bytes = try await network.data(
            "POST", path: club(clubId) + "/statement/preview",
            rawBody: try JSONEncoder().encode(["csv": csv]), contentType: "application/json"
        )
        do {
            return try FishersJSONDecoder.make().decode(StatementPreview.self, from: bytes)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Applies the chosen lines. The server reads the statement again, so the
    /// phone only picks which of its matches to apply.
    static func applyStatement(
        clubId: UUID, csv: String, lines: [String], network: NetworkService = .shared
    ) async throws -> StatementApplied {
        struct Body: Encodable { let csv: String; let lines: [String] }
        return try await network.request(
            "POST", path: club(clubId) + "/statement/apply", body: Body(csv: csv, lines: lines)
        )
    }

    /// Money admins: everybody's price group and who pays for them.
    static func moneyMembers(clubId: UUID, network: NetworkService = .shared) async throws -> [MoneyMember] {
        try await network.request("GET", path: club(clubId) + "/payments/members")
    }
}

// MARK: - Signing in with WhatsApp

/// `network` is there for the tests, which answer from a stub.
extension FishersAPI {
    static func whatsAppSignIn(network: NetworkService = .shared) async throws -> WhatsAppSignInConfig {
        try await network.request("GET", path: "/auth/whatsapp", authorized: false)
    }

    /// Errors: `bad_phone`, `whatsapp_off` (503), `slow_down` (429), `not_sent` (502).
    static func startWhatsAppSignIn(phone: String, network: NetworkService = .shared) async throws -> WhatsAppCodeSent {
        struct Body: Encodable { let phone: String }
        return try await network.request(
            "POST", path: "/auth/whatsapp/start", body: Body(phone: phone), authorized: false
        )
    }

    /// The same tokens as signing in with a password. `wrong_code`, `slow_down`.
    static func verifyWhatsAppSignIn(phone: String, code: String, network: NetworkService = .shared) async throws -> AuthTokens {
        struct Body: Encodable { let phone, code: String }
        return try await network.request(
            "POST", path: "/auth/whatsapp/verify", body: Body(phone: phone, code: code), authorized: false
        )
    }
}
