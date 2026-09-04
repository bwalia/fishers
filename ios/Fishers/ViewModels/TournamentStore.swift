import Foundation
import SwiftUI

/// One tournament: who's entered, the fixture list, the table.
@MainActor
final class TournamentStore: ObservableObject {
    @Published var entrants: [TournamentEntrant] = []
    @Published var schedule: [ScheduleRow] = []
    @Published var standings: [Standing] = []
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var errorMessage: String?

    private let blockId: UUID

    init(blockId: UUID) {
        self.blockId = blockId
    }

    /// Fixtures grouped by day, which is how a festival is actually read.
    var scheduleByDay: [(day: Date, fixtures: [ScheduleRow])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: schedule) { calendar.startOfDay(for: $0.startsAt) }
        return grouped.keys.sorted().map { ($0, grouped[$0]?.sorted { $0.startsAt < $1.startsAt } ?? []) }
    }

    var groups: [String] {
        Array(Set(standings.compactMap(\.groupLabel))).sorted()
    }

    func standings(in group: String) -> [Standing] {
        standings.filter { $0.groupLabel == group }
    }

    var knockoutFixtures: [ScheduleRow] {
        schedule.filter { $0.stage == "knockout" }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entrants = try await FishersAPI.entrants(blockId: blockId)
            schedule = try await FishersAPI.tournamentSchedule(blockId: blockId)
            standings = try await FishersAPI.standings(blockId: blockId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addEntrants(_ names: [String]) async {
        let cleaned = names
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        do {
            _ = try await FishersAPI.addEntrants(blockId: blockId, names: cleaned)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Lay out the pitches and times, then generate the fixtures into them.
    func setUp(
        courts: [String],
        firstStart: Date,
        matchMinutes: Int,
        gapMinutes: Int,
        rounds: Int,
        format: TournamentFormat,
        groupCount: Int
    ) async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            try await FishersAPI.generateSlots(
                blockId: blockId, courts: courts, firstStart: firstStart,
                matchMinutes: matchMinutes, gapMinutes: gapMinutes, rounds: rounds
            )
            try await FishersAPI.generateSchedule(
                blockId: blockId, format: format,
                groupCount: format == .groupsKnockout ? groupCount : nil,
                commit: true
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Draw the knockout from the group table.
    func buildKnockout(perGroup: Int) async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            try await FishersAPI.generateKnockout(blockId: blockId, perGroup: perGroup, commit: true)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recordResult(row: ScheduleRow, homeScore: Int, awayScore: Int) async {
        guard let home = entrants.first(where: { $0.name == row.homeName }),
              let away = entrants.first(where: { $0.name == row.awayName })
        else {
            errorMessage = "Couldn't match the sides to entrants."
            return
        }
        let homeResult = homeScore == awayScore ? "draw" : (homeScore > awayScore ? "win" : "loss")
        let awayResult = homeScore == awayScore ? "draw" : (homeScore > awayScore ? "loss" : "win")
        do {
            try await FishersAPI.recordResult(eventId: row.eventId, entrants: [
                (entrantId: home.id, score: homeScore, result: homeResult),
                (entrantId: away.id, score: awayScore, result: awayResult),
            ])
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Ticketed club events — presentation nights, dinners, AGMs.
@MainActor
final class TicketStore: ObservableObject {
    @Published var booking: TicketBooking?
    @Published var isWorking = false
    @Published var errorMessage: String?

    private let eventId: UUID

    init(eventId: UUID) {
        self.eventId = eventId
    }

    /// This device's own booking, if any.
    var myTicket: EventTicket? {
        guard let userId = KeychainStore.get("user_id").flatMap(UUID.init(uuidString:)) else {
            return nil
        }
        return booking?.tickets.first { $0.userId == userId && $0.status != "cancelled" }
    }

    var isTicketed: Bool { (booking?.summary.ticketPriceCents ?? 0) > 0 || booking?.summary.ticketCapacity != nil }

    func load() async {
        booking = try? await FishersAPI.tickets(eventId: eventId)
    }

    func book(guests: Int, guestNames: String?, notes: String?) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await FishersAPI.bookTicket(
                eventId: eventId, guests: guests,
                guestNames: guestNames?.nonEmpty, notes: notes?.nonEmpty
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pay() async {
        guard let ticket = myTicket else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await FishersAPI.payTicket(ticket.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() async {
        guard let ticket = myTicket else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await FishersAPI.cancelTicket(ticket.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
