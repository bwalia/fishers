import SwiftUI

struct HomeFeedView: View {
    @State private var events: [Event] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty && error == nil {
                    ContentUnavailableView {
                        Label("No sessions yet", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Join a club or add sample fixtures from the Clubs tab.")
                    }
                } else {
                    List {
                        if let error {
                            Section {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                        Section {
                            ForEach(events) { event in
                                NavigationLink(value: event) {
                                    EventRow(event: event)
                                }
                            }
                        } header: {
                            Text("Upcoming")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ShopView()
                    } label: {
                        Image(systemName: "bag")
                    }
                    .accessibilityLabel("Shop")
                }
            }
            .navigationDestination(for: Event.self) { EventDetailView(eventId: $0.id) }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            events = try await FishersAPI.events()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct EventRow: View {
    let event: Event

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FishersTheme.space2) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(event.eventSubtype.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundStyle(FishersTheme.accent)
                Text(event.startAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let fee = event.feeAmountCents {
                Text(String(format: "£%.0f", Double(fee) / 100))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Fee \(String(format: "£%.0f", Double(fee) / 100))")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
