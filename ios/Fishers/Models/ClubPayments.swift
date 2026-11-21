import Foundation

// Paying the club by bank transfer. See docs/PAY_BY_BANK_TRANSFER.md §11 for
// the contract these decode; backend/api/src/routes/club_payments.rs is the
// source of truth.
//
// Every state the server names (`state`, `account_state`, a payment's
// `status`, a cost's `mode`) is decoded as a `Lenient` value rather than a
// closed enum. A new value from a newer server then reads as `.unknown` on
// this build instead of failing the whole response — which is how one unknown
// value once emptied an entire list on iOS.

// MARK: - Money

/// Integer minor units in a currency, as words on a screen.
///
/// The API never sends a float for money: `*_cents` plus an ISO code. The
/// locale is picked per currency rather than taken from the phone, so a
/// Riverside player whose phone is set to the US still reads "£1,000.00" the
/// way the club's own messages write it.
enum Money {
    static func format(_ minor: Int, _ currency: String) -> String {
        let code = currency.uppercased()
        let digits = fractionDigits(code)
        var value = Decimal(minor)
        for _ in 0..<digits { value /= 10 }
        return value.formatted(
            .currency(code: code)
                .locale(locale(for: code))
                .precision(.fractionLength(digits))
        )
    }

    /// What somebody typed — "60", "7.50", "£1,000" — as minor units, or nil
    /// when it is not an amount. More decimal places than the currency has is
    /// a typo, not something to round away quietly.
    static func parse(_ text: String, currency: String) -> Int? {
        let digits = fractionDigits(currency.uppercased())
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty, cleaned.filter({ $0 == "." }).count <= 1 else { return nil }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        let whole = parts[0].isEmpty ? "0" : String(parts[0])
        var fraction = parts.count > 1 ? String(parts[1]) : ""
        guard fraction.count <= digits, whole.count <= 9 else { return nil }
        fraction += String(repeating: "0", count: digits - fraction.count)
        guard let major = Int(whole), let minor = Int(fraction.isEmpty ? "0" : fraction) else { return nil }
        var scale = 1
        for _ in 0..<digits { scale *= 10 }
        return major * scale + minor
    }

    /// For the amount field: "7.50", no symbol, so it edits cleanly.
    static func plain(_ minor: Int, _ currency: String) -> String {
        let digits = fractionDigits(currency.uppercased())
        var scale = 1
        for _ in 0..<digits { scale *= 10 }
        guard digits > 0 else { return String(minor) }
        let fraction = String(abs(minor) % scale)
        return "\(minor / scale).\(String(repeating: "0", count: digits - fraction.count))\(fraction)"
    }

    /// What the server assumes when nothing says otherwise: an event is made
    /// in pounds unless it is told a currency.
    static let fallbackCurrency = "GBP"

    /// Above this per head, the schedule and cost forms ask "are you sure?".
    /// The server's `amount_limit` is the hard stop, well beyond it.
    static let confirmAboveMinor = 100_00

    /// How many digits the currency's minor unit has — 2 for pounds and
    /// rupees, 0 for yen — as ISO 4217 has it, which Foundation knows.
    private static func fractionDigits(_ code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.maximumFractionDigits
    }

    /// Where the currency is the home one, so its symbol and grouping read
    /// the way that country writes them ("₹1,00,000.00").
    private static func locale(for code: String) -> Locale {
        let home: Locale.Region? = switch code.lowercased() {
        case "gbp": .unitedKingdom
        case "inr": .india
        case "eur": .ireland
        case "aud": .australia
        case "nzd": .newZealand
        case "cad": .canada
        case "usd": .unitedStates
        default: nil
        }
        return home.map { Locale(languageCode: .english, languageRegion: $0) } ?? Locale.current
    }
}

// MARK: - Lenient states

/// A value the server names from a list that can grow. Unknown values are
/// kept, not thrown: `.unknown("refunded")` still renders, as something.
protocol LenientState: Codable, Hashable {
    init(raw: String)
    var raw: String { get }
}

extension LenientState {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.init(raw: (try? c.decode(String.self)) ?? "")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

/// Where one share stands: `owed`, `part_paid`, `waiting` (somebody said they
/// paid, nobody has confirmed it), `paid`, `waived`, `void`, or `covered` (a
/// pass pays for it: nothing to pay).
enum ShareState: LenientState {
    case owed, partPaid, waiting, paid, waived, void, covered
    case unknown(String)

    init(raw: String) {
        switch raw {
        case "owed": self = .owed
        case "part_paid": self = .partPaid
        case "waiting": self = .waiting
        case "paid": self = .paid
        case "waived": self = .waived
        case "void": self = .void
        case "covered": self = .covered
        default: self = .unknown(raw)
        }
    }

    var raw: String {
        switch self {
        case .owed: return "owed"
        case .partPaid: return "part_paid"
        case .waiting: return "waiting"
        case .paid: return "paid"
        case .waived: return "waived"
        case .void: return "void"
        case .covered: return "covered"
        case .unknown(let raw): return raw
        }
    }

    var label: String {
        switch self {
        case .owed: return tr("Owed")
        case .partPaid: return tr("Part paid")
        case .waiting: return tr("Waiting for the club to confirm")
        case .paid: return tr("Paid")
        case .waived: return tr("Let off")
        case .void: return tr("Cancelled")
        case .covered: return tr("Covered by your pass")
        case .unknown(let raw): return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Short, for a badge beside a name in a list.
    var shortLabel: String {
        self == .waiting ? tr("Waiting to confirm") : label
    }

    /// Money still to come from this person for this share.
    var stillOwed: Bool { self == .owed || self == .partPaid }

    /// A treasurer can let somebody off what is still open on it.
    var canBeLetOff: Bool { self == .owed || self == .partPaid || self == .waiting }
}

/// What the pay screen can show: `active` (the details), `none` (the club has
/// added none), `frozen` (being checked: don't pay), `unreadable` (the club
/// must enter them again) or `nothing_owed`.
enum PayAccountState: LenientState {
    case active, none, frozen, unreadable, nothingOwed
    case unknown(String)

    init(raw: String) {
        switch raw {
        case "active": self = .active
        case "none": self = .none
        case "frozen": self = .frozen
        case "unreadable": self = .unreadable
        case "nothing_owed": self = .nothingOwed
        default: self = .unknown(raw)
        }
    }

    var raw: String {
        switch self {
        case .active: return "active"
        case .none: return "none"
        case .frozen: return "frozen"
        case .unreadable: return "unreadable"
        case .nothingOwed: return "nothing_owed"
        case .unknown(let raw): return raw
        }
    }

    /// Why there are no details to copy. Nil when there are.
    var explanation: String? {
        switch self {
        case .active: return nil
        case .none: return tr("Your club hasn't added bank details yet. Pay your secretary directly.")
        case .frozen: return tr("The club's bank details are being checked. Don't pay yet.")
        case .unreadable: return tr("Ask your secretary to enter the bank details again.")
        case .nothingOwed: return tr("You're all paid up.")
        // A state this build has never heard of: the careful reading is
        // "don't pay into it yet".
        case .unknown: return tr("The club's bank details are being checked. Don't pay yet.")
        }
    }
}

/// A set of bank details: `active`, `pending` (waiting out its 24 hours),
/// `frozen`, `superseded` or `retired`.
enum PayoutState: LenientState {
    case active, pending, frozen, superseded, retired
    case unknown(String)

    init(raw: String) {
        switch raw {
        case "active": self = .active
        case "pending": self = .pending
        case "frozen": self = .frozen
        case "superseded": self = .superseded
        case "retired": self = .retired
        default: self = .unknown(raw)
        }
    }

    var raw: String {
        switch self {
        case .active: return "active"
        case .pending: return "pending"
        case .frozen: return "frozen"
        case .superseded: return "superseded"
        case .retired: return "retired"
        case .unknown(let raw): return raw
        }
    }
}

/// A payment: `claimed` (somebody says they paid), `confirmed`, `rejected`
/// or `cancelled`.
enum PaymentStatus: LenientState {
    case claimed, confirmed, rejected, cancelled
    case unknown(String)

    init(raw: String) {
        switch raw {
        case "claimed": self = .claimed
        case "confirmed": self = .confirmed
        case "rejected": self = .rejected
        case "cancelled": self = .cancelled
        default: self = .unknown(raw)
        }
    }

    var raw: String {
        switch self {
        case .claimed: return "claimed"
        case .confirmed: return "confirmed"
        case .rejected: return "rejected"
        case .cancelled: return "cancelled"
        case .unknown(let raw): return raw
        }
    }
}

/// How an event's cost is shared: a total split between whoever came, or the
/// same from everyone.
enum CostMode: LenientState, CaseIterable {
    case splitTotal, perPlayer
    case unknown(String)

    static var allCases: [CostMode] { [.splitTotal, .perPlayer] }

    init(raw: String) {
        switch raw {
        case "split_total": self = .splitTotal
        case "per_player": self = .perPlayer
        default: self = .unknown(raw)
        }
    }

    var raw: String {
        switch self {
        case .splitTotal: return "split_total"
        case .perPlayer: return "per_player"
        case .unknown(let raw): return raw
        }
    }

    var label: String {
        switch self {
        case .splitTotal: return tr("Split a total")
        case .perPlayer: return tr("Same for everyone")
        case .unknown(let raw): return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// "£60.00 split between whoever comes", "£5.00 each".
    func describe(_ minor: Int, _ currency: String) -> String {
        let money = Money.format(minor, currency)
        switch self {
        case .splitTotal: return tr("{amount} split between whoever comes", vars: ["amount": money])
        default: return tr("{amount} each", vars: ["amount": money])
        }
    }
}

// MARK: - Bank details

struct PayoutAccount: Codable, Identifiable, Equatable {
    let id: UUID
    let label: String
    let holderName: String
    let isPersonal: Bool
    let sortCode: String?
    let last4: String
    let state: PayoutState
    let liveFrom: Date
    let createdAt: Date?
    let createdByName: String?
    let freezeReason: String?
    /// False when the key that sealed the number is gone: enter them again.
    let readable: Bool

    enum CodingKeys: String, CodingKey {
        case id, label, last4, state, readable
        case holderName = "holder_name"
        case isPersonal = "is_personal"
        case sortCode = "sort_code"
        case liveFrom = "live_from"
        case createdAt = "created_at"
        case createdByName = "created_by_name"
        case freezeReason = "freeze_reason"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        holderName = try c.decodeIfPresent(String.self, forKey: .holderName) ?? ""
        isPersonal = try c.decodeIfPresent(Bool.self, forKey: .isPersonal) ?? false
        sortCode = try c.decodeIfPresent(String.self, forKey: .sortCode)
        last4 = try c.decodeIfPresent(String.self, forKey: .last4) ?? ""
        state = try c.decodeIfPresent(PayoutState.self, forKey: .state) ?? .unknown("")
        liveFrom = try c.decode(Date.self, forKey: .liveFrom)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        createdByName = try c.decodeIfPresent(String.self, forKey: .createdByName)
        freezeReason = try c.decodeIfPresent(String.self, forKey: .freezeReason)
        readable = try c.decodeIfPresent(Bool.self, forKey: .readable) ?? true
    }

    /// "20-00-00 · ••••9911". The full number never comes down this route.
    var masked: String {
        [sortCode, "••••\(last4)"].compactMap { $0 }.joined(separator: " · ")
    }
}

/// `GET /clubs/{id}/payout-account`, and what every change to it answers with.
struct PayoutAccounts: Codable, Equatable {
    let canManage: Bool
    let isOwner: Bool
    /// What players are shown.
    let current: PayoutAccount?
    /// A change waiting out its delay. Admins only.
    let pending: PayoutAccount?
    /// Frozen details waiting for the owner. Admins only.
    let frozen: PayoutAccount?
    let changedAt: Date?

    enum CodingKeys: String, CodingKey {
        case current, pending, frozen
        case canManage = "can_manage"
        case isOwner = "is_owner"
        case changedAt = "changed_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canManage = try c.decodeIfPresent(Bool.self, forKey: .canManage) ?? false
        isOwner = try c.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
        current = try c.decodeIfPresent(PayoutAccount.self, forKey: .current)
        pending = try c.decodeIfPresent(PayoutAccount.self, forKey: .pending)
        frozen = try c.decodeIfPresent(PayoutAccount.self, forKey: .frozen)
        changedAt = try c.decodeIfPresent(Date.self, forKey: .changedAt)
    }

    var isEmpty: Bool { current == nil && pending == nil && frozen == nil }
}

/// What the add/change form sends. The account number only ever travels in
/// this body: it is not kept, logged or echoed back.
struct NewPayoutAccount: Encodable {
    let holderName: String
    let sortCode: String
    let accountNumber: String
    let label: String?
    let isPersonal: Bool
    let password: String?

    enum CodingKeys: String, CodingKey {
        case label, password
        case holderName = "holder_name"
        case sortCode = "sort_code"
        case accountNumber = "account_number"
        case isPersonal = "is_personal"
    }
}

/// The form's own checks, before anything is sent. The server checks again
/// and its sentence wins; these only catch what a second look would.
enum BankDetailsCheck {
    static func digits(_ s: String) -> String { s.filter(\.isNumber) }

    /// The sentence to show, or nil when the form can be sent.
    static func problem(holder: String, sortCode: String, account: String, again: String) -> String? {
        if holder.trimmingCharacters(in: .whitespaces).isEmpty {
            return tr("Put the name exactly as it is on the account.")
        }
        if digits(sortCode).count != 6 {
            return tr("A sort code is six digits, like 12-34-56.")
        }
        let number = digits(account)
        if number.count != 8 && number.count != 7 {
            return tr("A UK account number is eight digits.")
        }
        if number != digits(again) {
            return tr("The two account numbers don't match. Check both against a bank card or statement.")
        }
        return nil
    }

    /// "123456" as "12-34-56" while it is typed.
    static func formatSortCode(_ raw: String) -> String {
        let d = String(digits(raw).prefix(6))
        var out = ""
        for (i, c) in d.enumerated() {
            if i > 0 && i % 2 == 0 { out.append("-") }
            out.append(c)
        }
        return out
    }
}

// MARK: - Shares and dues

/// One person's part of a bill.
///
/// Not always a session's: a monthly pass charge or a group fee is a line
/// too, with no event (`kind` says which), so `eventId` is optional.
struct ClubShare: Codable, Identifiable, Equatable {
    let id: UUID
    let billId: UUID
    let eventId: UUID?
    let title: String
    let eventStartAt: Date
    let userId: UUID?
    let guestName: String?
    let name: String
    let amountCents: Int
    let paidCents: Int
    let waitingCents: Int
    let currency: String
    let state: ShareState
    let reason: String?
    /// `event`, `pass` or `collection`; nil from servers before passes.
    let kind: String?
    /// When a pass charge or a group fee falls due, as the server wrote it.
    let dueOn: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name, currency, state, reason, kind
        case dueOn = "due_on"
        case billId = "bill_id"
        case eventId = "event_id"
        case eventStartAt = "event_start_at"
        case userId = "user_id"
        case guestName = "guest_name"
        case amountCents = "amount_cents"
        case paidCents = "paid_cents"
        case waitingCents = "waiting_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        billId = try c.decode(UUID.self, forKey: .billId)
        eventId = try? c.decodeIfPresent(UUID.self, forKey: .eventId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        eventStartAt = try c.decode(Date.self, forKey: .eventStartAt)
        userId = try c.decodeIfPresent(UUID.self, forKey: .userId)
        guestName = try c.decodeIfPresent(String.self, forKey: .guestName)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? guestName ?? ""
        amountCents = try c.decodeIfPresent(Int.self, forKey: .amountCents) ?? 0
        paidCents = try c.decodeIfPresent(Int.self, forKey: .paidCents) ?? 0
        waitingCents = try c.decodeIfPresent(Int.self, forKey: .waitingCents) ?? 0
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? Money.fallbackCurrency
        state = try c.decodeIfPresent(ShareState.self, forKey: .state) ?? .unknown("")
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        dueOn = try? c.decodeIfPresent(String.self, forKey: .dueOn)
    }

    var isGuest: Bool { userId == nil }

    /// What is still to pay on it, as the API worked it out.
    var leftCents: Int { max(0, amountCents - paidCents - waitingCents) }
}

/// What one person owes one club.
struct ClubDues: Codable, Identifiable, Equatable {
    let clubId: UUID
    let clubName: String
    let currency: String
    let owedCents: Int
    let waitingCents: Int
    let creditCents: Int
    /// Still to pay or waiting, then the most recent paid ones.
    let shares: [ClubShare]

    var id: UUID { clubId }

    enum CodingKeys: String, CodingKey {
        case currency, shares
        case clubId = "club_id"
        case clubName = "club_name"
        case owedCents = "owed_cents"
        case waitingCents = "waiting_cents"
        case creditCents = "credit_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clubId = try c.decode(UUID.self, forKey: .clubId)
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName) ?? ""
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? Money.fallbackCurrency
        owedCents = try c.decodeIfPresent(Int.self, forKey: .owedCents) ?? 0
        waitingCents = try c.decodeIfPresent(Int.self, forKey: .waitingCents) ?? 0
        creditCents = try c.decodeIfPresent(Int.self, forKey: .creditCents) ?? 0
        shares = try c.decodeIfPresent([ClubShare].self, forKey: .shares) ?? []
    }
}

/// `GET /me/dues`.
struct MyDues: Codable, Equatable {
    let clubs: [ClubDues]

    init(clubs: [ClubDues]) { self.clubs = clubs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clubs = try c.decodeIfPresent([ClubDues].self, forKey: .clubs) ?? []
    }

    enum CodingKeys: String, CodingKey { case clubs }

    /// Clubs with something still to pay, which is what the card is about.
    var owing: [ClubDues] { clubs.filter { $0.owedCents > 0 } }

    /// "£15.00", or one amount per currency when clubs differ: adding pounds
    /// to rupees would be a number that means nothing.
    var owedSummary: String? {
        let totals = Dictionary(grouping: owing, by: \.currency)
            .map { (currency: $0.key, minor: $0.value.reduce(0) { $0 + $1.owedCents }) }
            .sorted { $0.currency < $1.currency }
        guard !totals.isEmpty else { return nil }
        return totals.map { Money.format($0.minor, $0.currency) }.joined(separator: " + ")
    }
}

// MARK: - The pay screen

/// What to copy into a banking app. Here, and only here, the full account
/// number is held — in memory, for as long as the screen is open.
struct BankDetails: Codable, Equatable {
    let label: String
    let holderName: String
    let sortCode: String
    let accountNumber: String
    let isPersonal: Bool
    let changedAt: Date?
    /// What the person who added a personal account is to the club —
    /// `secretary`, `treasurer` or `owner` — for "Pay Aman Gill, the club
    /// secretary". Nil for a club account.
    let payeeRole: String?

    enum CodingKeys: String, CodingKey {
        case label
        case holderName = "holder_name"
        case sortCode = "sort_code"
        case accountNumber = "account_number"
        case isPersonal = "is_personal"
        case changedAt = "changed_at"
        case payeeRole = "payee_role"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        holderName = try c.decodeIfPresent(String.self, forKey: .holderName) ?? ""
        sortCode = try c.decodeIfPresent(String.self, forKey: .sortCode) ?? ""
        accountNumber = try c.decodeIfPresent(String.self, forKey: .accountNumber) ?? ""
        isPersonal = try c.decodeIfPresent(Bool.self, forKey: .isPersonal) ?? false
        changedAt = try c.decodeIfPresent(Date.self, forKey: .changedAt)
        payeeRole = try? c.decodeIfPresent(String.self, forKey: .payeeRole)
    }

    /// A description that cannot leak the number into a log by accident.
    var debugDescription: String { "BankDetails(\(holderName), \(sortCode), ••••\(accountNumber.suffix(4)))" }
}

/// A payment: a claim a player made, cash a treasurer recorded, a refund.
struct ClubPayment: Codable, Identifiable, Equatable {
    let id: UUID
    let clubId: UUID
    let userId: UUID?
    let guestName: String?
    let name: String
    let amountCents: Int
    let currency: String
    /// `transfer`, `cash`, `card`, `credit` or `refund`. Shown, never switched
    /// on, so a plain string is safe.
    let method: String
    let reference: String?
    let status: PaymentStatus
    let note: String?
    let createdAt: Date
    let decidedByName: String?
    let decidedAt: Date?
    let decisionReason: String?
    /// The share a pay-link payment was for, and the link it came through.
    let shareId: UUID?
    let viaLink: UUID?
    /// The payer added a picture of the payment.
    let hasScreenshot: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, currency, method, reference, status, note
        case shareId = "share_id"
        case viaLink = "via_link"
        case hasScreenshot = "has_screenshot"
        case clubId = "club_id"
        case userId = "user_id"
        case guestName = "guest_name"
        case amountCents = "amount_cents"
        case createdAt = "created_at"
        case decidedByName = "decided_by_name"
        case decidedAt = "decided_at"
        case decisionReason = "decision_reason"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        clubId = try c.decode(UUID.self, forKey: .clubId)
        userId = try c.decodeIfPresent(UUID.self, forKey: .userId)
        guestName = try c.decodeIfPresent(String.self, forKey: .guestName)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? guestName ?? ""
        amountCents = try c.decodeIfPresent(Int.self, forKey: .amountCents) ?? 0
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? Money.fallbackCurrency
        method = try c.decodeIfPresent(String.self, forKey: .method) ?? ""
        reference = try c.decodeIfPresent(String.self, forKey: .reference)
        status = try c.decodeIfPresent(PaymentStatus.self, forKey: .status) ?? .unknown("")
        note = try c.decodeIfPresent(String.self, forKey: .note)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        decidedByName = try c.decodeIfPresent(String.self, forKey: .decidedByName)
        decidedAt = try c.decodeIfPresent(Date.self, forKey: .decidedAt)
        decisionReason = try c.decodeIfPresent(String.self, forKey: .decisionReason)
        shareId = try? c.decodeIfPresent(UUID.self, forKey: .shareId)
        viaLink = try? c.decodeIfPresent(UUID.self, forKey: .viaLink)
        hasScreenshot = (try? c.decodeIfPresent(Bool.self, forKey: .hasScreenshot)) ?? false
    }

    /// Waiting for a money admin to check it.
    var isWaiting: Bool { status == .claimed }

    /// "Bank transfer", "Cash".
    var methodLabel: String {
        switch method {
        case "transfer": return tr("Bank transfer")
        case "cash": return tr("Cash")
        case "refund": return tr("Refund")
        default: return method.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// `GET /clubs/{id}/pay`.
struct PayScreen: Codable, Equatable {
    let clubId: UUID
    let clubName: String
    let currency: String
    let owedCents: Int
    let waitingCents: Int
    let creditCents: Int
    let shares: [ClubShare]
    let accountState: PayAccountState
    let account: BankDetails?
    let reference: String
    /// Your claims nobody has confirmed yet.
    let claims: [ClubPayment]

    enum CodingKeys: String, CodingKey {
        case currency, shares, account, reference, claims
        case clubId = "club_id"
        case clubName = "club_name"
        case owedCents = "owed_cents"
        case waitingCents = "waiting_cents"
        case creditCents = "credit_cents"
        case accountState = "account_state"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clubId = try c.decode(UUID.self, forKey: .clubId)
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName) ?? ""
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? Money.fallbackCurrency
        owedCents = try c.decodeIfPresent(Int.self, forKey: .owedCents) ?? 0
        waitingCents = try c.decodeIfPresent(Int.self, forKey: .waitingCents) ?? 0
        creditCents = try c.decodeIfPresent(Int.self, forKey: .creditCents) ?? 0
        shares = try c.decodeIfPresent([ClubShare].self, forKey: .shares) ?? []
        accountState = try c.decodeIfPresent(PayAccountState.self, forKey: .accountState) ?? .unknown("")
        account = try c.decodeIfPresent(BankDetails.self, forKey: .account)
        reference = try c.decodeIfPresent(String.self, forKey: .reference) ?? ""
        claims = try c.decodeIfPresent([ClubPayment].self, forKey: .claims) ?? []
    }

    /// Details to copy, only when the server says they are good to pay into.
    var payableAccount: BankDetails? { accountState == .active ? account : nil }

    /// What is still to pay, oldest first as the server lists them.
    var owedShares: [ClubShare] { shares.filter(\.state.stillOwed) }

    /// "You owe £5.00 for Friday nets.", or the total when it is for more
    /// than one thing.
    var owedHeadline: String {
        let amount = Money.format(owedCents, currency)
        if owedShares.count == 1, let title = owedShares.first?.title, !title.isEmpty {
            return tr("You owe {amount} for {what}.", vars: ["amount": amount, "what": title])
        }
        return tr("You owe {amount}.", vars: ["amount": amount])
    }

    /// Everything a banking app asks for, for "Send these details to
    /// someone" — a son or daughter who does the banking. The words are the
    /// pay screen's own.
    var detailsToSend: String? {
        guard let account = payableAccount else { return nil }
        let lines = [
            [tr("Amount"), Money.format(owedCents, currency)],
            [tr("Name"), account.holderName],
            [tr("Sort code"), account.sortCode],
            [tr("Account number"), account.accountNumber],
            [tr("What to write in the reference box"), reference],
        ]
        .map { $0.joined(separator: ": ") }
        return ([tr("Please pay {club} for me:", vars: ["club": clubName])] + lines).joined(separator: "\n")
    }
}

// MARK: - The treasurer's overview

struct PaymentSettings: Codable, Equatable {
    var autoBill: Bool
    var autoBillAfterHours: Int
    var roundSharesUp: Bool
    /// The club's usual prices: read here, and only ever written through
    /// `UsualPrices`, so a settings save can never clear them by accident.
    var usualPrices: UsualPrices

    enum CodingKeys: String, CodingKey {
        case autoBill = "auto_bill"
        case autoBillAfterHours = "auto_bill_after_hours"
        case roundSharesUp = "round_shares_up"
        case defaultNetsMode = "default_nets_mode"
        case defaultNetsCents = "default_nets_cents"
        case defaultMatchFeeCents = "default_match_fee_cents"
    }

    init(autoBill: Bool, autoBillAfterHours: Int, roundSharesUp: Bool, usualPrices: UsualPrices = UsualPrices()) {
        self.autoBill = autoBill
        self.autoBillAfterHours = autoBillAfterHours
        self.roundSharesUp = roundSharesUp
        self.usualPrices = usualPrices
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoBill = try c.decodeIfPresent(Bool.self, forKey: .autoBill) ?? false
        autoBillAfterHours = try c.decodeIfPresent(Int.self, forKey: .autoBillAfterHours) ?? 24
        roundSharesUp = try c.decodeIfPresent(Bool.self, forKey: .roundSharesUp) ?? false
        var nets: UsualPrices.Price?
        if let mode = (try? c.decodeIfPresent(CostMode.self, forKey: .defaultNetsMode)) ?? nil,
           let cents = (try? c.decodeIfPresent(Int.self, forKey: .defaultNetsCents)) ?? nil {
            nets = UsualPrices.Price(mode: mode, amountCents: cents)
        }
        usualPrices = UsualPrices(
            nets: nets,
            matchFeeCents: (try? c.decodeIfPresent(Int.self, forKey: .defaultMatchFeeCents)) ?? nil
        )
    }

    /// The three switches only. An absent price is left as it is by the
    /// server; a null one would be cleared.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(autoBill, forKey: .autoBill)
        try c.encode(autoBillAfterHours, forKey: .autoBillAfterHours)
        try c.encode(roundSharesUp, forKey: .roundSharesUp)
    }
}


/// One payer's position with the club: a member, or a guest by name.
struct MemberBalance: Codable, Identifiable, Equatable {
    let userId: UUID?
    let guestName: String?
    let name: String
    let owedCents: Int
    let waitingCents: Int
    let creditCents: Int

    var id: String { userId?.uuidString ?? "guest:\(guestName ?? name)" }

    enum CodingKeys: String, CodingKey {
        case name
        case userId = "user_id"
        case guestName = "guest_name"
        case owedCents = "owed_cents"
        case waitingCents = "waiting_cents"
        case creditCents = "credit_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeIfPresent(UUID.self, forKey: .userId)
        guestName = try c.decodeIfPresent(String.self, forKey: .guestName)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? guestName ?? ""
        owedCents = try c.decodeIfPresent(Int.self, forKey: .owedCents) ?? 0
        waitingCents = try c.decodeIfPresent(Int.self, forKey: .waitingCents) ?? 0
        creditCents = try c.decodeIfPresent(Int.self, forKey: .creditCents) ?? 0
    }
}

struct MoneyTotals: Codable, Equatable {
    let owedCents: Int
    let waitingCents: Int
    let creditCents: Int

    enum CodingKeys: String, CodingKey {
        case owedCents = "owed_cents"
        case waitingCents = "waiting_cents"
        case creditCents = "credit_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        owedCents = try c.decodeIfPresent(Int.self, forKey: .owedCents) ?? 0
        waitingCents = try c.decodeIfPresent(Int.self, forKey: .waitingCents) ?? 0
        creditCents = try c.decodeIfPresent(Int.self, forKey: .creditCents) ?? 0
    }
}

/// One recent bill, as the overview lists it.
struct BillSummary: Codable, Identifiable, Equatable {
    let billId: UUID
    /// Nil for a bill that is not a session's (a group fee, later).
    let eventId: UUID?
    let title: String
    let eventStartAt: Date
    let currency: String
    let totalCents: Int
    let paidCents: Int
    let waitingCents: Int
    let owedCents: Int
    let people: Int
    let unpaid: Int
    let waiting: Int

    var id: UUID { billId }

    enum CodingKeys: String, CodingKey {
        case title, currency, people, unpaid, waiting
        case billId = "bill_id"
        case eventId = "event_id"
        case eventStartAt = "event_start_at"
        case totalCents = "total_cents"
        case paidCents = "paid_cents"
        case waitingCents = "waiting_cents"
        case owedCents = "owed_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        billId = try c.decode(UUID.self, forKey: .billId)
        eventId = try? c.decodeIfPresent(UUID.self, forKey: .eventId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        eventStartAt = try c.decode(Date.self, forKey: .eventStartAt)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? Money.fallbackCurrency
        totalCents = try c.decodeIfPresent(Int.self, forKey: .totalCents) ?? 0
        paidCents = try c.decodeIfPresent(Int.self, forKey: .paidCents) ?? 0
        waitingCents = try c.decodeIfPresent(Int.self, forKey: .waitingCents) ?? 0
        owedCents = try c.decodeIfPresent(Int.self, forKey: .owedCents) ?? 0
        people = try c.decodeIfPresent(Int.self, forKey: .people) ?? 0
        unpaid = try c.decodeIfPresent(Int.self, forKey: .unpaid) ?? 0
        waiting = try c.decodeIfPresent(Int.self, forKey: .waiting) ?? 0
    }
}

/// `GET /clubs/{id}/money`. A 403 here is how the app learns somebody is not
/// a money admin — it is never worked out from roles on the phone.
struct MoneyOverview: Codable, Equatable {
    let currency: String
    /// Changed on screen as a stepper moves, before the save lands.
    var settings: PaymentSettings
    let account: PayoutAccounts
    let toCheck: [ClubPayment]
    let members: [MemberBalance]
    let totals: MoneyTotals?
    let bills: [BillSummary]

    enum CodingKeys: String, CodingKey {
        case currency, settings, account, members, totals, bills
        case toCheck = "to_check"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? Money.fallbackCurrency
        settings = try c.decode(PaymentSettings.self, forKey: .settings)
        account = try c.decode(PayoutAccounts.self, forKey: .account)
        toCheck = try c.decodeIfPresent([ClubPayment].self, forKey: .toCheck) ?? []
        members = try c.decodeIfPresent([MemberBalance].self, forKey: .members) ?? []
        totals = try c.decodeIfPresent(MoneyTotals.self, forKey: .totals)
        bills = try c.decodeIfPresent([BillSummary].self, forKey: .bills) ?? []
    }
}

// MARK: - An event's cost and bill

struct EventCost: Codable, Equatable {
    let mode: CostMode
    let amountCents: Int
    let currency: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case mode, currency, note
        case amountCents = "amount_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(CostMode.self, forKey: .mode) ?? .unknown("")
        amountCents = try c.decodeIfPresent(Int.self, forKey: .amountCents) ?? 0
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? Money.fallbackCurrency
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    var summary: String { mode.describe(amountCents, currency) }
}

/// The live bill on an event, with what has come in against it.
struct EventBill: Codable, Equatable {
    let id: UUID
    let totalCents: Int
    let currency: String
    /// Sent back to re-split; a stale one gets `version_conflict`.
    let version: Int
    let auto: Bool
    let note: String?
    let issuedAt: Date?
    let paidCents: Int
    let waitingCents: Int
    let owedCents: Int
    let surplusCents: Int

    enum CodingKeys: String, CodingKey {
        case id, currency, version, auto, note
        case totalCents = "total_cents"
        case issuedAt = "issued_at"
        case paidCents = "paid_cents"
        case waitingCents = "waiting_cents"
        case owedCents = "owed_cents"
        case surplusCents = "surplus_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        totalCents = try c.decodeIfPresent(Int.self, forKey: .totalCents) ?? 0
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? Money.fallbackCurrency
        version = try c.decode(Int.self, forKey: .version)
        auto = try c.decodeIfPresent(Bool.self, forKey: .auto) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note)
        issuedAt = try c.decodeIfPresent(Date.self, forKey: .issuedAt)
        paidCents = try c.decodeIfPresent(Int.self, forKey: .paidCents) ?? 0
        waitingCents = try c.decodeIfPresent(Int.self, forKey: .waitingCents) ?? 0
        owedCents = try c.decodeIfPresent(Int.self, forKey: .owedCents) ?? 0
        surplusCents = try c.decodeIfPresent(Int.self, forKey: .surplusCents) ?? 0
    }
}

/// A club member who might have come. `rsvp` is their own answer — `going`,
/// `maybe`, `not_going`, `invited`, or `not_invited` for somebody who joined
/// after it was scheduled — kept as a string because it is only grouped on.
struct BillCandidate: Codable, Identifiable, Equatable {
    let userId: UUID
    let name: String
    let rsvp: String
    let attended: Bool?
    /// Ticked to start with.
    let suggested: Bool

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case name, rsvp, attended, suggested
        case userId = "user_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(UUID.self, forKey: .userId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        rsvp = try c.decodeIfPresent(String.self, forKey: .rsvp) ?? ""
        attended = try c.decodeIfPresent(Bool.self, forKey: .attended)
        suggested = try c.decodeIfPresent(Bool.self, forKey: .suggested) ?? false
    }

    /// Somebody who was never asked: listed apart, under "Others in the club".
    var wasInvited: Bool { rsvp != "not_invited" }

    /// What they said, beside their name.
    var answer: String? {
        if attended == true { return tr("Marked as there") }
        switch rsvp {
        case "going": return tr("Said they'd come")
        case "maybe": return tr("Said maybe")
        case "not_going": return tr("Said no")
        case "invited": return tr("Didn't answer")
        default: return nil
        }
    }
}

/// `GET /events/{id}/bill`: everything the event's money section draws.
struct EventBillPage: Codable, Equatable {
    let eventId: UUID
    let clubId: UUID
    let title: String
    let endAt: Date?
    let cost: EventCost?
    let bill: EventBill?
    let canBill: Bool
    let canManageMoney: Bool
    /// Everyone's for those who run it; only your own otherwise.
    let shares: [ClubShare]
    let myShare: ClubShare?
    let candidates: [BillCandidate]
    /// Guests on the current bill, to carry into a re-split.
    let guests: [String]
    let hasPayoutAccount: Bool
    let roundSharesUp: Bool

    enum CodingKeys: String, CodingKey {
        case title, cost, bill, shares, candidates, guests
        case eventId = "event_id"
        case clubId = "club_id"
        case endAt = "end_at"
        case canBill = "can_bill"
        case canManageMoney = "can_manage_money"
        case myShare = "my_share"
        case hasPayoutAccount = "has_payout_account"
        case roundSharesUp = "round_shares_up"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try c.decode(UUID.self, forKey: .eventId)
        clubId = try c.decode(UUID.self, forKey: .clubId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
        cost = try c.decodeIfPresent(EventCost.self, forKey: .cost)
        bill = try c.decodeIfPresent(EventBill.self, forKey: .bill)
        canBill = try c.decodeIfPresent(Bool.self, forKey: .canBill) ?? false
        canManageMoney = try c.decodeIfPresent(Bool.self, forKey: .canManageMoney) ?? false
        shares = try c.decodeIfPresent([ClubShare].self, forKey: .shares) ?? []
        myShare = try c.decodeIfPresent(ClubShare.self, forKey: .myShare)
        candidates = try c.decodeIfPresent([BillCandidate].self, forKey: .candidates) ?? []
        guests = try c.decodeIfPresent([String].self, forKey: .guests) ?? []
        hasPayoutAccount = try c.decodeIfPresent(Bool.self, forKey: .hasPayoutAccount) ?? false
        roundSharesUp = try c.decodeIfPresent(Bool.self, forKey: .roundSharesUp) ?? false
    }

    /// Whether this person has anything to see here at all. A member at an
    /// event with no cost and no share of their own sees nothing.
    var isRelevant: Bool { canBill || canManageMoney || myShare != nil || (cost != nil && bill == nil) }

    /// Who to tick on "Change who came": the members on the bill now, rather
    /// than the RSVPs, which have moved on since.
    var billedMembers: Set<UUID> {
        Set(shares.filter { $0.state != .void }.compactMap(\.userId))
    }

    /// Ticked to start with on a first bill.
    var suggestedMembers: Set<UUID> {
        Set(candidates.filter(\.suggested).map(\.userId))
    }
}

/// `POST /events/{id}/bill/preview`.
struct BillPreview: Codable, Equatable {
    struct Line: Codable, Equatable {
        let userId: UUID?
        let name: String
        let amountCents: Int

        enum CodingKeys: String, CodingKey {
            case name
            case userId = "user_id"
            case amountCents = "amount_cents"
        }
    }

    let shares: [Line]
    let totalCents: Int
    let surplusCents: Int
    let currency: String

    enum CodingKeys: String, CodingKey {
        case shares, currency
        case totalCents = "total_cents"
        case surplusCents = "surplus_cents"
    }

    /// "4 people · £20.00 in all · £5.00 each", or "… · 6 pay £6.67 · 3 pay
    /// £6.66" when the pennies don't divide.
    var summary: String {
        let total = Money.format(totalCents, currency)
        let people = shares.count == 1
            ? tr("{n} person · {total} in all", vars: ["n": 1, "total": total])
            : tr("{n} people · {total} in all", vars: ["n": shares.count, "total": total])
        // Each distinct amount, the bigger first, with how many pay it.
        let groups = Dictionary(grouping: shares.map(\.amountCents), by: { $0 })
            .map { (amount: $0.key, count: $0.value.count) }
            .sorted { $0.amount > $1.amount }
        guard !groups.isEmpty else { return people }
        let parts = groups.count == 1
            ? [tr("{amount} each", vars: ["amount": Money.format(groups[0].amount, currency)])]
            : groups.map { group in
                group.count == 1
                    ? tr("{n} pays {amount}", vars: ["n": 1, "amount": Money.format(group.amount, currency)])
                    : tr("{n} pay {amount}", vars: ["n": group.count, "amount": Money.format(group.amount, currency)])
            }
        return ([people] + parts).joined(separator: " · ")
    }
}

/// What the "Who came?" screen sends, to preview and to send.
struct BillBody: Encodable, Equatable {
    var attendees: [UUID]
    var guests: [String]
    var version: Int?
    var note: String?
}

// MARK: - Errors that are not failures

extension APIError {
    /// The bank details form wants the password typed (again). Not a session
    /// failure: the person stays signed in.
    var wantsPassword: Bool { code == "reauth_required" || code == "wrong_password" }

    /// Somebody else got there first, or the screen is behind the server.
    /// Reload, and show the server's sentence as information.
    var isStale: Bool {
        guard let code else { return false }
        return [
            "version_conflict", "already_billed", "already_decided", "nothing_owed",
            "no_bill", "not_live", "not_frozen", "already_retired", "not_freezable",
        ].contains(code)
    }
}

// MARK: - Where a money notification goes

enum MoneyRoute: Hashable {
    /// The event's money section; `whoCame` opens the ticking.
    case event(UUID, whoCame: Bool)
    /// What the reader owes this club.
    case payScreen(UUID)
    /// The club's payments, for a money admin; the pay screen for anybody
    /// the server refuses.
    case overview(UUID)
}
