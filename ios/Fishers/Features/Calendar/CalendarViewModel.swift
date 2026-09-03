import Foundation
import Observation

@Observable
@MainActor
final class CalendarViewModel {
    enum ViewMode: String, CaseIterable {
        case month = "Month"
        case week = "Week"
    }

    var viewMode: ViewMode = .month
    var anchor: Date = Date()           // any date inside the displayed month/week
    var selectedDay: Date = Date()
    var cricketSeasonOnly = false
    var availabilityByDay: [String: Availability] = [:]
    var events: [Event] = []
    var isLoading = false
    var errorMessage: String?

    private let calendar = Calendar.current

    // MARK: Derived

    var monthTitle: String {
        anchor.formatted(.dateTime.month(.wide).year())
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Cells for the month grid: nil = leading/trailing padding.
    var monthCells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: anchor) else { return [] }
        let firstDay = interval.start
        let dayCount = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 30
        let leading = (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: firstDay))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    var weekDays: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: anchor) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    var visibleEvents: [Event] {
        cricketSeasonOnly ? events.filter { $0.isCricket } : events
    }

    func status(for day: Date) -> AvailabilityStatus? {
        availabilityByDay[DayFormatter.string(from: day)]?.status
    }

    func events(on day: Date) -> [Event] {
        let key = DayFormatter.string(from: day)
        return visibleEvents.filter { $0.dayKey == key }.sorted { $0.startAt < $1.startAt }
    }

    var selectedDayEvents: [Event] {
        events(on: selectedDay)
    }

    var weekEvents: [Event] {
        weekDays.flatMap { events(on: $0) }
    }

    func isToday(_ day: Date) -> Bool {
        calendar.isDateInToday(day)
    }

    func isSelected(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: selectedDay)
    }

    func inDisplayedMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: anchor, toGranularity: .month)
    }

    // MARK: Actions

    func step(_ direction: Int) {
        let component: Calendar.Component = viewMode == .month ? .month : .weekOfYear
        if let next = calendar.date(byAdding: component, value: direction, to: anchor) {
            anchor = next
        }
    }

    func goToToday() {
        anchor = Date()
        selectedDay = Date()
    }

    /// The core interaction: single tap selects the day and cycles
    /// none -> available -> maybe -> unavailable -> available...
    func tap(day: Date, api: FishersAPI) {
        selectedDay = day
        let key = DayFormatter.string(from: day)
        let nextStatus = availabilityByDay[key]?.status.next ?? .available
        // Optimistic update; reconcile with the server response.
        let optimistic = Availability(
            id: availabilityByDay[key]?.id ?? UUID(),
            userId: UUID(),
            date: key,
            status: nextStatus,
            note: nil,
            recurrenceRule: nil
        )
        availabilityByDay[key] = optimistic
        Task {
            do {
                let saved = try await api.setAvailability(date: key, status: nextStatus, note: nil)
                availabilityByDay[key] = saved
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func load(api: FishersAPI) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        // Load a generous window around the anchor so month paging feels instant.
        let from = calendar.date(byAdding: .month, value: -2, to: anchor)!
        let to = calendar.date(byAdding: .month, value: 4, to: anchor)!
        do {
            async let eventsTask = api.events(clubId: nil, teamId: nil, from: from, to: to)
            async let availabilityTask = api.availability(
                from: DayFormatter.string(from: from),
                to: DayFormatter.string(from: to)
            )
            let (loadedEvents, loadedAvailability) = try await (eventsTask, availabilityTask)
            events = loadedEvents
            var map: [String: Availability] = [:]
            for entry in loadedAvailability { map[entry.date] = entry }
            availabilityByDay = map
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
