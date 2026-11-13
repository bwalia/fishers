import Foundation

/// What the schedule sheet makes. A match is against somebody and ends in a
/// scorecard; nets and training are a session to turn up to, with nobody to
/// play and no side to pick.
enum ScheduleKind: String, CaseIterable, Identifiable {
    case match, nets, training

    var id: String { rawValue }

    var label: String {
        switch self {
        case .match: return t("np.match")
        case .nets: return t("ev.nets")
        case .training: return t("ev.training")
        }
    }

    var isPractice: Bool { self != .match }

    /// Nets usually run two hours, training an hour and a half.
    var defaultMinutes: Int { self == .training ? 90 : 120 }
}

/// What the schedule sheet sends, kept out of the view so it can be tested
/// without a server: one `POST /events` per match, or per week of practice.
enum ScheduleRequests {
    static let minuteChoices = [60, 90, 120, 180]
    static let weekChoices = 2...12
    static let defaultWeeks = 8

    /// A match, exactly as the sheet has always sent it.
    static func match(
        club: Club, opponentClubId: UUID?, theirName: String, venueId: UUID?, start: Date
    ) -> CreateEventBody {
        CreateEventBody(
            club_id: club.id,
            opponent_club_id: opponentClubId,
            team_id: nil,
            // What the club plays. Hard-coding cricket here filed every
            // fixture as a cricket match whatever the club turns out for.
            sport: club.sportTypes.first ?? tr("cricket"),
            event_subtype: "league_match",
            title: "\(club.name) v \(theirName)",
            venue_id: venueId,
            start_at: start,
            // A cricket fixture runs most of an afternoon; nobody wants to
            // type an end time as well.
            end_at: start.addingTimeInterval(5 * 3600),
            recurrence_rule: nil,
            capacity: nil,
            fee_amount_cents: nil,
            metadata: nil
        )
    }

    /// Nets or training: one body per session, a week apart.
    ///
    /// `weeks` is nil for a one-off. A series shares one `series_id`, minted
    /// here, and numbers its weeks from 0 — the server notifies only for week
    /// 0, so eight weeks of nets is one ping rather than eight. Each week is
    /// added on the calendar rather than as 7 × 24 hours, so 19:00 stays 19:00
    /// when the clocks change.
    static func sessions(
        kind: ScheduleKind,
        club: Club,
        teamId: UUID?,
        title: String,
        venueId: UUID?,
        start: Date,
        minutes: Int,
        note: String,
        weeks: Int?,
        seriesId: UUID = UUID(),
        calendar: Calendar = .current
    ) -> [CreateEventBody] {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = weeks ?? 1
        return (0..<count).compactMap { index in
            guard let at = calendar.date(byAdding: .weekOfYear, value: index, to: start) else { return nil }
            var metadata: [String: JSONValue] = [:]
            if !note.isEmpty { metadata["note"] = .string(note) }
            if weeks != nil {
                metadata["series_id"] = .string(seriesId.uuidString.lowercased())
                metadata["series_index"] = .number(Double(index))
                metadata["series_count"] = .number(Double(count))
            }
            return CreateEventBody(
                club_id: club.id,
                opponent_club_id: nil,
                team_id: teamId,
                sport: club.sportTypes.first ?? "cricket",
                event_subtype: kind.rawValue,
                title: title,
                venue_id: venueId,
                start_at: at,
                end_at: at.addingTimeInterval(TimeInterval(minutes * 60)),
                recurrence_rule: nil,
                capacity: nil,
                fee_amount_cents: nil,
                metadata: metadata
            )
        }
    }

    /// Sends `bodies` one after another from `index`, stopping at the first
    /// that fails. What was made comes back with the failure, so a retry can
    /// carry on from there rather than sending a week that already exists.
    static func create(
        _ bodies: [CreateEventBody],
        from index: Int = 0,
        send: (CreateEventBody) async throws -> Event
    ) async -> (made: [Event], failure: Error?) {
        var made: [Event] = []
        for body in bodies.dropFirst(index) {
            do {
                made.append(try await send(body))
            } catch {
                return (made, error)
            }
        }
        return (made, nil)
    }
}

/// Nets or training just made: the first session to open, and how many there
/// were — a weekly series says so on the page it lands on.
struct ScheduledSessions: Hashable {
    let eventId: UUID
    let count: Int

    var notice: String? {
        count > 1 ? t("np.scheduled_sessions", count: count, vars: ["n": count]) : nil
    }
}

/// How a nets or training event reads, wherever one is shown. Anything else
/// gets nil or `false` back and is drawn exactly as it was.
enum Practice {
    static func isPractice(_ subtype: String) -> Bool {
        subtype == ScheduleKind.nets.rawValue || subtype == ScheduleKind.training.rawValue
    }

    /// "Nets" or "Training".
    static func label(_ subtype: String) -> String? {
        guard isPractice(subtype) else { return nil }
        return ScheduleKind(rawValue: subtype)?.label
    }

    /// The availability question: whether you are coming to a session, or
    /// whether you can play in a match.
    static func question(subtype: String, title: String) -> String {
        isPractice(subtype) ? t("np.are_you_coming") : t("ev.can_you_play", vars: ["fixture": title])
    }

    static func note(_ metadata: [String: JSONValue]?) -> String? {
        guard case .string(let note)? = metadata?["note"] else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// "Week 3 of 8", for one week of a series.
    static func weekOf(_ metadata: [String: JSONValue]?) -> String? {
        guard case .number(let index)? = metadata?["series_index"],
              case .number(let count)? = metadata?["series_count"],
              count > 1
        else { return nil }
        return t("np.week_of", vars: ["i": Int(index) + 1, "n": Int(count)])
    }
}

extension Event {
    var isPractice: Bool { Practice.isPractice(eventSubtype) }
}

extension MyFixture {
    var isPractice: Bool { Practice.isPractice(eventSubtype) }
}
