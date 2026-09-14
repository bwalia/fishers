import Foundation
import SwiftUI

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var month: Date = .now
    @Published var days: [Date: AvailabilityStatus] = [:]
    @Published var events: [Event] = []
    /// Your fixtures this month with your answer to each — the marks on a day.
    @Published var fixtures: [MyFixture] = []
    @Published var bulkBusy = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var cricketSeasonOnly = false

    private let calendar = Calendar.current
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let interval = monthInterval(for: month)
            let from = dayFormatter.string(from: interval.start)
            let to = dayFormatter.string(from: interval.end)
            async let avail = FishersAPI.availability(from: from, to: to)
            async let ev = FishersAPI.events(cricketSeason: cricketSeasonOnly)
            async let mine = FishersAPI.myFixtures(
                from: interval.start,
                to: calendar.date(byAdding: .day, value: 1, to: interval.end) ?? interval.end
            )
            let (a, e) = try await (avail, ev)
            fixtures = (try? await mine) ?? []
            var map: [Date: AvailabilityStatus] = [:]
            for item in a {
                if let d = dayFormatter.date(from: item.date) {
                    map[calendar.startOfDay(for: d)] = item.status
                }
            }
            days = map
            events = e
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func set(day: Date, to status: AvailabilityStatus) async {
        let start = calendar.startOfDay(for: day)
        do {
            let saved = try await FishersAPI.setAvailability(date: dayFormatter.string(from: start), status: status)
            days[start] = saved.status
        } catch {
            errorMessage = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
    }

    func toggle(day: Date) async {
        let start = calendar.startOfDay(for: day)
        let current = days[start] ?? .unavailable
        let next = (days[start] == nil) ? AvailabilityStatus.available : current.next()
        let key = dayFormatter.string(from: start)
        do {
            let saved = try await FishersAPI.setAvailability(date: key, status: next)
            days[start] = saved.status
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fixtures(on day: Date) -> [MyFixture] {
        fixtures.filter { calendar.isDate($0.startAt, inSameDayAs: day) }.sorted { $0.startAt < $1.startAt }
    }

    /// Every `weekday` (1 = Sunday) in the month shown, set at once — the way
    /// people actually think about it: "Saturdays I play".
    func setEvery(weekday: Int, to status: AvailabilityStatus) async {
        let dates = FixtureList.dates(in: month, weekday: weekday, calendar: calendar)
        guard !dates.isEmpty else { return }
        bulkBusy = true
        defer { bulkBusy = false }
        do {
            let saved = try await FishersAPI.setAvailability(dates: dates.map(dayFormatter.string(from:)), status: status)
            for item in saved {
                if let d = dayFormatter.date(from: item.date) { days[calendar.startOfDay(for: d)] = item.status }
            }
        } catch {
            errorMessage = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
    }

    func setAnswer(_ answer: FixtureAnswer?, for eventId: UUID) {
        if let index = fixtures.firstIndex(where: { $0.eventId == eventId }) {
            fixtures[index].myAnswer = answer
        }
    }

    func events(on day: Date) -> [Event] {
        let start = calendar.startOfDay(for: day)
        return events.filter { calendar.isDate($0.startAt, inSameDayAs: start) }
    }

    func monthInterval(for date: Date) -> (start: Date, end: Date) {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: comps) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? date
        return (start, end)
    }

    func daysInMonth() -> [Date?] {
        let interval = monthInterval(for: month)
        let firstWeekday = calendar.component(.weekday, from: interval.start) // 1=Sun
        let pad = (firstWeekday + 5) % 7 // Monday-first
        var result: [Date?] = Array(repeating: nil, count: pad)
        var d = interval.start
        while d <= interval.end {
            result.append(d)
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86400)
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }
}
