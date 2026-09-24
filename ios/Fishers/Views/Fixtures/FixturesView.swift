import SwiftUI

/// Where a fixture row leads.
struct FixtureRoute: Hashable {
    let eventId: UUID
}

/// The Fixtures tab: every fixture of every club you are in, as a list or as
/// your calendar, each asking the one thing it needs from you — can you play?
struct FixturesView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case list = "List", calendar = "Calendar", scores = "Scores"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .list

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch mode {
                case .list: FixturesListPane()
                case .calendar: CalendarPane()
                case .scores: ScoreHubPane()
                }
            }
            .background(FishersTheme.mist.ignoresSafeArea())
            .navigationTitle("Fixtures")
            .navigationDestination(for: FixtureRoute.self) { EventDetailView(eventId: $0.eventId) }
            .navigationDestination(for: Event.self) { EventDetailView(eventId: $0.id) }
        }
    }
}

/// "Can you play?" — Available, Maybe or Can't play, showing what you said and
/// letting you change it. Saved as you tap; put back if it does not save.
struct FixtureAnswerControl: View {
    let eventId: UUID
    @Binding var answer: FixtureAnswer?
    var title = "Can you play?"

    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(FixtureAnswer.allCases) { option in
                    let on = answer == option
                    Button {
                        Task { await choose(option) }
                    } label: {
                        Text(option.label)
                            .font(FishersTheme.subhead.weight(on ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(on ? .white : .primary)
                            .background(on ? tint(option) : FishersTheme.raised, in: Capsule())
                    }
                    // Borderless: inside a list row a default button claims the row.
                    .buttonStyle(.borderless)
                    .disabled(busy)
                    .accessibilityLabel("\(option.label)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            if let error {
                Text(error).font(FishersTheme.footnote).foregroundStyle(FishersTheme.unavailable)
            }
        }
    }

    private func tint(_ option: FixtureAnswer) -> Color {
        switch option {
        case .going: return FishersTheme.available
        case .maybe: return FishersTheme.maybe
        case .notGoing: return FishersTheme.unavailable
        }
    }

    private func choose(_ next: FixtureAnswer) async {
        guard next != answer, !busy else { return }
        let before = answer
        answer = next
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await FishersAPI.rsvp(eventId: eventId, status: next.rsvp)
        } catch {
            answer = before
            self.error = (error as? APIError)?.friendlyMessage ?? "That did not save — try again"
        }
    }
}

// MARK: - The list

struct FixturesListPane: View {
    enum Show: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming", unanswered = "To answer", past = "Past"
        var id: String { rawValue }
    }

    @State private var fixtures: [MyFixture]?
    @State private var past: [MyFixture]?
    @State private var show: Show = .upcoming
    @State private var clubFilter: UUID?
    @State private var schedulable: [Club] = []
    @State private var scheduling = false
    @State private var error: String?
    @AppStorage("fishers:fixtures-guide-dismissed") private var guideDismissed = false

    private var upcoming: [MyFixture] { fixtures ?? [] }
    private var unanswered: [MyFixture] { upcoming.filter { $0.myAnswer == nil } }
    private var playing: [MyFixture] { upcoming.filter { $0.myAnswer == .going } }

    private var source: [MyFixture] {
        switch show {
        case .upcoming: return upcoming
        case .unanswered: return unanswered
        case .past: return past ?? []
        }
    }

    private var shown: [MyFixture] {
        guard let clubFilter else { return source }
        return source.filter { $0.clubId == clubFilter || $0.opponentClubId == clubFilter }
    }

    private var clubs: [(UUID, String)] {
        var seen: [UUID: String] = [:]
        for f in upcoming + (past ?? []) { seen[f.clubId] = f.clubName }
        return seen.sorted { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            if !guideDismissed {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        guideLine("1", "Say whether you can play", "Tap Available, Maybe or Can't play on each fixture.")
                        guideLine("2", "The captain picks the side", "From who said they are available.")
                        guideLine("3", "You hear if you're in", "A notification when the squad is published.")
                    }
                    .padding(.vertical, 4)
                } header: {
                    HStack {
                        Text("How fixtures work")
                        Spacer()
                        Button("Got it") { guideDismissed = true }
                            .font(FishersTheme.footnote)
                            .textCase(nil)
                    }
                }
            }

            if fixtures != nil {
                Section {
                    HStack(spacing: 8) {
                        tile("Upcoming", upcoming.count, .upcoming)
                        tile("To answer", unanswered.count, .unanswered)
                        tile("Playing", playing.count, .upcoming)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                Picker("Which fixtures", selection: $show) {
                    ForEach(Show.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            if let error {
                Section { Text(error).foregroundStyle(FishersTheme.unavailable) }
            }

            let clashing = FixtureList.clashes(upcoming)
            ForEach(FixtureList.byDay(shown), id: \.day) { day in
                Section(FixtureList.dayTitle(day.day)) {
                    ForEach(day.fixtures) { fixture in
                        FixtureRow(
                            fixture: fixture,
                            clashes: clashing.contains(fixture.eventId),
                            isPast: show == .past,
                            answer: binding(for: fixture)
                        )
                    }
                }
            }

            if fixtures != nil && shown.isEmpty {
                ContentUnavailableView {
                    Label(show == .unanswered ? "Nothing to answer" : "No fixtures", systemImage: "calendar")
                } description: {
                    Text(show == .unanswered
                         ? "You've answered every upcoming fixture."
                         : show == .past ? "No fixtures in the last four months." : "Nothing in the diary for your clubs yet.")
                }
            }
        }
        .fishersList()
        .overlay { if fixtures == nil && error == nil { ProgressView() } }
        .toolbar {
            if clubs.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Club", selection: $clubFilter) {
                            Text("All clubs").tag(UUID?.none)
                            ForEach(clubs, id: \.0) { Text($0.1).tag(Optional($0.0)) }
                        }
                    } label: {
                        Image(systemName: clubFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Which club")
                }
            }
            if !schedulable.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button { scheduling = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Schedule a match")
                }
            }
        }
        .sheet(isPresented: $scheduling) {
            ScheduleMatchSheet(clubs: schedulable) { Task { await load() } }
        }
        .task { await load() }
        .task { await loadSchedulable() }
        .onChange(of: show) { _, now in
            if now == .past, past == nil { Task { await loadPast() } }
        }
        .refreshable {
            await load()
            if show == .past { await loadPast() }
        }
    }

    private func binding(for fixture: MyFixture) -> Binding<FixtureAnswer?> {
        Binding(
            get: { (fixtures ?? []).first { $0.eventId == fixture.eventId }?.myAnswer ?? fixture.myAnswer },
            set: { value in
                if let index = fixtures?.firstIndex(where: { $0.eventId == fixture.eventId }) {
                    fixtures?[index].myAnswer = value
                }
            }
        )
    }

    private func guideLine(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(FishersTheme.caption).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(FishersTheme.pitch, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(FishersTheme.headline)
                Text(detail).font(FishersTheme.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tile(_ label: String, _ value: Int, _ target: Show) -> some View {
        Button {
            show = target
        } label: {
            VStack(spacing: 2) {
                Text("\(value)").font(FishersTheme.figure(.title2)).foregroundStyle(FishersTheme.pitch)
                Text(label).font(FishersTheme.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(FishersTheme.cream, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(value)")
    }

    private func load() async {
        do {
            // From a few hours back, so a match on now is still here.
            fixtures = try await FishersAPI.myFixtures(
                from: .now.addingTimeInterval(-6 * 3600), to: .now.addingTimeInterval(180 * 86400)
            )
            error = nil
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
    }

    private func loadPast() async {
        past = ((try? await FishersAPI.myFixtures(from: .now.addingTimeInterval(-120 * 86400), to: .now)) ?? []).reversed()
    }

    /// Only somebody who can put a match in a club's diary sees the button.
    private func loadSchedulable() async {
        let clubs = (try? await FishersAPI.clubs()) ?? []
        var can: [Club] = []
        for club in clubs {
            if let role = try? await FishersAPI.myClubRole(clubId: club.id), role.permissions.contains("manage_events") {
                can.append(club)
            }
        }
        schedulable = can
    }
}

/// One fixture: what, when, where, who — and your answer.
struct FixtureRow: View {
    let fixture: MyFixture
    let clashes: Bool
    let isPast: Bool
    @Binding var answer: FixtureAnswer?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: FixtureRoute(eventId: fixture.eventId)) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: fixture.systemImage)
                        .foregroundStyle(FishersTheme.pitch)
                        .frame(width: 28, height: 28)
                        .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fixture.title).font(FishersTheme.contentTitle).lineLimit(2)
                        Text([fixture.startAt.formatted(date: .omitted, time: .shortened), fixture.venueName, fixture.clubName]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(FishersTheme.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            if fixture.isCancelled || fixture.isPostponed {
                                tag(fixture.status.capitalized, FishersTheme.unavailable)
                            }
                            if clashes {
                                Label("Clashes with another you're playing", systemImage: "exclamationmark.triangle.fill")
                                    .font(FishersTheme.caption)
                                    .foregroundStyle(FishersTheme.maybe)
                            }
                            if let price = fixture.ticketPriceCents {
                                tag("Tickets £\(price / 100)", FishersTheme.accent700)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isPast || fixture.isCancelled {
                Label(fixture.saidLabel, systemImage: answer?.systemImage ?? "circle")
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            } else {
                FixtureAnswerControl(eventId: fixture.eventId, answer: $answer, title: "Can you play \(fixture.title)?")
            }
        }
        .padding(.vertical, 6)
    }

    private func tag(_ text: String, _ colour: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colour.opacity(0.15), in: Capsule())
            .foregroundStyle(colour)
    }
}

// MARK: - Scheduling

struct ScheduleMatchSheet: View {
    let clubs: [Club]
    let onScheduled: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var clubId: UUID?
    @State private var venues: [Venue] = []
    @State private var venueId: UUID?
    @State private var opponent: ClubIdentity?
    @State private var oppositionName = ""
    @State private var picking = false
    @State private var start = Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: .now.addingTimeInterval(7 * 86400)) ?? .now
    @State private var busy = false
    @State private var error: String?

    private var club: Club? { clubs.first { $0.id == clubId } }
    private var theirName: String { opponent?.displayName ?? oppositionName.trimmingCharacters(in: .whitespaces) }

    /// Which piece is missing, in the order the form asks for them — a dead
    /// button with no explanation reads as a broken app.
    private var missing: String? {
        var parts: [String] = []
        if club == nil { parts.append("which of your clubs is playing") }
        if theirName.isEmpty { parts.append("who you are playing") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your side") {
                    Picker("Club", selection: $clubId) {
                        ForEach(clubs) { Text($0.name).tag(Optional($0.id)) }
                    }
                }

                Section {
                    if venues.isEmpty {
                        Text("No grounds saved for this club yet. Add them on the club's page and they show up here.")
                            .font(FishersTheme.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Ground", selection: $venueId) {
                            Text("Not decided yet").tag(UUID?.none)
                            ForEach(venues) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                } header: {
                    Text("Where")
                }

                Section {
                    Button {
                        picking = true
                    } label: {
                        LabeledContent("Opposition", value: theirName.isEmpty ? "Choose…" : theirName)
                    }
                } header: {
                    Text("The opposition")
                } footer: {
                    Text(opponent != nil
                         ? "\(opponent!.clubName) are on \(Brand.name) — their players get asked too."
                         : "A club on \(Brand.name) gets asked as well. Otherwise only your side is.")
                }

                Section("When") {
                    DatePicker("Date and time", selection: $start, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                }

                if let error {
                    Text(error).foregroundStyle(FishersTheme.unavailable)
                }

                Section {
                    Button {
                        Task { await schedule() }
                    } label: {
                        Group {
                            if busy { ProgressView() } else { Text("Schedule and ask who is available").font(FishersTheme.headline) }
                        }
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || missing != nil)
                    .listRowBackground(Color.clear)
                } footer: {
                    if let missing {
                        Text("Still needed: \(missing).")
                    } else {
                        Text("Everyone in \(opponent != nil ? "both clubs" : "your club") is asked whether they can play, and the captain hears each answer.")
                    }
                }
            }
            .navigationTitle("Schedule a match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $picking) {
                OppositionPickerView { name, identity in
                    oppositionName = name
                    opponent = identity
                    picking = false
                }
            }
            .task(id: clubId) {
                // The grounds belong to whichever club is hosting.
                venueId = nil
                guard let clubId else { return }
                venues = (try? await FishersAPI.venues(clubId: clubId)) ?? []
            }
            .onAppear { if clubId == nil { clubId = clubs.first?.id } }
        }
    }

    private func schedule() async {
        guard let club else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            _ = try await FishersAPI.createEvent(CreateEventBody(
                club_id: club.id,
                opponent_club_id: opponent?.clubId,
                team_id: nil,
                // What the club plays. Hard-coding cricket here filed every
                // fixture as a cricket match whatever the club turns out for.
                sport: club.sportTypes.first ?? "cricket",
                event_subtype: "league_match",
                title: "\(club.name) v \(theirName)",
                venue_id: venueId,
                start_at: start,
                // A cricket fixture runs most of an afternoon; nobody wants to
                // type an end time as well.
                end_at: start.addingTimeInterval(5 * 3600),
                recurrence_rule: nil,
                capacity: nil,
                fee_amount_cents: nil,
                metadata: nil
            ))
            onScheduled()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? "Could not schedule that"
        }
    }
}
