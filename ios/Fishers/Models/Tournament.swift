import Foundation

enum TournamentFormat: String, Codable, CaseIterable {
    case none
    case roundRobin = "round_robin"
    case groupsKnockout = "groups_knockout"
    case knockout
    case ladder

    var label: String {
        switch self {
        case .none: return "No structure"
        case .roundRobin: return "Round robin"
        case .groupsKnockout: return "Groups + knockout"
        case .knockout: return "Straight knockout"
        case .ladder: return "Ladder"
        }
    }
}

struct FixtureBlock: Codable, Identifiable, Hashable {
    let id: UUID
    let clubId: UUID
    let teamId: UUID?
    var name: String
    /// `block` | `tour` | `tournament` | `season`
    var kind: String
    var startsOn: String?
    var endsOn: String?

    // MARK: what a tournament settles before anybody enters
    //
    // All optional: a block created before tournaments carried rules sends
    // none of this, and a plain block of fixtures never will.
    var description: String?
    /// How many sides fit. Nil is no limit.
    var maxEntrants: Int?
    var entryDeadline: Date?
    /// What a side pays to enter — not a spectator's ticket.
    var entryFeeCents: Int?
    /// Eleven normally; six for sixes. Nil only from an older API.
    var playersPerSide: Int?
    /// 0 means every player must belong to the entering club.
    var guestPlayersAllowed: Int?
    var ageGroup: String?
    var gender: String?
    /// Overs, ball, ground and the fielding restrictions every fixture in the
    /// tournament inherits. Nil means the two captains agree their own.
    var conditions: MatchConditions?
    var rulesNotes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, description, gender, conditions
        case clubId = "club_id"
        case teamId = "team_id"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case maxEntrants = "max_entrants"
        case entryDeadline = "entry_deadline"
        case entryFeeCents = "entry_fee_cents"
        case playersPerSide = "players_per_side"
        case guestPlayersAllowed = "guest_players_allowed"
        case ageGroup = "age_group"
        case rulesNotes = "rules_notes"
    }

    /// A side is eleven unless the tournament says otherwise.
    var side: Int { playersPerSide ?? 11 }

    /// What the entry rules amount to, in one line for a list row.
    var entryLine: String {
        var parts: [String] = ["\(side) a side"]
        if let age = ageGroup, age != "open" { parts.append(age.uppercased()) }
        if let g = gender, g != "open" { parts.append(g.capitalized) }
        if let overs = conditions?.oversLimit { parts.append("\(overs) overs") }
        if let guests = guestPlayersAllowed, guests > 0 {
            parts.append("\(guests) guest\(guests == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    var systemImage: String {
        switch kind {
        case "tournament": return "trophy.fill"
        case "tour": return "bus.fill"
        case "season": return "calendar"
        default: return "square.stack.3d.up.fill"
        }
    }
}

/// Where a side is in the entry process.
///
/// A name an organiser typed in is `accepted` straight away — they are entering
/// it, not asking it. `invited` belongs to a real club that answers for itself,
/// and only accepted sides go into the draw.
enum EntryStatus: String, Codable, Equatable {
    case invited, accepted, declined, withdrawn

    var label: String {
        switch self {
        case .invited: return "Asked"
        case .accepted: return "In"
        case .declined: return "Declined"
        case .withdrawn: return "Withdrawn"
        }
    }
}

struct TournamentEntrant: Codable, Identifiable, Equatable {
    let id: UUID
    let blockId: UUID
    var name: String
    var clubId: UUID?
    var seed: Int?
    var groupLabel: String?
    var contactName: String?
    var contactEmail: String?
    /// Optional only so a build talking to an API that predates entry invites
    /// still decodes; `status` is what the server has decided.
    var status: EntryStatus?
    var respondedAt: Date?
    /// Set when the entry fee is settled, by card or by an organiser recording
    /// a cheque. Nil when the tournament is free, or when they still owe.
    var entryPaidAt: Date?
    /// `card` | `cash` | `transfer` | `cheque`
    var entryPaymentMethod: String?
    var withdrawn: Bool

    var entryPaid: Bool { entryPaidAt != nil }

    /// What the row says. Falls back to the old boolean when an older API
    /// sends no status at all.
    var entry: EntryStatus { status ?? (withdrawn ? .withdrawn : .accepted) }

    enum CodingKeys: String, CodingKey {
        case id, name, seed, withdrawn, status
        case blockId = "block_id"
        case clubId = "club_id"
        case groupLabel = "group_label"
        case contactName = "contact_name"
        case contactEmail = "contact_email"
        case respondedAt = "responded_at"
        case entryPaidAt = "entry_paid_at"
        case entryPaymentMethod = "entry_payment_method"
    }
}

/// What came back from asking a side in.
///
/// `inviteLink` is set only for a side with no Fishers account: club email goes
/// to a shared inbox somebody checks on Sundays, so the organiser often passes
/// the link on themselves.
struct InviteEntrantResult: Codable, Equatable {
    let entrant: TournamentEntrant
    let inviteLink: String?

    enum CodingKeys: String, CodingKey {
        case entrant
        case inviteLink = "invite_link"
    }
}

/// A tournament somebody has asked your club into.
struct EntryInvitation: Codable, Identifiable, Equatable {
    let entrantId: UUID
    let blockId: UUID
    let blockName: String
    let kind: String
    let startsOn: String?
    let endsOn: String?
    let hostClubId: UUID
    let hostClubName: String
    let entrantName: String
    let status: EntryStatus
    let invitedByName: String?
    /// What entering costs. Optional only so an older API still decodes.
    let entryFeeCents: Int?
    let entryPaidAt: Date?

    var id: UUID { entrantId }

    /// Said yes, still owes. Not in the draw until it is settled.
    var owesEntryFee: Bool { (entryFeeCents ?? 0) > 0 && entryPaidAt == nil }

    enum CodingKeys: String, CodingKey {
        case kind, status
        case entrantId = "entrant_id"
        case blockId = "block_id"
        case blockName = "block_name"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case hostClubId = "host_club_id"
        case hostClubName = "host_club_name"
        case entrantName = "entrant_name"
        case invitedByName = "invited_by_name"
        case entryFeeCents = "entry_fee_cents"
        case entryPaidAt = "entry_paid_at"
    }

    var dates: String? {
        guard let from = startsOn else { return nil }
        guard let to = endsOn, to != from else { return from }
        return "\(from) – \(to)"
    }
}

/// One fixture in a running tournament, as the app lists it.
struct ScheduleRow: Codable, Identifiable, Equatable {
    let eventId: UUID
    let title: String
    let startsAt: Date
    let courtLabel: String?
    /// `group` | `knockout`
    let stage: String?
    let round: Int?
    let groupLabel: String?
    let homeName: String?
    let awayName: String?
    let homeScore: Int?
    let awayScore: Int?
    let homeResult: String?
    let status: String

    var id: UUID { eventId }

    enum CodingKeys: String, CodingKey {
        case title, stage, round, status
        case eventId = "event_id"
        case startsAt = "starts_at"
        case courtLabel = "court_label"
        case groupLabel = "group_label"
        case homeName = "home_name"
        case awayName = "away_name"
        case homeScore = "home_score"
        case awayScore = "away_score"
        case homeResult = "home_result"
    }

    var isPlayed: Bool { homeResult != nil }

    var scoreLine: String? {
        guard let homeScore, let awayScore else { return nil }
        return "\(homeScore) – \(awayScore)"
    }

    var fixtureLine: String {
        "\(homeName ?? "TBC") v \(awayName ?? "TBC")"
    }
}

struct Standing: Codable, Identifiable, Equatable {
    let entrantId: UUID
    let name: String
    let groupLabel: String?
    let played: Int
    let won: Int
    let lost: Int
    let drawn: Int
    let noResult: Int
    let points: Int
    let scored: Int
    let conceded: Int

    var id: UUID { entrantId }

    enum CodingKeys: String, CodingKey {
        case name, played, won, lost, drawn, points, scored, conceded
        case entrantId = "entrant_id"
        case groupLabel = "group_label"
        case noResult = "no_result"
    }

    var difference: Int { scored - conceded }
}

struct EventTicket: Codable, Identifiable, Equatable {
    let id: UUID
    let eventId: UUID
    let userId: UUID
    let name: String?
    var guests: Int
    var guestNames: String?
    var amountCents: Int
    var currency: String
    /// `reserved` | `paid` | `cancelled`
    var status: String
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, guests, currency, status, notes
        case eventId = "event_id"
        case userId = "user_id"
        case guestNames = "guest_names"
        case amountCents = "amount_cents"
    }

    var isPaid: Bool { status == "paid" }
    var places: Int { 1 + guests }
}

struct TicketSummary: Codable, Equatable {
    let eventId: UUID
    let title: String
    let ticketCapacity: Int?
    let ticketPriceCents: Int?
    /// How many guests one member may bring; zero means members only. Optional
    /// only so an API that predates it still decodes.
    let guestsAllowed: Int?
    /// Anyone signed in may buy, not only members of the hosting club.
    /// Optional so an API that predates public sales still decodes.
    let ticketsPublic: Bool?
    let bookings: Int
    let headcount: Int
    let collectedCents: Int
    let outstandingCents: Int

    enum CodingKeys: String, CodingKey {
        case title, bookings, headcount
        case eventId = "event_id"
        case ticketCapacity = "ticket_capacity"
        case ticketPriceCents = "ticket_price_cents"
        case guestsAllowed = "guests_allowed"
        case ticketsPublic = "tickets_public"
        case collectedCents = "collected_cents"
        case outstandingCents = "outstanding_cents"
    }

    var placesLeft: Int? {
        ticketCapacity.map { max(0, $0 - headcount) }
    }
}

struct TicketBooking: Codable, Equatable {
    let summary: TicketSummary
    let tickets: [EventTicket]
    /// False for a non-member at a public event: they get the headcount and
    /// their own booking, never the guest list. Optional for an older API.
    let canSeeEveryone: Bool?

    /// Defaults to showing everything, which is what every event did before
    /// public sales existed and what every member still sees.
    var insider: Bool { canSeeEveryone ?? true }

    enum CodingKeys: String, CodingKey {
        case summary, tickets
        case canSeeEveryone = "can_see_everyone"
    }
}

/// A cricket fixture with its match state already joined on.
///
/// The scoring list and the Home overview both want the same thing: what is
/// happening, with enough on the row to decide whether to open it. `score` and
/// `result` arrive already formatted by the API, because a half-built innings
/// reads differently from a finished one and the server is the side that knows.
struct CricketFixtureRow: Codable, Identifiable, Hashable {
    let eventId: UUID
    let clubId: UUID
    let title: String
    let startAt: Date
    let eventStatus: String
    /// Absent until a match is created on the fixture.
    let matchId: UUID?
    /// `setup`, `live` or `complete`.
    let matchStatus: String?
    let homeName: String?
    let awayName: String?
    /// Somebody is scoring it — not necessarily you.
    let hasScorer: Bool
    /// "20/1 (2.0 ov)", as the API formats it.
    let score: String?
    let result: String?

    /// The fixture is the identity: there is at most one match on it, and rows
    /// without a match yet still need to be listed.
    var id: UUID { eventId }

    /// "London Lords v Watford", falling back to the fixture's own title before
    /// a match names the sides.
    var sides: String {
        guard let homeName, let awayName else { return title }
        return "\(homeName) v \(awayName)"
    }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case clubId = "club_id"
        case title
        case startAt = "start_at"
        case eventStatus = "event_status"
        case matchId = "match_id"
        case matchStatus = "match_status"
        case homeName = "home_name"
        case awayName = "away_name"
        case hasScorer = "has_scorer"
        case score
        case result
    }
}
