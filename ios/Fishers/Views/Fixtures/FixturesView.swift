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
                Picker(tr("Show"), selection: $mode) {
                    ForEach(Mode.allCases) { Text(tr($0.rawValue)).tag($0) }
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
            .navigationTitle(t("ev.fixtures"))
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
            self.error = (error as? APIError)?.friendlyMessage ?? tr("That did not save — try again")
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
    @State private var scheduleAs: ScheduleKind = .match
    /// Nets or training just made, waiting for the sheet to close.
    @State private var scheduled: ScheduledSessions?
    @State private var opened: ScheduledSessions?
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
                        Text(t("ev.how_fixtures_work"))
                        Spacer()
                        Button(t("ev.got_it")) { guideDismissed = true }
                            .font(FishersTheme.footnote)
                            .textCase(nil)
                    }
                }
            }

            if fixtures != nil {
                Section {
                    HStack(spacing: 8) {
                        tile(tr("Upcoming"), upcoming.count, .upcoming)
                        tile(tr("To answer"), unanswered.count, .unanswered)
                        tile(tr("Playing"), playing.count, .upcoming)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                Picker(tr("Which fixtures"), selection: $show) {
                    ForEach(Show.allCases) { Text(tr($0.rawValue)).tag($0) }
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
                    Label(show == .unanswered ? tr("Nothing to answer") : tr("No fixtures"), systemImage: "calendar")
                } description: {
                    Text(show == .unanswered
                         ? tr("You've answered every upcoming fixture.")
                         : show == .past ? tr("No fixtures in the last four months.") : tr("Nothing in the diary for your clubs yet."))
                }
            }
        }
        .fishersList()
        .overlay { if fixtures == nil && error == nil { ProgressView() } }
        .toolbar {
            if clubs.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker(tr("Club"), selection: $clubFilter) {
                            Text(t("ev.all_clubs")).tag(UUID?.none)
                            ForEach(clubs, id: \.0) { Text($0.1).tag(Optional($0.0)) }
                        }
                    } label: {
                        Image(systemName: clubFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel(tr("Which club"))
                }
            }
            if !schedulable.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        scheduleAs = .nets
                        scheduling = true
                    } label: {
                        Image(systemName: "sportscourt")
                    }
                    .accessibilityLabel(t("np.schedule_nets_or_practice"))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        scheduleAs = .match
                        scheduling = true
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel(tr("Schedule a match"))
                }
            }
        }
        .sheet(isPresented: $scheduling, onDismiss: {
            // Open the first session once the sheet is out of the way.
            opened = scheduled
            scheduled = nil
        }) {
            ScheduleMatchSheet(
                clubs: schedulable,
                startAs: scheduleAs,
                onScheduled: { Task { await load() } },
                onSessions: { first, count in
                    Task { await load() }
                    scheduled = ScheduledSessions(eventId: first.id, count: count)
                }
            )
        }
        .navigationDestination(item: $opened) { EventDetailView(eventId: $0.eventId, notice: $0.notice) }
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
                            if let kind = Practice.label(fixture.eventSubtype) {
                                tag(kind, FishersTheme.pitch)
                            }
                            if fixture.isPractice, let week = Practice.weekOf(fixture.metadata) {
                                Text(week).font(FishersTheme.caption).foregroundStyle(.secondary)
                            }
                            if fixture.isCancelled || fixture.isPostponed {
                                tag(fixture.status.capitalized, FishersTheme.unavailable)
                            }
                            if clashes {
                                Label(t("ev.clashes_with_another"), systemImage: "exclamationmark.triangle.fill")
                                    .font(FishersTheme.caption)
                                    .foregroundStyle(FishersTheme.maybe)
                            }
                            if let price = fixture.ticketPriceCents {
                                tag("Tickets £\(price / 100)", FishersTheme.accent700)
                            }
                        }
                        if fixture.isPractice, let note = Practice.note(fixture.metadata) {
                            Text(note)
                                .font(FishersTheme.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isPast || fixture.isCancelled {
                Label(fixture.saidLabel, systemImage: answer?.systemImage ?? tr("circle"))
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            } else {
                FixtureAnswerControl(eventId: fixture.eventId, answer: $answer, title: Practice.question(subtype: fixture.eventSubtype, title: fixture.title))
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

/// A match against somebody, or nets or training at the club — the same
/// sheet, so a secretary finds both where they already schedule things.
struct ScheduleMatchSheet: View {
    let clubs: [Club]
    let onScheduled: () -> Void
    /// Nets or training made: the first session, and how many.
    let onSessions: (Event, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ScheduleKind
    @State private var clubId: UUID?
    @State private var venues: [Venue] = []
    @State private var venueId: UUID?
    @State private var teams: [Team] = []
    @State private var teamId: UUID?
    @State private var opponent: ClubIdentity?
    @State private var oppositionName = ""
    @State private var picking = false
    @State private var start = Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: .now.addingTimeInterval(7 * 86400)) ?? .now
    @State private var name: String
    @State private var minutes: Int
    @State private var note = ""
    @State private var repeating = false
    @State private var weeks = ScheduleRequests.defaultWeeks
    /// The sessions being sent, and those already made. After a failure part
    /// way through a series the form is fixed and Schedule carries on from the
    /// week that failed — a week that exists is never sent twice.
    @State private var plan: [CreateEventBody] = []
    @State private var made: [Event] = []
    @State private var busy = false
    @State private var error: String?

    init(
        clubs: [Club],
        startAs: ScheduleKind = .match,
        onScheduled: @escaping () -> Void,
        onSessions: @escaping (Event, Int) -> Void = { _, _ in }
    ) {
        self.clubs = clubs
        self.onScheduled = onScheduled
        self.onSessions = onSessions
        _kind = State(initialValue: startAs)
        _name = State(initialValue: startAs.isPractice ? startAs.label : "")
        _minutes = State(initialValue: startAs.defaultMinutes)
    }

    private var club: Club? { clubs.first { $0.id == clubId } }
    private var theirName: String { opponent?.displayName ?? oppositionName.trimmingCharacters(in: .whitespaces) }

    /// Which piece is missing, in the order the form asks for them — a dead
    /// button with no explanation reads as a broken app.
    private var missing: String? {
        var parts: [String] = []
        if club == nil { parts.append(tr("which of your clubs is playing")) }
        if !kind.isPractice, theirName.isEmpty { parts.append(tr("who you are playing")) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(t("np.what_kind")) {
                    Picker(t("np.what_kind"), selection: $kind) {
                        ForEach(ScheduleKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .disabled(!made.isEmpty)

                if kind.isPractice {
                    practiceSections.disabled(!made.isEmpty)
                } else {
                    matchSections
                }

                if let error {
                    // A series that stopped part way says how much of it exists.
                    if kind.isPractice, repeating {
                        Text(t("np.scheduled_sessions", count: made.count, vars: ["n": made.count]))
                    }
                    Text(error).foregroundStyle(FishersTheme.unavailable)
                }

                Section {
                    Button {
                        Task { await schedule() }
                    } label: {
                        Group {
                            if busy {
                                ProgressView()
                            } else {
                                Text(kind.isPractice ? t("np.schedule") : t("ld.schedule_and_ask_who_is_available"))
                                    .font(FishersTheme.headline)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || missing != nil)
                    .listRowBackground(Color.clear)
                } footer: {
                    if let missing {
                        Text(t("sc.still_needed", vars: ["what": missing]))
                    } else if kind.isPractice {
                        Text(t("np.everyone_asked"))
                    } else {
                        Text(t("ev.everyone_in_is_asked", vars: ["who": opponent != nil ? t("ev.both_clubs") : t("ev.your_club")]))
                    }
                }
            }
            .navigationTitle(kind.isPractice ? t("np.schedule_nets_or_practice") : t("ev.schedule_a_match"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) {
                        // Part of a series was made before a week failed: the
                        // list behind should show what exists.
                        if !made.isEmpty { onScheduled() }
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled(busy || !made.isEmpty)
            .sheet(isPresented: $picking) {
                OppositionPickerView { name, identity in
                    oppositionName = name
                    opponent = identity
                    picking = false
                }
            }
            .task(id: clubId) {
                // The grounds and teams belong to whichever club is hosting.
                venueId = nil
                teamId = nil
                guard let clubId else { return }
                venues = (try? await FishersAPI.venues(clubId: clubId)) ?? []
                teams = (try? await FishersAPI.teams(clubId: clubId)) ?? []
            }
            .onChange(of: kind) { before, now in
                guard now.isPractice else { return }
                // Follow the kind until somebody has typed a name or picked a
                // length of their own.
                let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if typed.isEmpty || (before.isPractice && name == before.label) { name = now.label }
                if !before.isPractice || minutes == before.defaultMinutes { minutes = now.defaultMinutes }
            }
            .onAppear { if clubId == nil { clubId = clubs.first?.id } }
        }
    }

    @ViewBuilder
    private var matchSections: some View {
        Section(tr("Your side")) {
            Picker(tr("Club"), selection: $clubId) {
                ForEach(clubs) { Text($0.name).tag(Optional($0.id)) }
            }
        }

        groundSection

        Section {
            Button {
                picking = true
            } label: {
                LabeledContent(tr("Opposition"), value: theirName.isEmpty ? tr("Choose…") : theirName)
            }
        } header: {
            Text(t("ev.the_opposition"))
        } footer: {
            Text(opponent != nil
                 ? "\(opponent!.clubName) are on \(Brand.name) — their players get asked too."
                 : "A club on \(Brand.name) gets asked as well. Otherwise only your side is.")
        }

        Section(tr("When")) {
            DatePicker(tr("Date and time"), selection: $start, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
        }
    }

    /// Nets and training: nobody to play, so no opposition.
    @ViewBuilder
    private var practiceSections: some View {
        Section {
            Picker(t("ev.club"), selection: $clubId) {
                ForEach(clubs) { Text($0.name).tag(Optional($0.id)) }
            }
            if !teams.isEmpty {
                Picker(t("cl.team"), selection: $teamId) {
                    Text(t("rest.the_club")).tag(UUID?.none)
                    ForEach(teams) { Text($0.name).tag(Optional($0.id)) }
                }
            }
        }

        Section(t("np.name")) {
            TextField(t("np.name"), text: $name, prompt: Text(t("np.name_hint")))
        }

        Section(t("ev.when")) {
            DatePicker(t("ev.date_and_time"), selection: $start, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
            Picker(t("rest.how_long"), selection: $minutes) {
                ForEach(ScheduleRequests.minuteChoices, id: \.self) { n in
                    Text(t("np.n_minutes", vars: ["n": n])).tag(n)
                }
            }
        }

        groundSection

        Section(t("np.note")) {
            TextField(t("np.note"), text: $note, prompt: Text(t("np.note_hint")), axis: .vertical)
                .lineLimit(2...5)
        }

        Section {
            Toggle(t("np.repeat_weekly"), isOn: $repeating)
            if repeating {
                Stepper(value: $weeks, in: ScheduleRequests.weekChoices) {
                    Text(t("np.for_weeks", count: weeks, vars: ["n": weeks]))
                }
            }
        }
    }

    private var groundSection: some View {
        Section {
            if venues.isEmpty {
                Text(t("ev.no_grounds_saved_plain"))
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker(tr("Ground"), selection: $venueId) {
                    Text(t("ev.not_decided_yet")).tag(UUID?.none)
                    ForEach(venues) { Text($0.name).tag(Optional($0.id)) }
                }
            }
        } header: {
            Text(t("ev.where"))
        }
    }

    private func schedule() async {
        guard let club else { return }
        if kind.isPractice {
            await schedulePractice(club)
            return
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            _ = try await FishersAPI.createEvent(ScheduleRequests.match(
                club: club, opponentClubId: opponent?.clubId, theirName: theirName, venueId: venueId, start: start
            ))
            onScheduled()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? tr("Could not schedule that")
        }
    }

    /// One session, or one a week, sent one after another. A failure stops
    /// the run and says how many were made; Schedule again carries on from the
    /// week that failed.
    private func schedulePractice(_ club: Club) async {
        busy = true
        error = nil
        defer { busy = false }
        if made.isEmpty {
            let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
            plan = ScheduleRequests.sessions(
                kind: kind,
                club: club,
                teamId: teamId,
                title: title.isEmpty ? kind.label : title,
                venueId: venueId,
                start: start,
                minutes: minutes,
                note: note,
                weeks: repeating ? weeks : nil
            )
        }
        let outcome = await ScheduleRequests.create(plan, from: made.count, send: FishersAPI.createEvent)
        made += outcome.made
        if let failure = outcome.failure {
            error = (failure as? APIError)?.friendlyMessage ?? t("ld.could_not_schedule_that")
            return
        }
        guard let first = made.first else { return }
        onSessions(first, made.count)
        dismiss()
    }
}

