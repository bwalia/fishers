import SwiftUI

struct HomeFeedView: View {
    @State private var events: [Event] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                FishersTheme.mist.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Upcoming")
                            .font(FishersTheme.title)
                            .foregroundStyle(FishersTheme.ink)

                        if events.isEmpty {
                            Text("No sessions yet. Join a club or create Wednesday nets.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(events) { event in
                                NavigationLink(value: event) {
                                    EventRow(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Home")
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
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FishersTheme.pitch.gradient)
                .frame(width: 4)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .foregroundStyle(FishersTheme.ink)
                Text(event.eventSubtype.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundStyle(FishersTheme.accent)
                Text(event.startAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let fee = event.feeAmountCents {
                Text(String(format: "£%.0f", Double(fee) / 100))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FishersTheme.ink)
            }
        }
        .padding()
        .background(FishersTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
