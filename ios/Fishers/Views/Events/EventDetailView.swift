import SwiftUI

struct EventDetailView: View {
    let eventId: UUID

    @State private var event: Event?
    @State private var attendees: [AttendeeSummary] = []
    @State private var message: String?
    @State private var showSquad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let event {
                    header(event)
                    rsvpRow
                    paymentRow(event)
                    attendeesSection
                    if event.eventSubtype == "friendly" || event.eventSubtype == "league_match" {
                        Button("Squad picker") { showSquad = true }
                            .buttonStyle(.borderedProminent)
                            .tint(FishersTheme.accent)
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
        } catch {
            message = error.localizedDescription
        }
    }
}
