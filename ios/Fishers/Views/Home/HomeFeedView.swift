import SwiftUI

struct HomeFeedView: View {
    @State private var events: [Event] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                FishersTheme.mist.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Upcoming")
                            .fishersTitle()

                        Text("Nets, league and socials for your clubs.")
                            .font(FishersTheme.footnote)
                            .foregroundStyle(FishersTheme.muted)

                        if let error {
                            Text(error)
                                .font(FishersTheme.footnote)
                                .foregroundStyle(FishersTheme.unavailable)
                        }

                        if events.isEmpty {
                            emptyState
                        } else {
                            ForEach(events) { event in
                                NavigationLink(value: event) {
                                    EventRow(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Event.self) { EventDetailView(eventId: $0.id) }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No sessions yet")
                .font(FishersTheme.headline)
                .foregroundStyle(FishersTheme.ink)
            Text("Join a club or add sample fixtures from the Clubs tab.")
                .font(FishersTheme.callout)
                .foregroundStyle(FishersTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FishersTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(FishersTheme.headline)
                    .foregroundStyle(FishersTheme.ink)
                    .lineLimit(2)

                Text(event.eventSubtype.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(FishersTheme.overline)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(FishersTheme.accent)

                Text(event.startAt.formatted(date: .abbreviated, time: .shortened))
                    .font(FishersTheme.subhead)
                    .foregroundStyle(FishersTheme.muted)
            }
            Spacer(minLength: 8)
            if let fee = event.feeAmountCents {
                Text(String(format: "£%.0f", Double(fee) / 100))
                    .font(FishersTheme.headline)
                    .foregroundStyle(FishersTheme.ink)
                    .monospacedDigit()
            }
        }
        .padding(16)
        .background(FishersTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(FishersTheme.ink.opacity(0.04), lineWidth: 1)
        )
    }
}
