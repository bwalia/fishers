import Foundation

// MARK: - Passes, prices for juniors and others, group fees, paying for others

/// The calls behind docs/CLUB_PAYMENTS_V2_PLAN.md §11. Errors are the
/// server's `{error, code}`; show `error`, branch on `code`. `network` is
/// there for the tests, which answer from a stub.
extension FishersAPI {
    private static func club(_ id: UUID) -> String { "/clubs/\(id.uuidString)" }

    /// Header names are case-insensitive; the server reads it lower-case.
    private static func idempotent(_ key: UUID) -> [String: String] {
        ["idempotency-key": key.uuidString]
    }

    // MARK: Prices for juniors, students, guests

    /// Any member can read them; only money admins change them.
    static func priceTypes(clubId: UUID, network: NetworkService = .shared) async throws -> [PriceType] {
        try await network.request("GET", path: club(clubId) + "/price-types")
    }

    /// `name_taken`, `guest_type_taken` (one guest group per club).
    static func createPriceType(clubId: UUID, name: String, free: Bool, forGuests: Bool) async throws -> PriceType {
        struct Body: Encodable { let name: String; let free: Bool; let for_guests: Bool }
        return try await NetworkService.shared.request(
            "POST", path: club(clubId) + "/price-types", body: Body(name: name, free: free, for_guests: forGuests)
        )
    }

    static func updatePriceType(
        _ id: UUID, name: String? = nil, free: Bool? = nil, forGuests: Bool? = nil, archived: Bool? = nil
    ) async throws -> PriceType {
        struct Body: Encodable { let name: String?; let free: Bool?; let for_guests: Bool?; let archived: Bool? }
        return try await NetworkService.shared.request(
            "PATCH", path: "/price-types/\(id.uuidString)",
            body: Body(name: name, free: free, for_guests: forGuests, archived: archived)
        )
    }

    /// Nil puts them back on the standard price.
    static func setMemberPriceType(clubId: UUID, userId: UUID, priceTypeId: UUID?) async throws {
        struct Body: Encodable {
            let price_type_id: UUID?
            // A null has to be sent as a null, not left out.
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(price_type_id, forKey: .price_type_id)
            }
            enum CodingKeys: String, CodingKey { case price_type_id }
        }
        try await NetworkService.shared.requestVoid(
            "PUT", path: club(clubId) + "/members/\(userId.uuidString)/price-type", body: Body(price_type_id: priceTypeId)
        )
    }

    // MARK: Passes

    /// `all` includes the ones no longer offered (admins only).
    static func passes(clubId: UUID, all: Bool = false) async throws -> [PassPlan] {
        try await NetworkService.shared.request("GET", path: club(clubId) + (all ? "/passes?all=true" : "/passes"))
    }

    static func createPass(clubId: UUID, _ body: NewPassBody) async throws -> PassPlan {
        try await NetworkService.shared.request("POST", path: club(clubId) + "/passes", body: body)
    }

    /// Stop offering it, or open it to everyone to get themselves.
    static func updatePass(_ id: UUID, openToJoin: Bool? = nil, archived: Bool? = nil) async throws -> PassPlan {
        struct Body: Encodable { let open_to_join: Bool?; let archived: Bool? }
        return try await NetworkService.shared.request(
            "PATCH", path: "/passes/\(id.uuidString)", body: Body(open_to_join: openToJoin, archived: archived)
        )
    }

    static func passHolders(passId: UUID) async throws -> [PassHolder] {
        try await NetworkService.shared.request("GET", path: "/passes/\(passId.uuidString)/holders")
    }

    /// The first payment is charged at once. `already_on_pass`.
    static func addToPass(passId: UUID, userId: UUID) async throws -> PassHolder {
        struct Body: Encodable { let user_id: UUID }
        return try await NetworkService.shared.request(
            "POST", path: "/passes/\(passId.uuidString)/holders", body: Body(user_id: userId)
        )
    }

    /// `forUserId` for somebody the reader pays for. `not_open`,
    /// `not_eligible`, `not_their_payer`, `already_on_pass`.
    static func joinPass(passId: UUID, forUserId: UUID? = nil) async throws -> PassHolder {
        struct Body: Encodable { let for_user_id: UUID? }
        return try await NetworkService.shared.request(
            "POST", path: "/passes/\(passId.uuidString)/join", body: Body(for_user_id: forUserId)
        )
    }

    /// A monthly pass covers to the end of the month already charged
    /// (`ends_on`). `already_cancelled`.
    static func cancelPass(holderId: UUID) async throws -> PassHolder {
        try await NetworkService.shared.request("POST", path: "/pass-holders/\(holderId.uuidString)/cancel")
    }

    static func keepCovering(holderId: UUID, on: Bool) async throws -> PassHolder {
        struct Body: Encodable { let on: Bool }
        return try await NetworkService.shared.request(
            "PUT", path: "/pass-holders/\(holderId.uuidString)/keep-covering", body: Body(on: on)
        )
    }

    /// The reader's passes and those of anybody they pay for, every club.
    static func myPasses() async throws -> [PassHolder] {
        try await NetworkService.shared.request("GET", path: "/me/passes")
    }

    // MARK: Group fees

    /// Kept across a retry, so a second tap is the same group fee rather
    /// than everybody billed twice.
    static func createGroupFee(clubId: UUID, _ body: NewGroupFeeBody, key: UUID) async throws -> GroupFee {
        try await retryingBusy {
            try await NetworkService.shared.request(
                "POST", path: club(clubId) + "/collections", body: body, headers: idempotent(key)
            )
        }
    }

    /// The 50 newest, totals only.
    static func groupFees(clubId: UUID) async throws -> [GroupFee] {
        try await NetworkService.shared.request("GET", path: club(clubId) + "/collections")
    }

    static func groupFee(billId: UUID) async throws -> GroupFee {
        try await NetworkService.shared.request("GET", path: "/collections/\(billId.uuidString)")
    }

    /// Anything paid becomes credit, and the pay link closes. `reason_required`.
    static func cancelGroupFee(billId: UUID, reason: String) async throws -> GroupFee {
        struct Body: Encodable { let reason: String }
        return try await NetworkService.shared.request(
            "POST", path: "/collections/\(billId.uuidString)/void", body: Body(reason: reason)
        )
    }

    /// The group fee's open link, or nil. Never makes one, so it is safe to
    /// ask on opening the page.
    static func openGroupFeeLink(billId: UUID) async throws -> BillLink? {
        try await NetworkService.shared.request("GET", path: "/bills/\(billId.uuidString)/link")
    }

    /// A group fee's pay link and messages, the same shape as a session's:
    /// the open one, or a new one.
    static func groupFeeLink(billId: UUID) async throws -> BillLink {
        try await NetworkService.shared.request("POST", path: "/bills/\(billId.uuidString)/link")
    }

    static func disableGroupFeeLink(billId: UUID) async throws {
        try await NetworkService.shared.requestVoid("POST", path: "/bills/\(billId.uuidString)/link/disable")
    }

    // MARK: Paying for others

    /// Nil: they pay for themselves.
    static func setPayer(clubId: UUID, memberId: UUID, payerId: UUID?) async throws {
        struct Body: Encodable {
            let payer_id: UUID?
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(payer_id, forKey: .payer_id)
            }
            enum CodingKeys: String, CodingKey { case payer_id }
        }
        try await NetworkService.shared.requestVoid(
            "PUT", path: club(clubId) + "/members/\(memberId.uuidString)/payer", body: Body(payer_id: payerId)
        )
    }

    /// A junior with no sign-in of their own, looked after by whoever pays.
    static func addJunior(clubId: UUID, name: String, payerId: UUID) async throws -> ManagedMember {
        struct Body: Encodable { let name: String; let payer_id: UUID }
        return try await NetworkService.shared.request(
            "POST", path: club(clubId) + "/members/managed", body: Body(name: name, payer_id: payerId)
        )
    }

    /// What `for-others` takes.
    struct ForOthersBody: Encodable, Equatable {
        let method: String
        let people: [UUID]
        let include_me: Bool
        let note: String?
    }

    /// One payment for several people, under the reader's reference. The
    /// key is kept across a retry, so a second tap is the same payment.
    /// `not_their_payer`, `nothing_owed` (409).
    static func payForOthers(
        clubId: UUID, _ body: ForOthersBody, key: UUID, network: NetworkService = .shared
    ) async throws -> PaidForOthers {
        try await retryingBusy {
            try await network.request(
                "POST", path: club(clubId) + "/payments/for-others", body: body, headers: idempotent(key)
            )
        }
    }

    /// Prices on a session's cost: given, they replace the session's prices;
    /// nil leaves them as they are.
    static func setEventCost(
        eventId: UUID, mode: CostMode, amountCents: Int, note: String?, applyToSeries: Bool, prices: [TypePriceBody]?
    ) async throws {
        struct Body: Encodable {
            let mode: String
            let amount_cents: Int
            let note: String?
            let apply_to_series: Bool
            let prices: [TypePriceBody]?
        }
        try await NetworkService.shared.requestVoid(
            "PUT", path: "/events/\(eventId.uuidString)/cost",
            body: Body(mode: mode.raw, amount_cents: amountCents, note: note, apply_to_series: applyToSeries, prices: prices)
        )
    }
}
