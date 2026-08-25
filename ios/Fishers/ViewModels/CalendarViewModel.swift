import Foundation
import SwiftUI

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var month: Date = .now
    @Published var days: [Date: AvailabilityStatus] = [:]
    @Published var events: [Event] = []
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
            let (a, e) = try await (avail, ev)
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
