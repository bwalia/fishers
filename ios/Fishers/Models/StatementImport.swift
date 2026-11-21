import Foundation

// Step D of club payments: importing a bank statement, and the lists a money
// admin reads after the security review. See docs/CLUB_PAYMENTS_V2_PLAN.md
// §12–13; backend/api/src/routes/statements.rs is the source of truth.
//
// The statement holds the club's other banking too. It is read into memory,
// sent, and dropped: never written to disk, never logged, and never part of
// anything here that could be printed.

// MARK: - What the server made of the statement

/// What to do with one line: `confirm` ticks somebody's "I've paid",
/// `record` marks as paid somebody who hadn't said, `check` needs a person to
/// look, `unknown` carries nobody's reference, `already` was applied before.
enum StatementAction: LenientState {
    case confirm, record, check, unknown, already
    case other(String)

    init(raw: String) {
        switch raw {
        case "confirm": self = .confirm
        case "record": self = .record
        case "check": self = .check
        case "unknown": self = .unknown
        case "already": self = .already
        default: self = .other(raw)
        }
    }

    var raw: String {
        switch self {
        case .confirm: return "confirm"
        case .record: return "record"
        case .check: return "check"
        case .unknown: return "unknown"
        case .already: return "already"
        case .other(let raw): return raw
        }
    }
}

/// Why a line needs a person: they said they paid a different amount, or two
/// members share the surname and the number was left off.
enum StatementCheckWhy: LenientState {
    case differentAmount, sharedName
    case unknown(String)

    init(raw: String) {
        switch raw {
        case "different_amount": self = .differentAmount
        case "shared_name": self = .sharedName
        default: self = .unknown(raw)
        }
    }

    var raw: String {
        switch self {
        case .differentAmount: return "different_amount"
        case .sharedName: return "shared_name"
        case .unknown(let raw): return raw
        }
    }
}

/// One payment into the account, and what it matches.
struct StatementLine: Decodable, Identifiable, Equatable {
    /// Stable for this line of this statement: sent back to apply it.
    let hash: String
    let row: Int
    /// The day, as the server writes it ("2026-11-22").
    let date: String
    let amountCents: Int
    /// What the bank wrote, so the treasurer recognises it.
    let text: String
    let action: StatementAction
    /// Whose reference it carries.
    let userId: UUID?
    let name: String?
    /// The "I've paid"s it ticks: several when one transfer paid for several
    /// people, a parent's for two juniors.
    let paymentIds: [UUID]
    let why: StatementCheckWhy?

    var id: String { hash }

    enum CodingKeys: String, CodingKey {
        case hash, row, date, text, action, name, why
        case amountCents = "amount_cents"
        case userId = "user_id"
        case paymentIds = "payment_ids"
        case paymentId = "payment_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hash = try c.decode(String.self, forKey: .hash)
        row = (try? c.decodeIfPresent(Int.self, forKey: .row)) ?? 0
        date = (try? c.decodeIfPresent(String.self, forKey: .date)) ?? ""
        amountCents = (try? c.decodeIfPresent(Int.self, forKey: .amountCents)) ?? 0
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        action = (try? c.decodeIfPresent(StatementAction.self, forKey: .action)) ?? .other("")
        userId = try? c.decodeIfPresent(UUID.self, forKey: .userId)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)).flatMap { $0.isEmpty ? nil : $0 }
        // `payment_ids` replaced the single `payment_id` after the review.
        let many = try? c.decodeIfPresent([UUID].self, forKey: .paymentIds)
        let one = try? c.decodeIfPresent(UUID.self, forKey: .paymentId)
        paymentIds = many ?? one.map { [$0] } ?? []
        why = try? c.decodeIfPresent(StatementCheckWhy.self, forKey: .why)
    }

    /// Ticked off by applying it: a confirm or a record.
    var canApply: Bool { action == .confirm || action == .record }

    /// The member's name, or what the bank wrote when nobody's matched.
    var who: String { name ?? text }

    /// "22 Nov".
    var day: String { DayDate.short(date) ?? date }

    /// Under the name in "Ticked off": what applying it does.
    var applyWords: String {
        if action == .record { return tr("Hadn't said they'd paid: recorded as paid") }
        return paymentIds.count > 1
            ? tr("Said they'd paid, for {n} people: this ticks them off", vars: ["n": paymentIds.count])
            : tr("Said they'd paid: this ticks it off")
    }

    /// Why it needs a look, in words: "Two members called SHARMA — the
    /// number was left off", "Said £6.00, sent £9.00".
    ///
    /// The line doesn't carry the surname or what they said they sent, so
    /// both are worked out from what the screen already has: the club's
    /// members, and the payments waiting to be checked.
    func whyWords(currency: String, memberNames: [String], waiting: [ClubPayment]) -> String {
        switch why {
        case .sharedName:
            guard let shared = Self.sharedSurname(in: text, memberNames: memberNames) else {
                return tr("Two members share this name — the number was left off")
            }
            return shared.count == 2
                ? tr("Two members called {name} — the number was left off", vars: ["name": shared.surname])
                : tr("{count} members called {name} — the number was left off", vars: ["count": shared.count, "name": shared.surname])
        case .differentAmount:
            let sent = Money.format(amountCents, currency)
            // What they said they sent: their transfers still to check. One
            // amount reads as one; several can't be put in a sentence.
            let said = Set(waiting.filter { $0.payerId == userId && $0.method == "transfer" && $0.isWaiting }.map(\.amountCents))
            if said.count == 1, let amount = said.first {
                return tr("Said {said}, sent {sent}", vars: ["said": Money.format(amount, currency), "sent": sent])
            }
            return tr("Sent {sent}: not what they said they'd paid", vars: ["sent": sent])
        default:
            return tr("Have a look at this one")
        }
    }

    /// The surname two or more members share that the bank's words contain,
    /// in capitals as a reference is written ("SHARMA"), and how many share
    /// it. The longest wins.
    static func sharedSurname(in text: String, memberNames: [String]) -> (surname: String, count: Int)? {
        func words(_ s: String) -> [String] {
            s.uppercased().split { !($0.isLetter || $0 == "'" || $0 == "-") }.map(String.init)
        }
        let said = Set(words(text))
        let counts = Dictionary(grouping: memberNames.compactMap { words($0).last }, by: { $0 }).mapValues(\.count)
        return counts
            .filter { $0.value > 1 && said.contains($0.key) }
            .sorted { ($0.key.count, $0.key) > ($1.key.count, $1.key) }
            .first
            .map { (surname: $0.key, count: $0.value) }
    }
}

/// `POST /clubs/{id}/statement/preview`.
struct StatementPreview: Decodable, Equatable {
    let currency: String
    let lines: [StatementLine]

    enum CodingKeys: String, CodingKey { case currency, lines }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? Money.fallbackCurrency
        lines = (try? c.decodeIfPresent([StatementLine].self, forKey: .lines)) ?? []
    }

    /// "Ticked off": ready to apply, each ticked to start with.
    var toApply: [StatementLine] { lines.filter(\.canApply) }
    /// "Needs a look".
    var toCheck: [StatementLine] { lines.filter { $0.action == .check } }
    /// "Not recognised": nobody's reference, or something this build can't
    /// name — never applied, so never in the way.
    var notRecognised: [StatementLine] {
        lines.filter {
            switch $0.action {
            case .unknown, .other: return true
            default: return false
            }
        }
    }
    /// "Already done": applied from this statement before.
    var alreadyDone: [StatementLine] { lines.filter { $0.action == .already } }

    /// What "Apply" sends for the lines still ticked, in the statement's order.
    func hashes(ticked: Set<String>) -> [String] {
        toApply.map(\.hash).filter(ticked.contains)
    }
}

/// `POST /clubs/{id}/statement/apply`.
struct StatementApplied: Decodable, Equatable {
    /// "I've paid"s ticked: one line can tick several.
    let confirmed: Int
    /// Payments recorded for people who hadn't said.
    let recorded: Int
    /// Asked for, but somebody dealt with it meanwhile.
    let skipped: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        confirmed = (try? c.decodeIfPresent(Int.self, forKey: .confirmed)) ?? 0
        recorded = (try? c.decodeIfPresent(Int.self, forKey: .recorded)) ?? 0
        skipped = (try? c.decodeIfPresent(Int.self, forKey: .skipped)) ?? 0
    }

    enum CodingKeys: String, CodingKey { case confirmed, recorded, skipped }

    /// "8 payments ticked off."
    var headline: String {
        let n = confirmed + recorded
        return n == 1 ? tr("1 payment ticked off.") : tr("{n} payments ticked off.", vars: ["n": n])
    }

    /// Said when some had changed since the preview. Nil otherwise.
    var skippedWords: String? {
        guard skipped > 0 else { return nil }
        return skipped == 1
            ? tr("{n} had changed since, so it was left alone.", vars: ["n": 1])
            : tr("{n} had changed since, so they were left alone.", vars: ["n": skipped])
    }
}

/// The file a bank exports, as text. Banks write UTF-8, or the Windows
/// character set an older export uses for "£", or now and then UTF-16.
enum StatementFile {
    /// Far beyond 5,000 lines of any bank's export; more is the wrong file.
    static let maxBytes = 2_000_000

    /// The sentence for a statement that can't be used: the app's own words
    /// for the three the server names (§12), translated, and the server's
    /// sentence for anything else.
    static func problem(_ error: Error) -> String {
        switch (error as? APIError)?.code {
        case "empty_statement": return tr("That file is empty. Download the statement from your bank again.")
        case "unknown_statement": return unreadable
        case "statement_too_long": return tooLong
        default: return paymentMessage(error)
        }
    }

    static var unreadable: String {
        tr("That doesn't look like a bank statement. Download it from your bank as a CSV file, then try again.")
    }

    static var tooLong: String { tr("That statement is too long. Download a shorter one: a month or two.") }

    static func text(from data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
    }
}

// MARK: - Prices and who pays, for money admins

/// `GET /clubs/{id}/payments/members`: each member's price group and who
/// pays for them, as the server has it.
struct MoneyMember: Decodable, Identifiable, Equatable {
    let userId: UUID
    let name: String
    /// Nil: the standard price.
    let priceTypeId: UUID?
    /// Nil: they pay for themselves.
    let payerId: UUID?
    let payerName: String?
    /// No sign-in of their own: a junior added by name.
    let managed: Bool

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case name, managed
        case userId = "user_id"
        case priceTypeId = "price_type_id"
        case payerId = "payer_id"
        case payerName = "payer_name"
    }

    init(userId: UUID, name: String, priceTypeId: UUID? = nil, payerId: UUID? = nil, payerName: String? = nil, managed: Bool = false) {
        self.userId = userId
        self.name = name
        self.priceTypeId = priceTypeId
        self.payerId = payerId
        self.payerName = payerName
        self.managed = managed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(UUID.self, forKey: .userId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        priceTypeId = try? c.decodeIfPresent(UUID.self, forKey: .priceTypeId)
        payerId = try? c.decodeIfPresent(UUID.self, forKey: .payerId)
        payerName = try? c.decodeIfPresent(String.self, forKey: .payerName)
        managed = (try? c.decodeIfPresent(Bool.self, forKey: .managed)) ?? false
    }
}

// MARK: - I'm paying for friends too

/// One payment for the reader and the friends they've ticked: how much in
/// all, and who for.
struct FriendsPayment: Equatable {
    /// The reader's own dues, paid in the same go.
    let mineCents: Int
    let friends: [FriendOwing]
    let currency: String

    var includeMe: Bool { mineCents > 0 }
    var totalCents: Int { mineCents + friends.reduce(0) { $0 + $1.owedCents } }

    /// "you, Jas and Arjun".
    var whoWords: String {
        let first = friends.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
        let you = tr("you")
        let names = (includeMe ? [you] : []) + first
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return tr("{a} and {b}", vars: ["a": names.dropLast().joined(separator: ", "), "b": last])
    }

    /// "One payment of £25.00 for you, Jas and Arjun, with one reference."
    var sentence: String {
        tr("One payment of {amount} for {who}, with one reference.", vars: [
            "amount": Money.format(totalCents, currency), "who": whoWords,
        ])
    }
}
