import SwiftUI

/// The Calendar tab: the emotional core of the app. One tap on a day cycles
/// your availability; club events overlay as dots so fixtures sit against
/// your own free time at a glance.
struct CalendarTabView: View {
    @Environment(AppState.self) private var app
    @State private var viewModel = CalendarViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    if viewModel.viewMode == .month {
                        AvailabilityCalendarView(viewModel: viewModel) { day in
                            viewModel.tap(day: day, api: app.api)
                        }
                    } else {
                        weekStrip
                    }

                    legend

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    eventList
                }
                .padding(.horizontal)
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Event.self) { event in
                EventDetailView(event: event)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") { viewModel.goToToday() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        CricketSeasonView()
                    } label: {
                        Label("Cricket Season", systemImage: "figure.cricket")
                    }
                }
            }
            .task {
                await viewModel.load(api: app.api)
            }
            .refreshable {
                await viewModel.load(api: app.api)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Picker("View", selection: $viewModel.viewMode) {
                ForEach(CalendarViewModel.ViewMode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)

            HStack {
                Button { viewModel.step(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(viewModel.monthTitle)
                    .font(.headline)
                Spacer()
                Button { viewModel.step(1) } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.horizontal, 4)

            Toggle(isOn: $viewModel.cricketSeasonOnly) {
                Label("Cricket only", systemImage: "figure.cricket")
                    .font(.subheadline)
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.weekDays, id: \.self) { day in
                DayCell(
                    day: day,
                    status: viewModel.status(for: day),
                    eventCount: viewModel.events(on: day).count,
                    isToday: viewModel.isToday(day),
                    isSelected: viewModel.isSelected(day),
                    isInMonth: true,
                    compact: false
                )
                .onTapGesture { viewModel.tap(day: day, api: app.api) }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(AvailabilityStatus.allCases, id: \.self) { status in
                Label(status.label, systemImage: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(status.color)
            }
            Spacer()
            Text("Tap a day to cycle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var eventList: some View {
        let events = viewModel.viewMode == .month ? viewModel.selectedDayEvents : viewModel.weekEvents
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.viewMode == .month
                 ? viewModel.selectedDay.formatted(.dateTime.weekday(.wide).day().month())
                 : "This week")
                .font(.headline)

            if events.isEmpty {
                Text("No events")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(events) { event in
                    NavigationLink(value: event) {
                        EventRow(event: event)
                            .padding(10)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 24)
    }
}

/// Custom month grid built on LazyVGrid: colour-coded availability circles,
/// event dots, dimmed out-of-month padding cells.
struct AvailabilityCalendarView: View {
    let viewModel: CalendarViewModel
    let onTap: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(viewModel.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(viewModel.monthCells.enumerated()), id: \.offset) { _, cell in
                    if let day = cell {
                        DayCell(
                            day: day,
                            status: viewModel.status(for: day),
                            eventCount: viewModel.events(on: day).count,
                            isToday: viewModel.isToday(day),
                            isSelected: viewModel.isSelected(day),
                            isInMonth: true,
                            compact: true
                        )
                        .onTapGesture { onTap(day) }
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }
}

struct DayCell: View {
    let day: Date
    let status: AvailabilityStatus?
    let eventCount: Int
    let isToday: Bool
    let isSelected: Bool
    let isInMonth: Bool
    let compact: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(day, format: .dateTime.day())
                .font(.subheadline.weight(isToday ? .bold : .regular))
                .foregroundStyle(foreground)
                .frame(width: 32, height: 32)
                .background(background, in: Circle())
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    } else if isToday {
                        Circle().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                    }
                }

            HStack(spacing: 2) {
                ForEach(0..<min(eventCount, 3), id: \.self) { _ in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .contentShape(Rectangle())
        .opacity(isInMonth ? 1 : 0.3)
    }

    private var background: Color {
        guard let status else { return .clear }
        return status.color.opacity(0.85)
    }

    private var foreground: Color {
        status == nil ? .primary : .white
    }
}

#Preview {
    CalendarTabView()
        .environment(AppState(demoMode: true))
}
