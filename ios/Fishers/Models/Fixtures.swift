import Foundation

/// "Can you play?" — the three answers, saved as an RSVP.
enum FixtureAnswer: String, Codable, CaseIterable, Identifiable {
    case going
    case maybe
    case notGoing = "not_going"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .going: return "Available"
        case .maybe: return "Maybe"
        case .notGoing: return "Can't play"
        }
    }

    /// What the card says back.
    var said: String {
        switch self {
        case .going: return "You're available"
        case .maybe: return "You said maybe"
        case .notGoing: return "You can't play"
        }
    }

    var systemImage: String {
        switch self {
        case .going: return "checkmark.circle.fill"
        case .maybe: return "questionmark.circle.fill"
        case .notGoing: return "xmark.circle.fill"
        }
    }

    var rsvp: RsvpStatus {
        switch self {
        case .going: return .going
        case .maybe: return .maybe
        case .notGoing: return .notGoing
        }
    }
}

/// One of your fixtures with your answer to it (`GET /events/mine`). The list
/// and the calendar both read this, so they cannot disagree about whether you
/// are playing.
struct MyFixture: Codable, Identifiable, Hashable {
    let eventId: UUID
    var title: String
    var sport: String
    var eventSubtype: String
    var status: String
    var startAt: Date
    var endAt: Date
    var clubId: UUID
    var clubName: String
    var opponentClubId: UUID?
    var opponentClubName: String?
    var venueName: String?
    var matchId: UUID?
    var myAnswer: FixtureAnswer?
    var feeAmountCents: Int?
    var ticketPriceCents: Int?

    var id: UUID { eventId }

    enum CodingKeys: String, CodingKey {
        case title, sport, status
        case eventId = "event_id"
        case eventSubtype = "event_subtype"
        case startAt = "start_at"
        case endAt = "end_at"
        case clubId = "club_id"
        case clubName = "club_name"
        case opponentClubId = "opponent_club_id"
        case opponentClubName = "opponent_club_name"
        case venueName = "venue_name"
        case matchId = "match_id"
        case myAnswer = "my_answer"
        case feeAmountCents = "fee_amount_cents"
        case ticketPriceCents = "ticket_price_cents"
    }

    var saidLabel: String { myAnswer?.said ?? "Not answered yet" }

    var systemImage: String {
        switch eventSubtype {
        case "league_match", "tournament": return "trophy"
        case "friendly": return "figure.cricket"
        case "nets": return "sportscourt"
        case "social": return "person.3"
        default: return "calendar"
        }
    }

    var isCancelled: Bool { status == "cancelled" }
    var isPostponed: Bool { status == "postponed" }
}

enum FixtureList {
    /// Fixtures by the local calendar day they start on, days in order.
    static func byDay(_ fixtures: [MyFixture], calendar: Calendar = .current) -> [(day: Date, fixtures: [MyFixture])] {
        let grouped = Dictionary(grouping: fixtures) { calendar.startOfDay(for: $0.startAt) }
        return grouped.keys.sorted().map { day in
            (day, grouped[day]!.sorted { $0.startAt < $1.startAt })
        }
    }

    /// Fixtures you have said yes to that overlap another you said yes to.
    static func clashes(_ fixtures: [MyFixture]) -> Set<UUID> {
        let yes = fixtures.filter { $0.myAnswer == .going }
        var out = Set<UUID>()
        for a in yes {
            for b in yes where a.eventId != b.eventId && a.startAt < b.endAt && b.startAt < a.endAt {
                out.insert(a.eventId)
            }
        }
        return out
    }

    /// "Today · Sunday 14 September", "Tomorrow · …", or the long date.
    static func dayTitle(_ day: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let long = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if calendar.isDate(day, inSameDayAs: now) { return "Today · \(long)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow · \(long)"
        }
        return long
    }

    /// Every date in `month` that falls on `weekday` (1 = Sunday … 7 = Saturday).
    static func dates(in month: Date, weekday: Int, calendar: Calendar = .current) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
            .filter { calendar.component(.weekday, from: $0) == weekday }
    }
}
