import SwiftUI

/// A ticketed club event — the dinner, the quiz, presentation night.
///
/// Two jobs on one screen, because they are the same conversation: book your
/// own place and bring people, and — if you are running it — see the headcount
/// and who still owes.
struct EventTicketsView: View {
    let eventId: UUID
    /// Can record cash at the door.
    var canManage = false

    @State private var booking: TicketBooking?
    @State private var guests = 0
    @State private var guestNames = ""
    @State private var notes = ""
    @State private var busy: String?
    @State private var note: String?
    @State private var error: String?

    private var myId: UUID? { KeychainStore.get("user_id").flatMap(UUID.init(uuidString:)) }

    var body: some View {
        List {
            if let booking {
                let summary = booking.summary
                let mine = booking.tickets.first { $0.userId == myId && $0.status != "cancelled" }
                let left = summary.placesLeft

                Section {
                    HStack(spacing: 8) {
                        figure("Coming", "\(summary.headcount)")
                        figure("Places left", left.map(String.init) ?? "—")
                        figure("Each", summary.ticketPriceCents.map(money) ?? "Free")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if let note {
                    Section { Label(note, systemImage: "checkmark.circle.fill").foregroundStyle(FishersTheme.pitch) }
                }
                if let error {
                    Section { Text(error).foregroundStyle(FishersTheme.unavailable) }
                }

                if let mine {
                    Section {
                        LabeledContent("Places", value: "\(mine.places)")
                        if let names = mine.guestNames { LabeledContent("Bringing", value: names) }
                        LabeledContent("To pay", value: money(mine.amountCents))
                        LabeledContent("Status", value: mine.status.capitalized)
                        if !mine.isPaid {
                            Button {
                                act("pay", "Payment opened — your club confirms it once it clears.") {
                                    _ = try await FishersAPI.payTicket(mine.id)
                                }
                            } label: {
                                Text(busy == "pay" ? "Opening…" : "Pay \(money(mine.amountCents))")
                                    .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy != nil)
                        }
                        Button("Cancel my place", role: .destructive) {
                            act("cancel", "Booking cancelled.") { _ = try await FishersAPI.cancelTicket(mine.id) }
                        }
                        .disabled(busy != nil)
                    } header: {
                        Text("You are booked")
                    }
                } else {
                    Section {
                        if let left, left <= 0 {
                            Text("Sold out. Ask your secretary whether there is a list.").foregroundStyle(.secondary)
                        } else {
                            let allowed = summary.guestsAllowed ?? 0
                            if allowed > 0 {
                                Stepper("Bringing \(guests) \(guests == 1 ? "guest" : "guests")", value: $guests, in: 0...allowed)
                                if guests > 0 {
                                    TextField("Names, so the table plan works", text: $guestNames)
                                }
                            } else {
                                Text("Members only — no guests at this one.").font(FishersTheme.footnote).foregroundStyle(.secondary)
                            }
                            TextField("Anything the club should know", text: $notes)
                            Button {
                                let places = 1 + guests
                                act("book", "Booked \(places) \(places == 1 ? "place" : "places").") {
                                    _ = try await FishersAPI.bookTicket(
                                        eventId: eventId, guests: guests,
                                        guestNames: guestNames.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                                        notes: notes.trimmingCharacters(in: .whitespaces).nilIfEmpty
                                    )
                                }
                            } label: {
                                Text(busy == "book" ? "Booking…" : "Book \(1 + guests) \(guests == 0 ? "place" : "places")")
                                    .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy != nil)
                        }
                    } header: {
                        Text("Book a place")
                    }
                }

                // Who else is coming is club business. At an event open to
                // anyone, a visitor gets the headcount and their own booking;
                // the server sends them no more than that, so listing it here
                // would show "12 bookings" above a list of one.
                if booking.insider {
                    Section {
                        if booking.tickets.isEmpty {
                            Text("Nobody yet. Be the first.").foregroundStyle(.secondary)
                        }
                        ForEach(booking.tickets) { ticket in
                            HStack(spacing: 12) {
                                AvatarView(name: ticket.name ?? "A member", size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ticket.name ?? "A member")
                                        .strikethrough(ticket.status == "cancelled")
                                    if ticket.guests > 0 {
                                        Text("+\(ticket.guests)\(ticket.guestNames.map { " — \($0)" } ?? "")")
                                            .font(FishersTheme.footnote).foregroundStyle(.secondary)
                                    }
                                    if let notes = ticket.notes {
                                        Text(notes).font(FishersTheme.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(ticket.status.capitalized)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(ticket.isPaid ? FishersTheme.pitch : .secondary)
                            }
                            // Cash at the door is how most club events are paid for;
                            // whoever is collecting records it without a card reader.
                            .swipeActions(edge: .trailing) {
                                if canManage && ticket.status == "reserved" {
                                    Button("Cash") { markPaid(ticket, "cash") }.tint(FishersTheme.pitch)
                                    Button("Transfer") { markPaid(ticket, "transfer") }.tint(FishersTheme.gold700)
                                }
                            }
                        }
                    } header: {
                        Text("Who is coming · \(summary.bookings) bookings")
                    } footer: {
                        if canManage {
                            Text("Taken \(money(summary.collectedCents)) · owed \(money(summary.outstandingCents)). Swipe a booking to mark it paid.")
                        }
                    }
                }
            } else if let error {
                Text(error).foregroundStyle(FishersTheme.unavailable)
            } else {
                ProgressView()
            }
        }
        .fishersList()
        .navigationTitle(booking?.summary.title ?? "Tickets")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(FishersTheme.figure(.title3)).foregroundStyle(FishersTheme.pitch)
            Text(label).font(FishersTheme.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(FishersTheme.cream, in: RoundedRectangle(cornerRadius: 12))
    }

    private func money(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: "GBP"))
    }

    private func markPaid(_ ticket: EventTicket, _ method: String) {
        act(ticket.id.uuidString, "\(ticket.name ?? "That booking") marked paid.") {
            try await FishersAPI.markTicketPaid(ticket.id, method: method)
        }
    }

    private func act(_ what: String, _ said: String, _ run: @escaping () async throws -> Void) {
        Task {
            busy = what
            error = nil
            note = nil
            defer { busy = nil }
            do {
                try await run()
                note = said
                await load()
            } catch {
                self.error = (error as? APIError)?.friendlyMessage ?? "That did not work"
            }
        }
    }

    private func load() async {
        do {
            booking = try await FishersAPI.tickets(eventId: eventId)
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? "Could not load the tickets"
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
