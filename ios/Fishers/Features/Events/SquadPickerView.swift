import SwiftUI

/// Captain-only, availability-aware roster builder. Players are ordered by
/// their RSVP for the event; tapping moves them into the XI (first eleven)
/// and then reserves.
struct SquadPickerView: View {
    @Environment(AppState.self) private var app
    let event: Event

    @State private var pool: [Attendee] = []
    @State private var selectedIds: [UUID] = []
    @State private var errorMessage: String?
    @State private var showSavedConfirmation = false

    private var startingXI: [Attendee] {
        selectedIds.prefix(11).compactMap { id in pool.first { $0.id == id } }
    }

    private var reserves: [Attendee] {
        selectedIds.dropFirst(11).compactMap { id in pool.first { $0.id == id } }
    }

    private var unselected: [Attendee] {
        pool.filter { !selectedIds.contains($0.id) }
            .sorted { rank($0.status) < rank($1.status) }
    }

    private func rank(_ status: RSVPStatus) -> Int {
        switch status {
        case .going: return 0
        case .maybe: return 1
        case .notGoing: return 2
        }
    }

    var body: some View {
        List {
            if let errorMessage {
                Section { ErrorBanner(message: errorMessage).listRowInsets(EdgeInsets()) }
            }

            Section {
                availabilitySummary
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section("Starting XI · \(startingXI.count)/11") {
                if startingXI.isEmpty {
                    Text("Tap players below to build the XI.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(startingXI) { attendee in
                    PlayerRow(attendee: attendee, selectionLabel: xiNumber(for: attendee))
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(attendee) }
                }
            }

            if !reserves.isEmpty {
                Section("Reserves") {
                    ForEach(reserves) { attendee in
                        PlayerRow(attendee: attendee, selectionLabel: "R")
                            .contentShape(Rectangle())
                            .onTapGesture { toggle(attendee) }
                    }
                }
            }

            Section("Available pool") {
                if unselected.isEmpty {
                    Text("Everyone is selected.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(unselected) { attendee in
                    PlayerRow(attendee: attendee, selectionLabel: nil)
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(attendee) }
                }
            }
        }
        .navigationTitle("Pick Squad")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { showSavedConfirmation = true }
                    .disabled(startingXI.isEmpty)
            }
        }
        .alert("Squad saved", isPresented: $showSavedConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(startingXI.count) in the XI, \(reserves.count) reserve\(reserves.count == 1 ? "" : "s"). Syncing squads to the server lands with the match-results backend work.")
        }
        .task { await load() }
    }

    private var availabilitySummary: some View {
        let going = pool.filter { $0.status == .going }.count
        let maybe = pool.filter { $0.status == .maybe }.count
        let out = pool.filter { $0.status == .notGoing }.count
        return HStack(spacing: 16) {
            summaryPill(count: going, label: "Available", color: .green)
            summaryPill(count: maybe, label: "Maybe", color: .orange)
            summaryPill(count: out, label: "Out", color: .red)
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryPill(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func xiNumber(for attendee: Attendee) -> String? {
        guard let index = selectedIds.firstIndex(of: attendee.id), index < 11 else { return nil }
        return "\(index + 1)"
    }

    private func toggle(_ attendee: Attendee) {
        if let index = selectedIds.firstIndex(of: attendee.id) {
            selectedIds.remove(at: index)
        } else {
            selectedIds.append(attendee.id)
        }
    }

    private func load() async {
        do {
            // The event-date player pool: RSVP responses double as availability here.
            var list = try await app.api.attendees(eventId: event.id)
            // Fold in club members who haven't responded, so the captain sees everyone.
            let members = try await app.api.members(clubId: event.clubId)
            let responded = Set(list.map(\.id))
            for member in members {
                if let user = member.user, !responded.contains(user.id) {
                    list.append(Attendee(user: user, status: .notGoing, hasPaid: false))
                }
            }
            pool = list
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PlayerRow: View {
    let attendee: Attendee
    let selectionLabel: String?

    var body: some View {
        HStack(spacing: 10) {
            if let selectionLabel {
                Text(selectionLabel)
                    .font(.caption.bold())
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor, in: Circle())
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            AvatarView(user: attendee.user, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(attendee.user.name).font(.subheadline)
                HStack(spacing: 4) {
                    if let position = attendee.user.position {
                        Text(position)
                    }
                    if let skill = attendee.user.skillLevel {
                        Text("· \(skill)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: attendee.status.systemImage)
                .foregroundStyle(attendee.status.color)
        }
    }
}

#Preview {
    NavigationStack {
        SquadPickerView(event: MockData.events.first(where: { $0.eventSubtype == .friendly })!)
    }
    .environment(AppState(demoMode: true))
}
