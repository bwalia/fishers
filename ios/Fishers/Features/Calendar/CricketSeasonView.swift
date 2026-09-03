import SwiftUI

/// "Cricket Season" view: every nets session and game from April to September,
/// grouped by month, so members see the whole summer at a glance.
struct CricketSeasonView: View {
    @Environment(AppState.self) private var app
    @State private var events: [Event] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var grouped: [(month: String, events: [Event])] {
        let groups = Dictionary(grouping: events) { event in
            event.startAt.formatted(.dateTime.month(.wide).year())
        }
        return groups
            .map { (month: $0.key, events: $0.value.sorted { $0.startAt < $1.startAt }) }
            .sorted { ($0.events.first?.startAt ?? .distantPast) < ($1.events.first?.startAt ?? .distantPast) }
    }

    var body: some View {
        List {
            if let errorMessage {
                ErrorBanner(message: errorMessage).listRowInsets(EdgeInsets())
            }
            if events.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No cricket scheduled",
                    systemImage: "figure.cricket",
                    description: Text("Nets and matches from April to September will appear here.")
                )
            }
            ForEach(grouped, id: \.month) { group in
                Section(group.month) {
                    ForEach(group.events) { event in
                        NavigationLink(value: event) {
                            EventRow(event: event)
                        }
                    }
                }
            }
        }
        .navigationTitle("Cricket Season")
        .navigationDestination(for: Event.self) { event in
            EventDetailView(event: event)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let from = calendar.date(from: DateComponents(year: year, month: 4, day: 1))!
        let to = calendar.date(from: DateComponents(year: year, month: 9, day: 30))!
        do {
            let all = try await app.api.events(clubId: nil, teamId: nil, from: from, to: to)
            events = all.filter { $0.isCricket }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        CricketSeasonView()
    }
    .environment(AppState(demoMode: true))
}
