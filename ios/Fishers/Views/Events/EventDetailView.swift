import SwiftUI

struct EventDetailView: View {
    let eventId: UUID

    @State private var event: Event?
    @State private var attendees: [AttendeeSummary] = []
    @State private var message: String?
    @State private var showSquad = false
    @State private var board: SelectionBoard?
    @State private var isResponding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let event {
                    header(event)
                    selectionCard(event)
                    rsvpRow
                    paymentRow(event)
                    attendeesSection
                    if event.eventSubtype == "friendly" || event.eventSubtype == "league_match" {
                        NavigationLink {
                            SelectionBoardView(eventId: eventId)
                        } label: {
                            Label("Selection board", systemImage: "person.3.sequence.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(FishersTheme.accent)
                        Button("Squad picker") { showSquad = true }
                            .buttonStyle(.bordered)
                    }
                } else {
                    ProgressView()
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(FishersTheme.mist.ignoresSafeArea())
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showSquad) {
            SquadPickerView(attendees: attendees)
        }
    }

    /// Shown to a player once they are picked: confirm or pull out, well before
    /// the morning of the game.
    @ViewBuilder
    private func selectionCard(_ event: Event) -> some View {
        if let board, let me = myPlace(in: board) {
            VStack(alignment: .leading, spacing: 10) {
                Label(headline(for: me.state), systemImage: icon(for: me.state))
                    .font(.headline)
                    .foregroundStyle(FishersTheme.accent)
                if me.state == .selected || me.state == .confirmed {
                    Text("Confirm at least \(board.confirmLeadHours)h before start. Unconfirmed places go to reserves \(board.dropLeadHours)h before.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if me.state != .confirmed {
                    HStack {
                        Button("I'm playing") { Task { await respond(true) } }
                            .buttonStyle(.borderedProminent)
                            .tint(FishersTheme.available)
                        Button("Can't make it") { Task { await respond(false) } }
                            .buttonStyle(.bordered)
                    }
                    .disabled(isResponding)
                } else {
                    Label("You're confirmed", systemImage: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundStyle(FishersTheme.available)
                    Button("Actually, I can't make it") { Task { await respond(false) } }
                        .font(.footnote)
                        .buttonStyle(.plain)
                        .foregroundStyle(FishersTheme.unavailable)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func myPlace(in board: SelectionBoard) -> SelectionCandidate? {
        // The board only carries club members; find the row for this device's user.
        guard let userId = KeychainStore.get("user_id").flatMap(UUID.init(uuidString:)) else {
            return board.candidates.first { $0.state == .selected || $0.state == .confirmed }
        }
        return board.candidates.first { $0.userId == userId }
    }

    private func headline(for state: SelectionState) -> String {
        switch state {
        case .selected: return "You're picked"
        case .confirmed: return "You're in"
        case .reserve: return "You're on standby"
        case .dropped: return "Your place went to a reserve"
        case .declined: return "You said you can't make it"
        case .notSelected: return "Not selected this time"
        case .pool: return "You're in the mix"
        }
    }

    private func icon(for state: SelectionState) -> String {
        switch state {
        case .confirmed: return "checkmark.seal.fill"
        case .selected: return "hand.raised.fill"
        case .reserve: return "clock.arrow.circlepath"
        default: return "person.crop.circle"
        }
    }

    private func respond(_ confirming: Bool) async {
        isResponding = true
        defer { isResponding = false }
        do {
            try await FishersAPI.respondToSelection(eventId: eventId, confirming: confirming)
            board = try? await FishersAPI.selectionBoard(eventId: eventId)
            message = confirming ? "Confirmed — see you there." : "Thanks for letting us know."
        } catch {
            message = error.localizedDescription
        }
    }

    private func header(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title)
                .font(FishersTheme.title)
            Text("\(event.sport.capitalized) · \(event.eventSubtype.replacingOccurrences(of: "_", with: " "))")
                .foregroundStyle(FishersTheme.accent)
            Text(event.startAt.formatted(date: .abbreviated, time: .shortened)
                 + " – "
                 + event.endAt.formatted(date: .omitted, time: .shortened))
                .foregroundStyle(.secondary)
            if let cap = event.capacity {
                Text("Capacity \(attendees.filter { $0.status == .going }.count)/\(cap)")
                    .font(.subheadline)
            }
        }
    }

    private var rsvpRow: some View {
        HStack(spacing: 10) {
            rsvpButton("Going", .going)
            rsvpButton("Maybe", .maybe)
            rsvpButton("Can't", .notGoing)
        }
    }

    private func rsvpButton(_ title: String, _ status: RsvpStatus) -> some View {
        Button(title) {
            Task {
                do {
                    try await FishersAPI.rsvp(eventId: eventId, status: status)
                    message = "RSVP updated"
                    await load()
                } catch {
                    message = error.localizedDescription
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private func paymentRow(_ event: Event) -> some View {
        Group {
            if let fee = event.feeAmountCents, fee > 0 {
                Button {
                    Task {
                        do {
                            let intent = try await FishersAPI.paymentIntent(eventId: eventId, amountCents: fee)
                            message = "Payment ready (\(intent.clientSecret.prefix(18))…)"
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Pay \(String(format: "£%.2f", Double(fee) / 100))", systemImage: "creditcard")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(FishersTheme.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attendees")
                .font(.headline)
            ForEach(attendees) { a in
                HStack {
                    VStack(alignment: .leading) {
                        Text(a.name)
                        if let avail = a.availability {
                            Text("Calendar: \(avail.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(a.status.rawValue.replacingOccurrences(of: "_", with: " "))
                        .font(.caption.weight(.semibold))
                    if a.paid {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(FishersTheme.available)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func load() async {
        do {
            async let e = FishersAPI.event(id: eventId)
            async let a = FishersAPI.attendees(eventId: eventId)
            (event, attendees) = try await (e, a)
            // Selection may not apply to this fixture (nets, socials) — a
            // failure here shouldn't blank the screen.
            board = try? await FishersAPI.selectionBoard(eventId: eventId)
        } catch {
            message = error.localizedDescription
        }
    }
}
