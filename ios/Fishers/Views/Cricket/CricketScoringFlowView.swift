import SwiftUI
import SwiftData

/// Setup wizard → LIVE scorer for a cricket fixture.
///
/// Everything here works with no network: the match id is minted on the device
/// and the API is told about it whenever the signal comes back.
struct CricketScoringFlowView: View {
    let event: Event
    let attendees: [AttendeeSummary]
    var canScore: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @StateObject private var store: CricketMatchStore
    @State private var step: Step = .setup
    @State private var overs = 20
    @State private var conditions = MatchConditions.standard(overs: 20)
    @State private var homeName = "Home"
    @State private var awayName = "Away"
    @State private var tossWinner: MatchSide = .home
    @State private var tossDecision: TossDecision = .bat
    @State private var homeSheet: [MatchPlayer] = []
    @State private var awaySheet: [MatchPlayer] = []
    @State private var homeCaptain: UUID?
    @State private var awayCaptain: UUID?
    @State private var homeKeeper: UUID?
    @State private var awayKeeper: UUID?
    @State private var umpires: [MatchPlayer] = []
    @State private var scorers: [MatchPlayer] = []
    @State private var strikerId: UUID?
    @State private var nonStrikerId: UUID?
    @State private var bowlerId: UUID?
    @State private var message: String?
    @State private var booting = false
    @State private var isPickingOpposition = false
    @State private var opponent: ClubIdentity?
    @State private var agreeingSide: MatchSide?
    @State private var isNamingCaptain = false
    @State private var captainName = ""

    enum Step: Hashable {
        case setup, agreement, toss, sheets, openers, live
    }

    init(event: Event, attendees: [AttendeeSummary], canScore: Bool) {
        self.event = event
        self.attendees = attendees
        self.canScore = canScore
        _store = StateObject(wrappedValue: CricketMatchStore(
            eventId: event.id,
            clubId: event.clubId
        ))
    }

    var body: some View {
        Group {
            switch step {
            case .setup: setupStep
            case .agreement: agreementStep
            case .toss: tossStep
            case .sheets: sheetsStep
            case .openers: openersStep
            case .live:
                LiveScorerView(store: store, onDone: { dismiss() })
            }
        }
        .background(FishersTheme.mist.ignoresSafeArea())
        .navigationTitle(step == .live ? "LIVE" : "Start match")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.replaceContext(modelContext)
            await resumeOrPrepare()
        }
        .onDisappear {
            CricketSyncService.shared.unregister(store: store)
        }
        .sheet(isPresented: $isPickingOpposition) {
            OppositionPickerView { name, identity in
                awayName = name
                opponent = identity
            }
        }
    }

    // MARK: Step 1 — the match

    private var setupStep: some View {
        Form {
            Section {
                TextField("Batting first / home side", text: $homeName)
                Button {
                    isPickingOpposition = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(awayName.isEmpty ? "Opposition" : awayName)
                                .foregroundStyle(awayName.isEmpty ? .secondary : .primary)
                            if opponent != nil {
                                Label("On Fishers", systemImage: "checkmark.seal.fill")
                                    .font(.caption2)
                                    .foregroundStyle(FishersTheme.available)
                            }
                        }
                        Spacer()
                        Image(systemName: "qrcode.viewfinder")
                            .foregroundStyle(FishersTheme.accent)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text(event.title)
            } footer: {
                Text("Scan the other club's QR code, search for them, or type a name.")
            }

            Section {
                Picker("Overs", selection: $conditions.oversLimit) {
                    ForEach(Self.overPresets, id: \.self) { option in
                        Text("\(option)").tag(UInt8(option))
                    }
                }
                Stepper(
                    conditions.oversPerBowler == 0
                        ? "No bowler limit"
                        : "Max \(conditions.oversPerBowler) overs per bowler",
                    value: $conditions.oversPerBowler,
                    in: 0...conditions.oversLimit
                )
                Stepper(
                    conditions.powerplayOvers == 0
                        ? "No powerplay"
                        : "\(conditions.powerplayOvers) over powerplay",
                    value: $conditions.powerplayOvers,
                    in: 0...conditions.oversLimit
                )
                Stepper(
                    conditions.targetOversPerHour == 0
                        ? "Over rate not counted"
                        : "\(conditions.targetOversPerHour) overs an hour",
                    value: $conditions.targetOversPerHour,
                    in: 0...25
                )
            } header: {
                Text("Format")
            } footer: {
                Text("The usual allocation is a fifth of the innings — \(MatchConditions.standardOversPerBowler(conditions.oversLimit)) for \(conditions.oversLimit) overs — with a \(MatchConditions.standardPowerplay(conditions.oversLimit)) over powerplay. Fourteen an hour is the usual over rate. Set any of them to none for a social game.")
            }

            Section("Ground") {
                Picker("Ground", selection: $conditions.ground) {
                    ForEach(GroundType.allCases) { ground in
                        Label(ground.label, systemImage: ground.systemImage).tag(ground)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Text(conditions.ground.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(
                    "\(conditions.fieldersOutsidePowerplay) outside the circle in the powerplay",
                    value: $conditions.fieldersOutsidePowerplay,
                    in: 0...11
                )
                Stepper(
                    "\(conditions.fieldersOutsideNormal) outside after it",
                    value: $conditions.fieldersOutsideNormal,
                    in: 0...11
                )
            } header: {
                Text("Fielding restrictions")
            } footer: {
                Text("Two and five are standard. Two behind square on the leg side applies throughout and is not adjustable.")
            }

            Section("Ball") {
                Picker("Ball", selection: $conditions.ball) {
                    ForEach(BallType.allCases) { ball in
                        Text(ball.label).tag(ball)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            if !canScore {
                Section {
                    Label(
                        "You need scoring permission — a captain, club secretary or an assigned scorer.",
                        systemImage: "lock.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(FishersTheme.unavailable)
                }
            }
            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }

            Section {
                Button {
                    Task { await startMatch() }
                } label: {
                    HStack {
                        Spacer()
                        if booting {
                            ProgressView()
                        } else {
                            Text("Propose these terms").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(!canScore || booting || homeName.isEmpty || awayName.isEmpty)
            } footer: {
                Text("Both captains have to agree before the toss.")
            }
        }
        .onChange(of: conditions.oversLimit) { _, new in
            // Keep the allocation sensible when the format changes.
            conditions.oversPerBowler = MatchConditions.standardOversPerBowler(new)
            conditions.powerplayOvers = MatchConditions.standardPowerplay(new)
            overs = Int(new)
        }
    }

    private static let overPresets = [5, 6, 8, 10, 12, 15, 16, 20, 25, 30, 35, 40, 45, 50]

    // MARK: Step 1b — both captains agree

    private var agreementStep: some View {
        Form {
            Section {
                Text(store.state.conditions.summary)
                    .font(FishersTheme.headline)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("On the table")
            } footer: {
                Text("Change anything and both captains have to agree again.")
            }

            Section("Captains") {
                agreementRow(side: .home, teamName: store.state.homeName)
                agreementRow(side: .away, teamName: store.state.awayName)
            }

            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(FishersTheme.unavailable) }
            }

            Section {
                Button("Continue to the toss") { step = .toss }
                    .bold()
                    .disabled(!store.state.conditionsAgreed)
                Button("Change the terms") { step = .setup }
                    .foregroundStyle(FishersTheme.accent)
            } footer: {
                if !store.state.conditionsAgreed {
                    Text("Waiting on \(waitingNames). Tap Agree next to their name once they have said yes — this is the conversation you have at the toss.")
                }
            }
        }
        .alert("Captain's name", isPresented: $isNamingCaptain) {
            TextField("Name", text: $captainName)
            Button("Agree") { confirmAgreement() }
            Button("Cancel", role: .cancel) { agreeingSide = nil }
        } message: {
            Text("Recorded against the agreement, so there is no argument later.")
        }
    }

    private func agreementRow(side: MatchSide, teamName: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(teamName).font(.subheadline.weight(.medium))
                if let name = store.state.agreedName(side) {
                    Label(name, systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(FishersTheme.available)
                } else {
                    Text("Not agreed yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.state.agreedName(side) == nil {
                Button("Agree") {
                    agreeingSide = side
                    captainName = suggestedCaptainName(for: side)
                    isNamingCaptain = true
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var waitingNames: String {
        store.state.awaitingAgreement
            .map { store.state.name(for: $0) }
            .joined(separator: " and ")
    }

    private func suggestedCaptainName(for side: MatchSide) -> String {
        // The home captain is usually whoever is holding the phone.
        side == .home ? (session.user?.name ?? "") : ""
    }

    private func confirmAgreement() {
        guard let side = agreeingSide else { return }
        let name = captainName.trimmingCharacters(in: .whitespaces)
        agreeingSide = nil
        guard !name.isEmpty else {
            message = "Put a name against the agreement."
            return
        }
        if store.append(.conditionsAgreed(side: side, captainName: name)) {
            message = nil
        } else {
            message = store.lastError
        }
    }

    // MARK: Step 2 — toss

    private var tossStep: some View {
        Form {
            Section {
                Text(store.state.conditions.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let home = store.state.agreedHome, let away = store.state.agreedAway {
                    Label("Agreed by \(home) and \(away)", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(FishersTheme.available)
                }
            }
            Section("Who won the toss") {
                Picker("Winner", selection: $tossWinner) {
                    Text(homeName).tag(MatchSide.home)
                    Text(awayName).tag(MatchSide.away)
                }
                .pickerStyle(.segmented)
            }
            Section("And chose to") {
                Picker("Decision", selection: $tossDecision) {
                    ForEach(TossDecision.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Text("\(store.state.name(for: firstInningsBatting)) bat first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Record toss") {
                    guard store.append(.tossRecorded(winner: tossWinner, decision: tossDecision))
                    else { return }
                    step = .sheets
                }
                .bold()
            }
        }
    }

    // MARK: Step 3 — team sheets

    private var sheetsStep: some View {
        VStack(spacing: 0) {
            TabView {
                TeamSheetEditor(
                    title: homeName,
                    players: $homeSheet,
                    captain: $homeCaptain,
                    keeper: $homeKeeper,
                    clubPlayers: clubPlayers,
                    alreadyPicked: Set(awaySheet.map(\.id))
                )
                .tabItem { Label(homeName, systemImage: "house") }

                TeamSheetEditor(
                    title: awayName,
                    players: $awaySheet,
                    captain: $awayCaptain,
                    keeper: $awayKeeper,
                    clubPlayers: clubPlayers,
                    alreadyPicked: Set(homeSheet.map(\.id))
                )
                .tabItem { Label(awayName, systemImage: "figure.walk") }

                OfficialsEditor(
                    umpires: $umpires,
                    scorers: $scorers,
                    clubPlayers: clubPlayers
                )
                .tabItem { Label("Officials", systemImage: "figure.australian.football") }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            // One side at a time, because each captain names their own and the
            // engine now refuses to start until both sheets are in.
            VStack(spacing: 6) {
                Text("\(umpires.count) umpire\(umpires.count == 1 ? "" : "s") appointed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    sideConfirmButton(side: .home, name: homeName, sheet: homeSheet)
                    sideConfirmButton(side: .away, name: awayName, sheet: awaySheet)
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(FishersTheme.unavailable)
                }
            }
            .padding()
            .background(.bar)
        }
    }

    // MARK: Step 4 — openers

    private var openersStep: some View {
        let batting = firstInningsBatting
        let batXi = store.state.players(for: batting)
        let bowlXi = store.state.players(for: batting.opposite)
        return Form {
            Section {
                playerPicker("Striker", selection: $strikerId, from: batXi)
                playerPicker("Non-striker", selection: $nonStrikerId, from: batXi)
            } header: {
                Text("\(store.state.name(for: batting)) opening pair")
            }
            Section("Opening bowler") {
                playerPicker("Bowler", selection: $bowlerId, from: bowlXi)
            }
            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(FishersTheme.unavailable) }
            }
            Section {
                Button("Start innings") { startInnings(batting: batting) }
                    .bold()
            }
        }
        .onAppear {
            if strikerId == nil { strikerId = batXi.first?.id }
            if nonStrikerId == nil { nonStrikerId = batXi.dropFirst().first?.id }
            if bowlerId == nil { bowlerId = bowlXi.first?.id }
        }
    }

    private func playerPicker(
        _ title: String,
        selection: Binding<UUID?>,
        from players: [MatchPlayer]
    ) -> some View {
        Picker(title, selection: selection) {
            Text("—").tag(UUID?.none)
            ForEach(players) { player in
                Text(player.name).tag(UUID?.some(player.id))
            }
        }
    }

    // MARK: Actions

    /// An umpire who is a Fishers member is granted scoring rights on the API,
    /// so they can pick up the book without holding a club office.
    private func grantScoringToOfficials() async {
        guard let matchId = store.matchId else { return }
        let members = Set(attendees.map(\.userId))
        for umpire in umpires where members.contains(umpire.id) {
            _ = try? await FishersAPI.appointOfficial(
                matchId: matchId, userId: umpire.id, role: "umpire"
            )
        }
        for scorer in scorers where members.contains(scorer.id) {
            _ = try? await FishersAPI.appointOfficial(
                matchId: matchId, userId: scorer.id, role: "scorer"
            )
        }
    }

    private var clubPlayers: [MatchPlayer] {
        attendees.map { MatchPlayer(id: $0.userId, name: $0.name) }
    }

    private var firstInningsBatting: MatchSide {
        guard let winner = store.state.tossWinner, let decision = store.state.tossDecision else {
            return tossDecision == .bat ? tossWinner : tossWinner.opposite
        }
        return decision == .bat ? winner : winner.opposite
    }

    /// Pick up where the device left off — a match half scored, the app killed,
    /// the phone rebooted at tea.
    private func resumeOrPrepare() async {
        if let opposition = event.metadata?["opposition"], case let .string(name) = opposition {
            awayName = name
        }
        guard store.resumeLocal() != nil, store.state.lastSeq > 0 else { return }

        // There is a log: jump to wherever it got to.
        homeName = store.state.homeName
        awayName = store.state.awayName
        overs = Int(store.state.oversLimit)
        homeSheet = store.state.players(for: .home)
        awaySheet = store.state.players(for: .away)
        umpires = store.state.officials.umpires
        scorers = store.state.officials.scorers
        conditions = store.state.conditions
        switch store.state.status {
        case .live, .inningsBreak, .complete, .published:
            step = .live
        case .ready:
            step = .openers
        case .selectingXi:
            step = .sheets
        case .toss:
            step = .toss
        case .preparing:
            // Terms are on the table but not settled.
            step = store.state.conditionsProposedBy == nil ? .setup : .agreement
        case .scheduled:
            step = .setup
        }
        CricketSyncService.shared.register(store: store)
    }

    private func startMatch() async {
        guard canScore else {
            message = "You need scoring permission (captain, secretary or assigned scorer)."
            return
        }
        booting = true
        defer { booting = false }
        store.replaceContext(modelContext)
        do {
            _ = try store.openLocal(homeName: homeName, awayName: awayName, oversLimit: overs)
        } catch {
            message = error.localizedDescription
            return
        }
        if store.state.lastSeq == 0 {
            guard store.append(.matchPrepared(
                oversLimit: conditions.oversLimit, homeName: homeName, awayName: awayName
            )) else {
                message = store.lastError
                return
            }
        }
        // Whoever is scoring is proposing on behalf of the home side.
        guard store.append(.conditionsProposed(
            conditions: conditions,
            by: .home,
            byName: session.user?.name ?? homeName
        )) else {
            message = store.lastError
            return
        }
        CricketSyncService.shared.register(store: store)
        message = nil
        step = .agreement
    }

    @ViewBuilder
    private func sideConfirmButton(side: MatchSide, name: String, sheet: [MatchPlayer]) -> some View {
        let named = !store.state.xi(side).isEmpty
        Button {
            commitSheet(side: side, players: sheet)
        } label: {
            Label(
                named ? "\(name) named" : "Confirm \(name) (\(sheet.count))",
                systemImage: named ? "checkmark.circle.fill" : "person.3"
            )
            .font(FishersTheme.caption)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(named ? FishersTheme.available : FishersTheme.accent)
        .disabled(named || sheet.count < 2)
    }

    /// Name one side, then move on once both are in.
    private func commitSheet(side: MatchSide, players: [MatchPlayer]) {
        let captain = side == .home ? homeCaptain : awayCaptain
        let keeper = side == .home ? homeKeeper : awayKeeper
        guard store.append(.xiSelected(
            side: side, players: players, captainId: captain, keeperId: keeper
        )) else {
            message = store.lastError
            return
        }
        message = nil
        if !store.state.homeXi.isEmpty && !store.state.awayXi.isEmpty {
            commitOfficialsAndAdvance()
        }
    }

    private func commitOfficialsAndAdvance() {
        if !(umpires.isEmpty && scorers.isEmpty) {
            guard store.append(.officialsAppointed(
                officials: MatchOfficials(umpires: umpires, scorers: scorers)
            )) else {
                message = store.lastError
                return
            }
            // Appointed officials can score the match, so tell the API too.
            Task { await grantScoringToOfficials() }
        }
        message = nil
        step = .openers
    }

    private func startInnings(batting: MatchSide) {
        guard let s = strikerId, let ns = nonStrikerId, let b = bowlerId, s != ns else {
            message = "Pick two different batters and a bowler."
            return
        }
        if store.append(.inningsStarted(
            inningsIndex: 0, batting: batting,
            strikerId: s, nonStrikerId: ns, bowlerId: b
        )) {
            message = nil
            step = .live
        } else {
            message = store.lastError
        }
    }
}

// MARK: - Team sheet editor

/// One side's sheet: pick from the club, add a guest, order the batting line-up.
private struct TeamSheetEditor: View {
    let title: String
    @Binding var players: [MatchPlayer]
    @Binding var captain: UUID?
    @Binding var keeper: UUID?
    let clubPlayers: [MatchPlayer]
    /// Nobody plays for both sides.
    let alreadyPicked: Set<UUID>

    @State private var guestName = ""

    var body: some View {
        List {
            Section {
                if players.isEmpty {
                    Text("Nobody picked yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .trailing)
                            Text(player.name)
                            Spacer()
                            if captain == player.id {
                                Text("C").font(.caption2.bold())
                                    .foregroundStyle(FishersTheme.accent)
                            }
                            if keeper == player.id {
                                Text("WK").font(.caption2.bold())
                                    .foregroundStyle(FishersTheme.accent)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let removed = offsets.map { players[$0].id }
                        players.remove(atOffsets: offsets)
                        if let c = captain, removed.contains(c) { captain = nil }
                        if let k = keeper, removed.contains(k) { keeper = nil }
                    }
                    .onMove { players.move(fromOffsets: $0, toOffset: $1) }
                }
            } header: {
                Text("\(title) — batting order (\(players.count))")
            } footer: {
                Text("Drag to set the batting order. Swipe to remove.")
            }

            if !players.isEmpty {
                Section("Roles") {
                    Picker("Captain", selection: $captain) {
                        Text("—").tag(UUID?.none)
                        ForEach(players) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Picker("Wicketkeeper", selection: $keeper) {
                        Text("—").tag(UUID?.none)
                        ForEach(players) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
            }

            Section("Add a guest or the opposition") {
                HStack {
                    TextField("Name", text: $guestName)
                        .textInputAutocapitalization(.words)
                        .onSubmit(addGuest)
                    Button("Add", action: addGuest)
                        .disabled(guestName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if !available.isEmpty {
                Section("From the club") {
                    ForEach(available) { player in
                        Button {
                            players.append(player)
                        } label: {
                            HStack {
                                Text(player.name)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(FishersTheme.accent)
                            }
                        }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .listStyle(.insetGrouped)
    }

    private var available: [MatchPlayer] {
        let picked = Set(players.map(\.id)).union(alreadyPicked)
        return clubPlayers.filter { !picked.contains($0.id) }
    }

    private func addGuest() {
        let name = guestName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        players.append(MatchPlayer(name: name))
        guestName = ""
    }
}

// MARK: - Officials

/// Who is standing and who is keeping the book. Umpires appointed here can
/// control the scoring, which is how the square-leg umpire ends up with the app.
private struct OfficialsEditor: View {
    @Binding var umpires: [MatchPlayer]
    @Binding var scorers: [MatchPlayer]
    let clubPlayers: [MatchPlayer]

    @State private var guestName = ""
    @State private var addingUmpire = true

    var body: some View {
        List {
            Section {
                if umpires.isEmpty {
                    Text("Nobody standing yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(umpires) { official in
                        Text(official.name)
                    }
                    .onDelete { umpires.remove(atOffsets: $0) }
                }
            } header: {
                Text("Umpires (\(umpires.count))")
            } footer: {
                Text("An umpire who is a Fishers member can pick up the scoring, even without a club role.")
            }

            Section("Scorers (\(scorers.count))") {
                if scorers.isEmpty {
                    Text("Only the person who started the match.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scorers) { official in
                        Text(official.name)
                    }
                    .onDelete { scorers.remove(atOffsets: $0) }
                }
            }

            Section("Add") {
                Picker("Role", selection: $addingUmpire) {
                    Text("Umpire").tag(true)
                    Text("Scorer").tag(false)
                }
                .pickerStyle(.segmented)

                HStack {
                    TextField("Name", text: $guestName)
                        .textInputAutocapitalization(.words)
                        .onSubmit(addGuest)
                    Button("Add", action: addGuest)
                        .disabled(guestName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                ForEach(available) { player in
                    Button {
                        append(player)
                    } label: {
                        HStack {
                            Text(player.name)
                            Spacer()
                            Image(systemName: "plus.circle").foregroundStyle(FishersTheme.accent)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var available: [MatchPlayer] {
        let taken = Set(umpires.map(\.id)).union(scorers.map(\.id))
        return clubPlayers.filter { !taken.contains($0.id) }
    }

    private func append(_ player: MatchPlayer) {
        if addingUmpire {
            umpires.append(player)
        } else {
            scorers.append(player)
        }
    }

    private func addGuest() {
        let name = guestName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        append(MatchPlayer(name: name))
        guestName = ""
    }
}
