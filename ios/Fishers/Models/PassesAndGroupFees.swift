import Foundation

// Steps B and C of club payments: passes, prices for juniors and others,
// group fees, and paying for other people. See docs/CLUB_PAYMENTS_V2_PLAN.md
// §11; backend/api/src/routes/passes.rs is the source of truth.
//
// Words: a player reads "pass", "group fee", "covered by your pass" and "pays
// for" — never "subscription", "collection", "holder", "dependent" or "price
// type". A secretary reads "Prices for juniors, students…".

// MARK: - Days

/// A day as the server writes it ("2026-12-06"): a due date, the end of a
/// pass. Read in the phone's own time zone, so the 6th stays the 6th.
enum DayDate {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return formatter.date(from: String(raw.prefix(10)))
    }

    /// What the server takes for a day.
    static func string(_ date: Date) -> String { formatter.string(from: date) }

    /// "6 Dec".
    static func short(_ raw: String?) -> String? {
        date(raw).map { $0.formatted(.dateTime.day().month(.abbreviated)) }
    }

    /// Before `today`, by the day rather than the second.
    static func isPast(_ raw: String?, today: Date = .now) -> Bool {
        guard let day = date(raw) else { return false }
        return day < Calendar.current.startOfDay(for: today)
    }
}

// MARK: - Prices for juniors, students, guests

/// A group a club prices differently: Junior, Student, Coach (free), Guest.
/// Shown to a secretary as "Prices for juniors, students…", never by the
/// API's name for it.
struct PriceType: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let free: Bool
    let forGuests: Bool
    let sortOrder: Int
    let archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, free
        case forGuests = "for_guests"
        case sortOrder = "sort_order"
        case archivedAt = "archived_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        free = (try? c.decodeIfPresent(Bool.self, forKey: .free)) ?? false
        forGuests = (try? c.decodeIfPresent(Bool.self, forKey: .forGuests)) ?? false
        sortOrder = (try? c.decodeIfPresent(Int.self, forKey: .sortOrder)) ?? 0
        archivedAt = try? c.decodeIfPresent(Date.self, forKey: .archivedAt)
    }

    var isArchived: Bool { archivedAt != nil }

    /// "Free", "For guests", both, or nothing.
    var tags: [String] {
        var out: [String] = []
        if free { out.append(tr("Free")) }
        if forGuests { out.append(tr("For guests")) }
        return out
    }
}

extension Array where Element == PriceType {
    /// Still in use, in the club's order.
    var inUse: [PriceType] { filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder } }

    /// The juniors' group, for the templates and "Add a junior": the one the
    /// club named that way, whatever the case.
    var junior: PriceType? { inUse.first { $0.name.lowercased().contains("junior") && !$0.forGuests } }
}

/// One group's price for one session, where it differs from the standard.
struct TypePrice: Codable, Equatable, Identifiable {
    let priceTypeId: UUID
    let name: String
    let amountCents: Int

    var id: UUID { priceTypeId }

    enum CodingKeys: String, CodingKey {
        case name
        case priceTypeId = "price_type_id"
        case amountCents = "amount_cents"
    }

    init(priceTypeId: UUID, name: String, amountCents: Int) {
        self.priceTypeId = priceTypeId
        self.name = name
        self.amountCents = amountCents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        priceTypeId = try c.decode(UUID.self, forKey: .priceTypeId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        amountCents = (try? c.decodeIfPresent(Int.self, forKey: .amountCents)) ?? 0
    }

    /// "Junior £3.00", or "Junior free".
    func describe(_ currency: String) -> String {
        amountCents == 0
            ? tr("{name} free", vars: ["name": name])
            : [name, Money.format(amountCents, currency)].joined(separator: " ")
    }
}

/// What `PUT /events/{id}/cost` takes for each group's price.
struct TypePriceBody: Encodable, Equatable {
    let priceTypeId: UUID
    let amountCents: Int

    enum CodingKeys: String, CodingKey {
        case priceTypeId = "price_type_id"
        case amountCents = "amount_cents"
    }
}

/// "Different price for juniors?" on a session's cost, as it is typed.
struct SessionPricesDraft: Equatable {
    var on: Bool
    /// What is typed for each group; empty means the usual price.
    var typed: [UUID: String]

    init(existing: [TypePrice], currency: String) {
        on = !existing.isEmpty
        typed = Dictionary(existing.map { ($0.priceTypeId, Money.plain($0.amountCents, currency)) }, uniquingKeysWith: { a, _ in a })
    }

    /// What to send with the cost: nil leaves the session's prices as they
    /// are, an empty list clears them. A problem names the price that can't
    /// be read. Prices are for a cost per player only; a total is split evenly.
    func body(mode: CostMode, groups: [PriceType], existing: [TypePrice], currency: String) -> (prices: [TypePriceBody]?, problem: String?) {
        // No groups to show (none, or not loaded): the question was never
        // asked, so nothing changes. A split total drops them on the server.
        guard mode == .perPlayer, !groups.isEmpty else { return (nil, nil) }
        guard on else { return (existing.isEmpty ? nil : [], nil) }
        var out: [TypePriceBody] = []
        for group in groups {
            let text = (typed[group.id] ?? "").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            guard let cents = Money.parse(text, currency: currency) else {
                return (nil, tr("Check the price for {group}.", vars: ["group": group.name]))
            }
            out.append(TypePriceBody(priceTypeId: group.id, amountCents: cents))
        }
        return (out, nil)
    }
}

// MARK: - Passes

/// How a pass is paid: `once`, `monthly` (by the player's own standing
/// order) or `instalments` (the price in equal monthly parts).
enum PassBilling: LenientState {
    case once, monthly, instalments
    case unknown(String)

    init(raw: String) {
        switch raw {
        case "once": self = .once
        case "monthly": self = .monthly
        case "instalments": self = .instalments
        default: self = .unknown(raw)
        }
    }

    var raw: String {
        switch self {
        case .once: return "once"
        case .monthly: return "monthly"
        case .instalments: return "instalments"
        case .unknown(let raw): return raw
        }
    }
}

/// `up_to_date`, `behind` (a payment late, still covering) or `suspended`
/// (not covering until paid up).
enum PassStanding: LenientState {
    case upToDate, behind, suspended
    case unknown(String)

    init(raw: String) {
        switch raw {
        case "up_to_date": self = .upToDate
        case "behind": self = .behind
        case "suspended": self = .suspended
        default: self = .unknown(raw)
        }
    }

    var raw: String {
        switch self {
        case .upToDate: return "up_to_date"
        case .behind: return "behind"
        case .suspended: return "suspended"
        case .unknown(let raw): return raw
        }
    }
}

/// A kind of session a pass can cover.
enum SessionKind: LenientState, CaseIterable {
    case nets, training, friendly, leagueMatch, tournament, social
    case unknown(String)

    static var allCases: [SessionKind] { [.nets, .training, .friendly, .leagueMatch, .tournament, .social] }

    init(raw: String) {
        switch raw {
        case "nets": self = .nets
        case "training": self = .training
        case "friendly": self = .friendly
        case "league_match": self = .leagueMatch
        case "tournament": self = .tournament
        case "social": self = .social
        default: self = .unknown(raw)
        }
    }

    var raw: String {
        switch self {
        case .nets: return "nets"
        case .training: return "training"
        case .friendly: return "friendly"
        case .leagueMatch: return "league_match"
        case .tournament: return "tournament"
        case .social: return "social"
        case .unknown(let raw): return raw
        }
    }

    /// For a switch: "Nets", "League matches".
    var title: String {
        switch self {
        case .nets: return tr("Nets")
        case .training: return tr("Training")
        case .friendly: return tr("Friendlies")
        case .leagueMatch: return tr("League matches")
        case .tournament: return tr("Tournaments")
        case .social: return tr("Social events")
        case .unknown(let raw): return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// "nets", "nets and training", "nets, training and league matches".
    static func list(_ kinds: [SessionKind]) -> String {
        let words = kinds.map { $0.title.lowercased() }
        guard let last = words.last else { return "" }
        guard words.count > 1 else { return last }
        return tr("{a} and {b}", vars: ["a": words.dropLast().joined(separator: ", "), "b": last])
    }

    /// What a pass covers, in one sentence, for an offer and for a pass
    /// somebody has: "Covers nets and training.", "Covers 10 sessions of
    /// nets.", "Covers nets until 31 Mar.", or what a plain membership is.
    static func coverWords(_ covers: [SessionKind], sessions: Int?, validUntil: String?) -> String {
        let what = list(covers)
        if covers.isEmpty {
            if let until = DayDate.short(validUntil) {
                return tr("A membership, until {date}. Sessions are paid as usual.", vars: ["date": until])
            }
            return tr("A membership. Sessions are paid as usual.")
        }
        if let sessions {
            return sessions == 1
                ? tr("Covers 1 session of {what}.", vars: ["what": what])
                : tr("Covers {n} sessions of {what}.", vars: ["n": sessions, "what": what])
        }
        if let until = DayDate.short(validUntil) {
            return tr("Covers {what} until {date}.", vars: ["what": what, "date": until])
        }
        return tr("Covers {what}.", vars: ["what": what])
    }
}

/// What a pass costs and covers. `mine` is the reader's own running pass on
/// it, if they have one.
struct PassPlan: Decodable, Identifiable, Equatable {
    let id: UUID
    let clubId: UUID
    let name: String
    let priceCents: Int
    let currency: String
    let billing: PassBilling
    let instalments: Int?
    let covers: [SessionKind]
    let teamId: UUID?
    /// The last day it covers, for a pass that runs to a date.
    let validUntil: String?
    /// How many sessions a card covers.
    let sessions: Int?
    /// Only members in this group can have it.
    let priceTypeId: UUID?
    let openToJoin: Bool
    let archivedAt: Date?
    /// One payment: the price, or one part of it.
    let chargeCents: Int
    /// How many are on it now.
    let holders: Int
    let mine: PassHolder?

    enum CodingKeys: String, CodingKey {
        case id, name, currency, billing, instalments, covers, sessions, holders, mine
        case clubId = "club_id"
        case priceCents = "price_cents"
        case teamId = "team_id"
        case validUntil = "valid_until"
        case priceTypeId = "price_type_id"
        case openToJoin = "open_to_join"
        case archivedAt = "archived_at"
        case chargeCents = "charge_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        clubId = try c.decode(UUID.self, forKey: .clubId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        priceCents = (try? c.decodeIfPresent(Int.self, forKey: .priceCents)) ?? 0
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? Money.fallbackCurrency
        billing = try c.decodeIfPresent(PassBilling.self, forKey: .billing) ?? .unknown("")
        instalments = try? c.decodeIfPresent(Int.self, forKey: .instalments)
        covers = (try? c.decodeIfPresent([SessionKind].self, forKey: .covers)) ?? []
        teamId = try? c.decodeIfPresent(UUID.self, forKey: .teamId)
        validUntil = try? c.decodeIfPresent(String.self, forKey: .validUntil)
        sessions = try? c.decodeIfPresent(Int.self, forKey: .sessions)
        priceTypeId = try? c.decodeIfPresent(UUID.self, forKey: .priceTypeId)
        openToJoin = (try? c.decodeIfPresent(Bool.self, forKey: .openToJoin)) ?? false
        archivedAt = try? c.decodeIfPresent(Date.self, forKey: .archivedAt)
        chargeCents = (try? c.decodeIfPresent(Int.self, forKey: .chargeCents)) ?? priceCents
        holders = (try? c.decodeIfPresent(Int.self, forKey: .holders)) ?? 0
        // A holder this build can't read is no reason to lose the whole pass.
        mine = try? c.decodeIfPresent(PassHolder.self, forKey: .mine)
    }

    var isArchived: Bool { archivedAt != nil }

    /// "£20.00 a month", "£60.00", "£120.00, in 3 monthly parts of £40.00".
    var priceWords: String {
        let price = Money.format(priceCents, currency)
        switch billing {
        case .monthly:
            return tr("{amount} a month", vars: ["amount": price])
        case .instalments:
            return tr("{amount}, in {n} monthly parts of {part}", vars: [
                "amount": price, "n": instalments ?? 1, "part": Money.format(chargeCents, currency),
            ])
        default:
            return price
        }
    }

    /// "Covers nets and training.", "Covers 10 sessions of nets.", "Covers
    /// nets until 31 Mar.", or what a plain membership is.
    var coverWords: String {
        SessionKind.coverWords(covers, sessions: sessions, validUntil: validUntil)
    }

    /// "Only for Junior members."
    func onlyFor(_ groups: [PriceType]) -> String? {
        guard let id = priceTypeId else { return nil }
        let name = groups.first { $0.id == id }?.name ?? tr("some")
        return tr("Only for {group} members.", vars: ["group": name])
    }

    /// Asked before a player gets it.
    var joinQuestion: String { tr("Get {pass}?", vars: ["pass": name]) }

    /// What getting it means, in one sentence.
    var joinExplanation: String {
        let charge = Money.format(chargeCents, currency)
        switch billing {
        case .monthly:
            return tr("{amount} a month. You set up a standing order in your banking app, and it pays itself.", vars: ["amount": charge])
        case .instalments:
            return tr("{amount} now, then each month until it's paid.", vars: ["amount": charge])
        default:
            return tr("Pay {amount} once, and you're covered.", vars: ["amount": charge])
        }
    }

    /// Said once they're on it: the next step.
    var joinedNotice: String {
        billing == .monthly
            ? tr("You're on {pass}. Set up the standing order below, and it pays itself.", vars: ["pass": name])
            : tr("You're on {pass}. Pay what's owed above, and you're covered.", vars: ["pass": name])
    }
}

/// Exactly what to type into a banking app for a monthly pass.
struct StandingOrder: Decodable, Equatable {
    let amountCents: Int
    /// Always "month" for now.
    let every: String
    let firstPaymentOn: String
    let reference: String

    enum CodingKeys: String, CodingKey {
        case every, reference
        case amountCents = "amount_cents"
        case firstPaymentOn = "first_payment_on"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amountCents = (try? c.decodeIfPresent(Int.self, forKey: .amountCents)) ?? 0
        every = (try? c.decodeIfPresent(String.self, forKey: .every)) ?? "month"
        firstPaymentOn = (try? c.decodeIfPresent(String.self, forKey: .firstPaymentOn)) ?? ""
        reference = (try? c.decodeIfPresent(String.self, forKey: .reference)) ?? ""
    }

    /// "Every month".
    var howOften: String { every == "month" ? tr("Every month") : every.capitalized }

    /// For "Send to someone who pays for me": everything the banking app
    /// asks for, in the pay screen's words. The bank details are there only
    /// when the club's pay screen shows them.
    func detailsToSend(club: String, currency: String, account: BankDetails?) -> String {
        var lines: [[String]] = []
        if let account {
            lines += [
                [tr("Who to pay"), account.holderName],
                [tr("Sort code"), account.sortCode],
                [tr("Account number"), account.accountNumber],
            ]
        }
        lines += [
            [tr("Amount"), Money.format(amountCents, currency)],
            [tr("How often"), howOften],
            [tr("First payment"), DayDate.short(firstPaymentOn) ?? firstPaymentOn],
            [tr("What to write in the reference box"), reference],
        ]
        let head = tr("Please set up a standing order to {club} for me:", vars: ["club": club])
        return ([head] + lines.map { $0.joined(separator: ": ") }).joined(separator: "\n")
    }
}

/// Somebody on a pass. From `/me/passes` it also carries the club, the
/// charge and, for a monthly pass, the standing order.
struct PassHolder: Decodable, Identifiable, Equatable {
    let id: UUID
    let planId: UUID
    let clubId: UUID
    let userId: UUID
    let name: String
    let startedOn: String?
    /// The last day it covers, once cancelled.
    let endsOn: String?
    let cancelledAt: Date?
    /// A secretary's override: covering however far behind.
    let keepCovering: Bool
    let planName: String
    let billing: PassBilling
    let standing: PassStanding
    let sessionsLeft: Int?
    /// Covers sessions today.
    let running: Bool
    let nextChargeOn: String?
    let clubName: String?
    let chargeCents: Int?
    let currency: String?
    let standingOrder: StandingOrder?
    /// The pass's own terms, from `/me/passes`: what it covers, its last
    /// day, and how many sessions a card is for.
    let covers: [SessionKind]
    let validUntil: String?
    let sessions: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, billing, standing, running, currency, covers, sessions
        case validUntil = "valid_until"
        case planId = "plan_id"
        case clubId = "club_id"
        case userId = "user_id"
        case startedOn = "started_on"
        case endsOn = "ends_on"
        case cancelledAt = "cancelled_at"
        case keepCovering = "keep_covering"
        case planName = "plan_name"
        case sessionsLeft = "sessions_left"
        case nextChargeOn = "next_charge_on"
        case clubName = "club_name"
        case chargeCents = "charge_cents"
        case standingOrder = "standing_order"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        planId = try c.decode(UUID.self, forKey: .planId)
        clubId = try c.decode(UUID.self, forKey: .clubId)
        userId = try c.decode(UUID.self, forKey: .userId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        startedOn = try? c.decodeIfPresent(String.self, forKey: .startedOn)
        endsOn = try? c.decodeIfPresent(String.self, forKey: .endsOn)
        cancelledAt = try? c.decodeIfPresent(Date.self, forKey: .cancelledAt)
        keepCovering = (try? c.decodeIfPresent(Bool.self, forKey: .keepCovering)) ?? false
        planName = try c.decodeIfPresent(String.self, forKey: .planName) ?? ""
        billing = try c.decodeIfPresent(PassBilling.self, forKey: .billing) ?? .unknown("")
        standing = try c.decodeIfPresent(PassStanding.self, forKey: .standing) ?? .unknown("")
        sessionsLeft = try? c.decodeIfPresent(Int.self, forKey: .sessionsLeft)
        running = (try? c.decodeIfPresent(Bool.self, forKey: .running)) ?? false
        nextChargeOn = try? c.decodeIfPresent(String.self, forKey: .nextChargeOn)
        clubName = try? c.decodeIfPresent(String.self, forKey: .clubName)
        chargeCents = try? c.decodeIfPresent(Int.self, forKey: .chargeCents)
        currency = try? c.decodeIfPresent(String.self, forKey: .currency)
        standingOrder = try? c.decodeIfPresent(StandingOrder.self, forKey: .standingOrder)
        covers = (try? c.decodeIfPresent([SessionKind].self, forKey: .covers)) ?? []
        validUntil = try? c.decodeIfPresent(String.self, forKey: .validUntil)
        sessions = try? c.decodeIfPresent(Int.self, forKey: .sessions)
    }

    var isCancelled: Bool { cancelledAt != nil }

    /// "Covers nets and training." Nil from a server that doesn't say, or
    /// from a list (a pass's own holders) that doesn't carry the terms.
    var coverWords: String? {
        guard !covers.isEmpty || validUntil != nil || sessions != nil else { return nil }
        return SessionKind.coverWords(covers, sessions: sessions, validUntil: validUntil)
    }

    /// A charge for this pass still to pay, among `shares` (the pay screen's,
    /// or the dues of whoever the reader pays for). A monthly pass's standing
    /// order pays it, so it mustn't be paid by hand as well.
    func hasChargeOwed(in shares: [ClubShare]) -> Bool {
        shares.contains { share in
            share.kind == "pass" && share.state.stillOwed
                && (share.userId == nil || share.userId == userId)
                && share.title.hasPrefix(planName)
        }
    }

    /// Where the pass stands, for the person it's for (or whoever pays for
    /// them): "Covered until 31 Mar", "3 sessions left", "A payment is late:
    /// pay it to stay covered".
    func standingWords(today: Date = .now) -> String {
        if isCancelled {
            if let end = DayDate.short(endsOn), !DayDate.isPast(endsOn, today: today) {
                return tr("Cancelled. It covers you until {date}.", vars: ["date": end])
            }
            return tr("Cancelled.")
        }
        switch standing {
        case .suspended:
            return tr("Payments are missing, so it isn't covering sessions. Pay what you owe to start again.")
        case .behind:
            return tr("A payment is late: pay it to stay covered.")
        default:
            break
        }
        if let left = sessionsLeft {
            switch left {
            case 0: return tr("All its sessions are used. Your next sessions are paid as usual.")
            case 1: return tr("1 session left")
            default: return tr("{n} sessions left", vars: ["n": left])
            }
        }
        if !running, let start = DayDate.date(startedOn), start > Calendar.current.startOfDay(for: today) {
            return tr("Starts {date}.", vars: ["date": start.formatted(.dateTime.day().month(.abbreviated))])
        }
        if let until = DayDate.short(validUntil) {
            return tr("Covered until {date}.", vars: ["date": until])
        }
        if billing == .monthly || billing == .instalments, let next = DayDate.short(nextChargeOn) {
            return tr("Covered. Next payment {date}.", vars: ["date": next])
        }
        return running ? tr("Covered.") : tr("Not covering sessions at the moment.")
    }

    /// Whether the standing words are good news.
    var isInGoodStanding: Bool {
        !isCancelled && running && standing != .behind && standing != .suspended
    }

    /// For a secretary's list: "Up to date", "A payment is late", "Payments
    /// missing: not covering".
    var adminStanding: String {
        var parts: [String] = []
        if isCancelled {
            if let end = DayDate.short(endsOn), !DayDate.isPast(endsOn) {
                parts.append(tr("Cancelled, covers until {date}", vars: ["date": end]))
            } else {
                parts.append(tr("Cancelled"))
            }
        } else {
            switch standing {
            case .upToDate: parts.append(tr("Up to date"))
            case .behind: parts.append(tr("A payment is late"))
            case .suspended:
                parts.append(keepCovering ? tr("Payments missing, still covered") : tr("Payments missing: not covering"))
            case .unknown(let raw): parts.append(raw.replacingOccurrences(of: "_", with: " ").capitalized)
            }
        }
        if let left = sessionsLeft, !isCancelled {
            parts.append(left == 1 ? tr("1 session left") : tr("{n} sessions left", vars: ["n": left]))
        }
        return parts.joined(separator: " · ")
    }

    /// Asked before cancelling.
    func cancelQuestion(forSomeoneElse: Bool) -> String {
        forSomeoneElse
            ? tr("Cancel {pass} for {name}?", vars: ["pass": planName, "name": name])
            : tr("Cancel {pass}?", vars: ["pass": planName])
    }

    /// What cancelling does, and for a monthly pass, the bank's side.
    var cancelWarning: String {
        billing == .monthly
            ? tr("It keeps covering to the end of the month already paid for. Cancel the standing order in your banking app too, or it keeps paying the club.")
            : tr("It stops covering today. Anything already charged stays as it is.")
    }

    /// Said after cancelling.
    var cancelledNotice: String {
        if billing == .monthly {
            if let end = DayDate.short(endsOn) {
                return tr("Cancelled. It covers until {date}. Now cancel the standing order in your banking app too.", vars: ["date": end])
            }
            return tr("Cancelled. Now cancel the standing order in your banking app too.")
        }
        return tr("Cancelled.")
    }
}

/// `POST /clubs/{id}/passes`: what a new pass is.
struct NewPassBody: Encodable, Equatable {
    let name: String
    let priceCents: Int
    let billing: String
    let instalments: Int?
    let covers: [String]
    let validUntil: String?
    let sessions: Int?
    let priceTypeId: UUID?
    let openToJoin: Bool

    enum CodingKeys: String, CodingKey {
        case name, billing, instalments, covers, sessions
        case priceCents = "price_cents"
        case validUntil = "valid_until"
        case priceTypeId = "price_type_id"
        case openToJoin = "open_to_join"
    }
}

/// The new-pass form, as it is filled in.
struct PassDraft: Equatable {
    enum Length: Hashable { case noEnd, until, sessions }

    var name = ""
    var amount = ""
    var billing: PassBilling = .once
    var parts = 3
    var covers: Set<SessionKind> = [.nets]
    var length: Length = .noEnd
    var validUntil = Date.now
    var sessions = 10
    var priceTypeId: UUID?
    var openToJoin = true

    /// The sentence to show, or nil when it can be saved.
    func problem(currency: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tr("Give the pass a name, like Winter nets pass.")
        }
        if (Money.parse(amount, currency: currency) ?? 0) <= 0 {
            return tr("Put in what the pass costs.")
        }
        return nil
    }

    /// What to send, or nil while something's missing. A monthly pass runs
    /// until it's cancelled, so it never has an end date or a session count.
    func body(currency: String) -> NewPassBody? {
        guard problem(currency: currency) == nil, let cents = Money.parse(amount, currency: currency) else { return nil }
        let monthly = billing == .monthly
        return NewPassBody(
            name: name.split(whereSeparator: \.isWhitespace).joined(separator: " "),
            priceCents: cents,
            billing: billing.raw,
            instalments: billing == .instalments ? min(max(parts, 2), 12) : nil,
            covers: SessionKind.allCases.filter { covers.contains($0) }.map(\.raw),
            validUntil: !monthly && length == .until ? DayDate.string(validUntil) : nil,
            sessions: !monthly && length == .sessions ? min(max(sessions, 1), 500) : nil,
            priceTypeId: priceTypeId,
            openToJoin: openToJoin
        )
    }
}

/// Where a secretary starts: tick a template, change the numbers.
enum PassTemplate: String, CaseIterable, Identifiable {
    case winterNets, tenSessions, monthlyNets, seasonMembership, juniorMembership

    var id: String { rawValue }

    var title: String {
        switch self {
        case .winterNets: return tr("Winter nets pass")
        case .tenSessions: return tr("10-session nets card")
        case .monthlyNets: return tr("Monthly nets")
        case .seasonMembership: return tr("Season membership")
        case .juniorMembership: return tr("Junior membership")
        }
    }

    var blurb: String {
        switch self {
        case .winterNets: return tr("Paid once, covers nets until the end of March.")
        case .tenSessions: return tr("Paid once, covers the next 10 nets sessions.")
        case .monthlyNets: return tr("Paid every month by standing order, covers nets.")
        case .seasonMembership: return tr("Membership, paid in 3 parts.")
        case .juniorMembership: return tr("Membership for juniors only.")
        }
    }

    var symbol: String {
        switch self {
        case .winterNets: return "snowflake"
        case .tenSessions: return "rectangle.stack"
        case .monthlyNets: return "calendar"
        case .seasonMembership: return "person.crop.rectangle"
        case .juniorMembership: return "figure.child"
        }
    }

    /// The form, filled in. The amounts are the plan's examples, to change.
    func draft(currency: String, groups: [PriceType], today: Date = .now) -> PassDraft {
        var d = PassDraft()
        d.name = title
        func amount(_ major: Int) -> String { Money.plain(major * 100, currency) }
        switch self {
        case .winterNets:
            d.amount = amount(60)
            d.covers = [.nets]
            d.length = .until
            d.validUntil = Self.endOfMarch(after: today)
        case .tenSessions:
            d.amount = amount(40)
            d.covers = [.nets]
            d.length = .sessions
            d.sessions = 10
        case .monthlyNets:
            d.amount = amount(20)
            d.billing = .monthly
            d.covers = [.nets]
        case .seasonMembership:
            d.amount = amount(120)
            d.billing = .instalments
            d.parts = 3
            d.covers = []
            d.openToJoin = false
        case .juniorMembership:
            d.amount = amount(50)
            d.covers = []
            d.priceTypeId = groups.junior?.id
        }
        return d
    }

    /// The next 31 March, this year's if it hasn't gone.
    static func endOfMarch(after today: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: today)
        for y in [year, year + 1] {
            if let date = calendar.date(from: DateComponents(year: y, month: 3, day: 31)),
               date >= calendar.startOfDay(for: today) {
                return date
            }
        }
        return today
    }
}

// MARK: - Group fees

/// A charge to a group of people that isn't for one session: league
/// registration, a tour, kit, match balls. Never called a "collection" on
/// screen.
struct GroupFee: Decodable, Identifiable, Equatable {
    let id: UUID
    let clubId: UUID
    let title: String
    let createdAt: Date
    let mode: CostMode
    let amountCents: Int
    let totalCents: Int
    let currency: String
    /// `issued`, or `void` once cancelled.
    let status: String
    let note: String?
    let dueOn: String?
    let voidReason: String?
    let paidCents: Int
    let waitingCents: Int
    let owedCents: Int
    let people: Int
    /// Everyone's lines for an admin, only your own for a member; empty in
    /// the list.
    let shares: [ClubShare]

    enum CodingKeys: String, CodingKey {
        case id, title, mode, currency, status, note, people, shares
        case clubId = "club_id"
        case createdAt = "event_start_at"
        case amountCents = "amount_cents"
        case totalCents = "total_cents"
        case dueOn = "due_on"
        case voidReason = "void_reason"
        case paidCents = "paid_cents"
        case waitingCents = "waiting_cents"
        case owedCents = "owed_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        clubId = try c.decode(UUID.self, forKey: .clubId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .now
        mode = try c.decodeIfPresent(CostMode.self, forKey: .mode) ?? .unknown("")
        amountCents = (try? c.decodeIfPresent(Int.self, forKey: .amountCents)) ?? 0
        totalCents = (try? c.decodeIfPresent(Int.self, forKey: .totalCents)) ?? 0
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? Money.fallbackCurrency
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        dueOn = try? c.decodeIfPresent(String.self, forKey: .dueOn)
        voidReason = try? c.decodeIfPresent(String.self, forKey: .voidReason)
        paidCents = (try? c.decodeIfPresent(Int.self, forKey: .paidCents)) ?? 0
        waitingCents = (try? c.decodeIfPresent(Int.self, forKey: .waitingCents)) ?? 0
        owedCents = (try? c.decodeIfPresent(Int.self, forKey: .owedCents)) ?? 0
        people = (try? c.decodeIfPresent(Int.self, forKey: .people)) ?? 0
        shares = (try? c.decodeIfPresent([ClubShare].self, forKey: .shares)) ?? []
    }

    var isCancelled: Bool { status == "void" }

    /// "Match balls, by 6 Dec".
    var titleWithDue: String {
        guard let due = DayDate.short(dueOn) else { return title }
        return tr("{what}, by {date}", vars: ["what": title, "date": due])
    }

    /// "3 people · £45.00 still owed", "Cancelled: wrong amount".
    var summary: String {
        if isCancelled {
            return voidReason.map { tr("Cancelled: {reason}", vars: ["reason": $0]) } ?? tr("Cancelled")
        }
        var parts = [people == 1 ? tr("{n} person", vars: ["n": 1]) : tr("{n} people", vars: ["n": people])]
        if owedCents > 0 {
            parts.append(tr("{amount} still owed", vars: ["amount": Money.format(owedCents, currency)]))
        }
        if waitingCents > 0 {
            parts.append(tr("{amount} to check", vars: ["amount": Money.format(waitingCents, currency)]))
        }
        if owedCents == 0, waitingCents == 0 { parts.append(tr("Paid")) }
        return parts.joined(separator: " · ")
    }
}

/// Who a group fee is for: one of these, plus any guests by name.
enum GroupFeeWho: Hashable {
    case everyone
    case team(UUID)
    case group(UUID)
    case people
}

/// `POST /clubs/{id}/collections`.
struct NewGroupFeeBody: Encodable, Equatable {
    let title: String
    let mode: String
    let amountCents: Int
    let everyone: Bool?
    let teamId: UUID?
    let priceTypeId: UUID?
    let userIds: [UUID]?
    let guests: [String]
    let dueOn: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case title, mode, everyone, guests, note
        case amountCents = "amount_cents"
        case teamId = "team_id"
        case priceTypeId = "price_type_id"
        case userIds = "user_ids"
        case dueOn = "due_on"
    }
}

/// The new group fee form, as it is filled in.
struct GroupFeeDraft: Equatable {
    var title = ""
    var who: GroupFeeWho = .everyone
    var picked: Set<UUID> = []
    var guests: [String] = []
    var mode: CostMode = .perPlayer
    var amount = ""
    var hasDueDate = true
    var dueOn = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    var note = ""

    func problem(currency: String) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tr("Say what it's for, like League registration.")
        }
        if (Money.parse(amount, currency: currency) ?? 0) <= 0 {
            return tr("Put in how much.")
        }
        if who == .people, picked.isEmpty, guests.isEmpty {
            return tr("Tick who it's for.")
        }
        return nil
    }

    func body(currency: String) -> NewGroupFeeBody? {
        guard problem(currency: currency) == nil, let cents = Money.parse(amount, currency: currency) else { return nil }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var everyone: Bool?
        var team: UUID?
        var group: UUID?
        var users: [UUID]?
        switch who {
        case .everyone: everyone = true
        case .team(let id): team = id
        case .group(let id): group = id
        case .people: users = picked.isEmpty ? nil : picked.sorted { $0.uuidString < $1.uuidString }
        }
        return NewGroupFeeBody(
            title: title.split(whereSeparator: \.isWhitespace).joined(separator: " "),
            mode: (mode == .splitTotal ? CostMode.splitTotal : .perPlayer).raw,
            amountCents: cents,
            everyone: everyone,
            teamId: team,
            priceTypeId: group,
            userIds: users,
            guests: guests,
            dueOn: hasDueDate ? DayDate.string(dueOn) : nil,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
    }
}

// MARK: - Paying for other people

/// Somebody the reader pays for (a parent's junior), with what they owe one
/// club. `managed` means they have no sign-in of their own.
struct PersonDues: Codable, Identifiable, Equatable {
    let userId: UUID
    let name: String
    let managed: Bool
    let clubId: UUID
    let dues: ClubDues

    var id: String { "\(userId.uuidString)-\(clubId.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case name, managed, dues
        case userId = "user_id"
        case clubId = "club_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(UUID.self, forKey: .userId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        managed = (try? c.decodeIfPresent(Bool.self, forKey: .managed)) ?? false
        clubId = try c.decode(UUID.self, forKey: .clubId)
        dues = try c.decode(ClubDues.self, forKey: .dues)
    }
}

/// One club's "You owe": the reader's own dues, and each person they pay
/// for, paid together with one payment and one reference.
struct DuesGroup: Identifiable, Equatable {
    let clubId: UUID
    let clubName: String
    let currency: String
    let mine: ClubDues?
    let people: [PersonDues]

    var id: UUID { clubId }

    var peopleOwing: [PersonDues] { people.filter { $0.dues.owedCents > 0 } }
    var includeMe: Bool { (mine?.owedCents ?? 0) > 0 }

    /// Everything to pay in one go.
    var totalOwedCents: Int { (mine?.owedCents ?? 0) + peopleOwing.reduce(0) { $0 + $1.dues.owedCents } }

    /// One button for everyone, once somebody else is in it.
    var canPayForEveryone: Bool { !peopleOwing.isEmpty }

    /// "you, Jas and Arjun", "Jas and Arjun".
    var whoWords: String {
        let first = peopleOwing.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
        let you = tr("you")
        let names = (includeMe ? [you] : []) + first
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return tr("{a} and {b}", vars: ["a": names.dropLast().joined(separator: ", "), "b": last])
    }
}

extension MyDues {
    /// Club by club: the reader's own dues, then whoever they pay for there.
    var groups: [DuesGroup] {
        var order: [UUID] = clubs.map(\.clubId)
        for person in people where !order.contains(person.clubId) { order.append(person.clubId) }
        return order.map { id in
            let mine = clubs.first { $0.clubId == id }
            let theirs = people.filter { $0.clubId == id }
            return DuesGroup(
                clubId: id,
                clubName: mine?.clubName ?? theirs.first?.dues.clubName ?? "",
                currency: mine?.currency ?? theirs.first?.dues.currency ?? Money.fallbackCurrency,
                mine: mine,
                people: theirs
            )
        }
    }
}

/// `POST /clubs/{id}/payments/for-others`: one line each, all under the
/// payer's reference.
struct PaidForOthers: Decodable, Equatable {
    let payments: [ClubPayment]
    let totalCents: Int
    let reference: String?

    enum CodingKeys: String, CodingKey {
        case payments, reference
        case totalCents = "total_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        payments = (try? c.decodeIfPresent([ClubPayment].self, forKey: .payments)) ?? []
        totalCents = (try? c.decodeIfPresent(Int.self, forKey: .totalCents)) ?? 0
        reference = try? c.decodeIfPresent(String.self, forKey: .reference)
    }

    var currency: String { payments.first?.currency ?? Money.fallbackCurrency }

    /// Said once it's recorded.
    func notice(method: String) -> String {
        let amount = Money.format(totalCents, currency)
        let n = payments.count
        if method == "cash" {
            return n == 1
                ? tr("Thanks. {amount} in cash for 1 person. The club will confirm it once they've got the cash.", vars: ["amount": amount])
                : tr("Thanks. {amount} in cash for {n} people. The club will confirm it once they've got the cash.", vars: ["amount": amount, "n": n])
        }
        let ref = reference ?? ""
        return n == 1
            ? tr("Thanks. {amount} for 1 person, with the reference {reference}. The club will confirm it once the money shows up.", vars: ["amount": amount, "reference": ref])
            : tr("Thanks. {amount} for {n} people, with the reference {reference}. The club will confirm it once the money shows up.", vars: ["amount": amount, "n": n, "reference": ref])
    }
}

/// `POST /clubs/{id}/members/managed`: a junior with no sign-in of their own.
struct ManagedMember: Decodable, Equatable {
    let userId: UUID
    let name: String
    let payerId: UUID?

    enum CodingKeys: String, CodingKey {
        case name
        case userId = "user_id"
        case payerId = "payer_id"
    }
}

// MARK: - Lines that aren't a session's

extension ClubShare {
    /// A pass charge or a group fee, rather than a session.
    var isSessionLine: Bool { (kind ?? "event") == "event" }

    /// Under the title: "by 6 Dec" for a charge with a date, the session's
    /// day otherwise.
    var whenWords: String {
        if let due = DayDate.short(dueOn) { return tr("by {date}", vars: ["date": due]) }
        return eventStartAt.formatted(date: .abbreviated, time: .omitted)
    }

    /// A free price group covers it, rather than a pass.
    var isFreeCover: Bool { cover == "free" }

    /// What a covered line says to the person it's for: nothing to pay, and
    /// why. Worded from `cover`; the `reason` is the server's English. A line
    /// from a server without `cover` reads as a pass's.
    func coveredWords(forSomeoneElse: Bool = false) -> String {
        if isFreeCover { return tr("Free ✓") }
        return forSomeoneElse ? tr("Covered by their pass ✓") : tr("Covered by your pass ✓")
    }

    /// Beside somebody's name in a list a money admin reads.
    var coveredByWords: String { isFreeCover ? tr("Free") : tr("Covered by a pass") }
}
