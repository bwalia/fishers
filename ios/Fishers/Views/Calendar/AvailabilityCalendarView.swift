import SwiftUI

/// Emotional core of Fishers — single-tap availability with event overlays.
struct AvailabilityCalendarView: View {
    @StateObject private var vm = CalendarViewModel()
    @State private var selectedDay: Date?
    @GestureState private var dragDays: Set<Date> = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        NavigationStack {
            ZStack {
                FishersTheme.mist.ignoresSafeArea()
                VStack(spacing: 16) {
                    header
                    weekdayHeader
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(vm.daysInMonth().enumerated()), id: \.offset) { _, day in
                            if let day {
                                dayCell(day)
                            } else {
                                Color.clear.frame(height: 44)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .updating($dragDays) { value, state, _ in
                                // Range select is applied on end via selectedDay stretch — lightweight UX hint.
                                _ = value
                                state = dragDays
                            }
                    )

                    Toggle("Cricket season (nets + games)", isOn: $vm.cricketSeasonOnly)
                        .padding(.horizontal)
                        .onChange(of: vm.cricketSeasonOnly) { _, _ in
                            Task { await vm.load() }
                        }

                    if let selectedDay {
                        dayDetail(selectedDay)
                    }

                    Spacer(minLength: 0)
                }
            }
            .navigationTitle("Calendar")
            .task { await vm.load() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                vm.month = Calendar.current.date(byAdding: .month, value: -1, to: vm.month) ?? vm.month
                Task { await vm.load() }
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(vm.month.formatted(.dateTime.month(.wide).year()))
                .font(FishersTheme.title)
                .foregroundStyle(FishersTheme.ink)
            Spacer()
            Button {
                vm.month = Calendar.current.date(byAdding: .month, value: 1, to: vm.month) ?? vm.month
                Task { await vm.load() }
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal)
        .foregroundStyle(FishersTheme.ink)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(weekdays, id: \.self) { d in
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
        let hasEvent = !vm.events(on: day).isEmpty
        return Button {
            selectedDay = day
            Task { await vm.toggle(day: day) }
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color(for: status).opacity(status == nil ? 0.15 : 0.85))
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(FishersTheme.subhead)
                    .foregroundStyle(status == nil ? FishersTheme.ink : .white)
                if hasEvent {
                    Circle()
                        .fill(.white)
                        .frame(width: 5, height: 5)
                        .padding(.bottom, 5)
                }
            }
            .frame(height: 44)
            .scaleEffect(selectedDay.map { Calendar.current.isDate($0, inSameDayAs: day) } == true ? 1.06 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: status)
        }
        .buttonStyle(.plain)
    }

    private func dayDetail(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day.formatted(date: .complete, time: .omitted))
                .font(FishersTheme.headline)
            let status = vm.days[Calendar.current.startOfDay(for: day)]
            Text(status?.label ?? "Tap a day to set availability")
                .foregroundStyle(.secondary)
            ForEach(vm.events(on: day)) { event in
                NavigationLink(value: event) {
                    EventRow(event: event)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FishersTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .navigationDestination(for: Event.self) { EventDetailView(eventId: $0.id) }
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
