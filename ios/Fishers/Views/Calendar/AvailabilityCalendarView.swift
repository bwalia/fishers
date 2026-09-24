import SwiftUI

/// When you can play — and what you said to each fixture.
///
/// Two things a captain reads, on one calendar: the colour of a day is your
/// general availability; the marks on it are that day's fixtures, each in the
/// colour of your answer. Tap a day to set it and answer its fixtures there.
struct CalendarPane: View {
    @StateObject private var vm = CalendarViewModel()
    @State private var selectedDay: Date?
    @State private var bulkWeekday = 7

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]
    /// Monday-first, as the grid is, in Calendar's 1 = Sunday numbering.
    private let weekdayOrder: [(Int, String)] = [
        (2, "Mondays"), (3, "Tuesdays"), (4, "Wednesdays"), (5, "Thursdays"), (6, "Fridays"), (7, "Saturdays"), (1, "Sundays"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                weekdayHeader
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(vm.daysInMonth().enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day)
                        } else {
                            Color.clear.frame(height: 48)
                        }
                    }
                }
                .padding(.horizontal)

                legend

                if let selectedDay {
                    dayDetail(selectedDay)
                }

                bulk

                Toggle("Cricket season only (nets + games)", isOn: $vm.cricketSeasonOnly)
                    .padding(.horizontal)
                    .onChange(of: vm.cricketSeasonOnly) { _, _ in
                        Task { await vm.load() }
                    }

                if let error = vm.errorMessage {
                    Text(error).font(FishersTheme.footnote).foregroundStyle(FishersTheme.unavailable).padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var header: some View {
        HStack {
            Button {
                vm.month = Calendar.current.date(byAdding: .month, value: -1, to: vm.month) ?? vm.month
                Task { await vm.load() }
            } label: {
                Image(systemName: "chevron.left").frame(width: FishersTheme.minTap, height: FishersTheme.minTap)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(vm.month.formatted(.dateTime.month(.wide).year()))
                .font(FishersTheme.title)
                .tracking(-0.3)
            Spacer()
            Button {
                vm.month = Calendar.current.date(byAdding: .month, value: 1, to: vm.month) ?? vm.month
                Task { await vm.load() }
            } label: {
                Image(systemName: "chevron.right").frame(width: FishersTheme.minTap, height: FishersTheme.minTap)
            }
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdays.enumerated()), id: \.offset) { _, d in
                Text(d)
                    .font(FishersTheme.overline)
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private func dayCell(_ day: Date) -> some View {
        let status = vm.days[Calendar.current.startOfDay(for: day)]
        let marks = vm.fixtures(on: day)
        let selected = selectedDay.map { Calendar.current.isDate($0, inSameDayAs: day) } == true
        return Button {
            if selected {
                // A second tap on the open day moves its availability on.
                Task { await vm.toggle(day: day) }
            }
            selectedDay = day
        } label: {
            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(FishersTheme.subhead)
                    .foregroundStyle(status == nil ? FishersTheme.ink : .white)
                HStack(spacing: 2) {
                    ForEach(marks.prefix(3)) { f in
                        Circle()
                            .fill(markColour(f.myAnswer, onColour: status != nil))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color(for: status).opacity(status == nil ? 0.12 : 0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? FishersTheme.ink : .clear, lineWidth: 2)
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: status)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayLabel(day, status: status, marks: marks))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(AvailabilityStatus.allCases, id: \.self) { s in
                Label(s.label, systemImage: "square.fill")
                    .foregroundStyle(color(for: s))
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(FishersTheme.caption)
        .padding(.horizontal)
    }

    private func dayDetail(_ day: Date) -> some View {
        let status = vm.days[Calendar.current.startOfDay(for: day)]
        return VStack(alignment: .leading, spacing: 12) {
            Text(day.formatted(date: .complete, time: .omitted)).font(FishersTheme.headline)
            HStack(spacing: 6) {
                ForEach(AvailabilityStatus.allCases, id: \.self) { s in
                    Button {
                        Task { await setDay(day, to: s) }
                    } label: {
                        Text(s.label)
                            .font(FishersTheme.subhead.weight(status == s ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(status == s ? .white : .primary)
                            .background(status == s ? color(for: s) : FishersTheme.raised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(status == s ? .isSelected : [])
                }
            }
            let fixtures = vm.fixtures(on: day)
            if fixtures.isEmpty {
                Text("No fixtures this day.").font(FishersTheme.footnote).foregroundStyle(.secondary)
            }
            ForEach(fixtures) { fixture in
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink(value: FixtureRoute(eventId: fixture.eventId)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fixture.title).font(FishersTheme.contentTitle)
                                Text([fixture.startAt.formatted(date: .omitted, time: .shortened), fixture.venueName]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(FishersTheme.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    FixtureAnswerControl(
                        eventId: fixture.eventId,
                        answer: Binding(
                            get: { vm.fixtures.first { $0.eventId == fixture.eventId }?.myAnswer },
                            set: { vm.setAnswer($0, for: fixture.eventId) }
                        ),
                        title: "Can you play \(fixture.title)?"
                    )
                }
                .padding(12)
                .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FishersTheme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    /// Set a whole weekday for the month, then fix the odd day.
    private var bulk: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your usual days").font(FishersTheme.headline)
            Text("Set every one of a weekday in \(vm.month.formatted(.dateTime.month(.wide))) at once, then change the odd day above.")
                .font(FishersTheme.footnote)
                .foregroundStyle(.secondary)
            Picker("Weekday", selection: $bulkWeekday) {
                ForEach(weekdayOrder, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.menu)
            HStack(spacing: 6) {
                ForEach(AvailabilityStatus.allCases, id: \.self) { s in
                    Button {
                        Task { await vm.setEvery(weekday: bulkWeekday, to: s) }
                    } label: {
                        Text(s.label)
                            .font(FishersTheme.subhead)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(color(for: s).opacity(0.18), in: Capsule())
                            .foregroundStyle(color(for: s))
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.bulkBusy)
                    .accessibilityLabel("Every \(weekdayOrder.first { $0.0 == bulkWeekday }?.1.dropLast() ?? "day") \(s.label)")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FishersTheme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    private func setDay(_ day: Date, to status: AvailabilityStatus) async {
        let start = Calendar.current.startOfDay(for: day)
        guard vm.days[start] != status else { return }
        await vm.set(day: day, to: status)
    }

    private func dayLabel(_ day: Date, status: AvailabilityStatus?, marks: [MyFixture]) -> String {
        var parts = [day.formatted(.dateTime.weekday(.wide).day().month(.wide)), status?.label ?? "not said"]
        parts += marks.map { "\($0.title): \($0.saidLabel)" }
        return parts.joined(separator: ", ")
    }

    private func markColour(_ answer: FixtureAnswer?, onColour: Bool) -> Color {
        switch answer {
        case .going: return onColour ? .white : FishersTheme.available
        case .maybe: return FishersTheme.accent400
        case .notGoing: return onColour ? .black.opacity(0.5) : FishersTheme.unavailable
        case nil: return onColour ? .white.opacity(0.6) : .secondary
        }
    }

    private func color(for status: AvailabilityStatus?) -> Color {
        switch status {
        case .available: return FishersTheme.available
        case .maybe: return FishersTheme.maybe
        case .unavailable: return FishersTheme.unavailable
        case nil: return FishersTheme.accent
        }
    }
}
