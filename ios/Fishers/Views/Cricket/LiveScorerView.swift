import SwiftUI
import UIKit

/// How often the scorer is asked where the ball went.
enum WagonWheelMode: String, CaseIterable, Identifiable {
    case off, boundaries, everyScoringShot

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .boundaries: return "Boundaries"
        case .everyScoringShot: return "Every shot"
        }
    }

    func asks(forRuns runs: Int) -> Bool {
        switch self {
        case .off: return false
        case .boundaries: return runs >= 4
        case .everyScoringShot: return runs > 0
        }
    }
}

/// One-tap LIVE scorer — thumb-zone runs grid, extras, wickets, undo.
struct LiveScorerView: View {
    @ObservedObject var store: CricketMatchStore
    var onDone: () -> Void

    @AppStorage("cricket_wheel_mode") private var wheelModeRaw = WagonWheelMode.everyScoringShot.rawValue

    @State private var showExtras = false
    @State private var showWicket = false
    @State private var showBowler = false
    @State private var showScorecard = false
    @State private var showSecondInnings = false
    @State private var showRain = false
    @State private var confirmEndInnings = false
    @State private var pendingShot: PendingShot?
    @State private var isSharing = false
    @State private var shareNotice: String?
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// A ball waiting on the wagon wheel before it is written to the log.
    private struct PendingShot: Identifiable {
        let id = UUID()
        let runs: Int
        let batterName: String
        let batsLeft: Bool
        let commit: (ShotRecord?) -> Void
    }

    private var innings: InningsState? { store.state.currentInnings }
    private var isLive: Bool { store.state.status == .live && innings?.complete == false }
    private var wheelMode: WagonWheelMode {
        WagonWheelMode(rawValue: wheelModeRaw) ?? .everyScoringShot
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 16) {
                    ScrollView { VStack(spacing: 14) { scoreHeader; commentaryPanel } }
                        .frame(maxWidth: .infinity)
                    controls.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 12) {
                    scoreHeader
                    commentaryPanel
                    Spacer(minLength: 0)
                    controls
                }
            }
        }
        .padding()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let shareNotice {
                    Text(shareNotice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                syncBar
            }
        }
        .sheet(isPresented: $showExtras) { ExtrasSheet(store: store, wheelMode: wheelMode) }
        .sheet(isPresented: $showWicket) { WicketSheet(store: store) }
        .sheet(isPresented: $showBowler) { BowlerSheet(store: store) }
        .sheet(isPresented: $showSecondInnings) { SecondInningsSheet(store: store) }
        .sheet(isPresented: $showRain) { RevisedOversSheet(store: store) }
        .sheet(item: $pendingShot) { pending in
            WagonWheelPicker(
                batterName: pending.batterName,
                batsLeft: pending.batsLeft,
                runs: pending.runs,
                onSave: { pending.commit($0) },
                onSkip: { pending.commit(nil) }
            )
        }
        .sheet(isPresented: $showScorecard) {
            NavigationStack {
                CricketScorecardView(state: store.state, dls: nil)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showScorecard = false }
                        }
                    }
            }
        }
        .confirmationDialog(
            "End the innings here?",
            isPresented: $confirmEndInnings,
            titleVisibility: .visible
        ) {
            Button("End innings", role: .destructive) { _ = store.append(.inningsCompleted) }
            Button("Keep scoring", role: .cancel) {}
        } message: {
            Text("Declarations and rain both end an innings early. You can undo it.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await shareLiveLink() }
                } label: {
                    if isSharing {
                        ProgressView()
                    } else {
                        Label("Share live", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isSharing || store.matchId == nil)
                .accessibilityLabel("Share live scoreboard to chat")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Wagon wheel", selection: $wheelModeRaw) {
                        ForEach(WagonWheelMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    Divider()
                    Button {
                        showRain = true
                    } label: {
                        Label("Overs reduced (rain)", systemImage: "cloud.rain.fill")
                    }
                    Button {
                        showScorecard = true
                    } label: {
                        Label("Scorecard", systemImage: "list.bullet.rectangle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onChange(of: store.state.status) { _, status in
            if status == .inningsBreak || status.isFinished {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    // MARK: Header

    private var scoreHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.state.scoreLine())
                    .font(FishersTheme.display)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityLabel("Score \(store.state.scoreLine())")
                Spacer()
                Button { showScorecard = true } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .accessibilityLabel("Full scorecard")
            }

            if let inn = innings {
                HStack(alignment: .top, spacing: 16) {
                    batterLine(id: inn.strikerId, onStrike: true)
                    batterLine(id: inn.nonStrikerId, onStrike: false)
                }
                if let bowler = inn.bowlerId {
                    let figures = inn.bowlers.first { $0.playerId == bowler }?.figures ?? "0.0-0-0-0"
                    Text("\(store.name(for: bowler))  \(figures)")
                        .font(FishersTheme.subhead)
                        .foregroundStyle(.secondary)
                }
                overStrip(inn)
                statsRow(inn)
                dlsRow
            }

            if store.state.status == .inningsBreak {
                Button("Start second innings") { showSecondInnings = true }
                    .buttonStyle(.borderedProminent)
                    .tint(FishersTheme.accent)
            }
            if store.state.status.isFinished {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.state.margin ?? "Match complete")
                        .font(FishersTheme.headline)
                        .foregroundStyle(FishersTheme.pitch)
                    HStack {
                        Button("Scorecard") { showScorecard = true }
                            .buttonStyle(.bordered)
                        Button("Done", action: onDone)
                            .buttonStyle(.borderedProminent)
                            .tint(FishersTheme.accent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func batterLine(id: UUID?, onStrike: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(onStrike ? "STRIKER" : "NON-STRIKER")
                .font(FishersTheme.overline)
                .foregroundStyle(.secondary)
            if let id, let inn = innings,
               let b = inn.batters.first(where: { $0.playerId == id }) {
                Text("\(store.name(for: id))\(onStrike ? "*" : "")")
                    .font(onStrike ? FishersTheme.headline : FishersTheme.subhead)
                Text("\(b.runs) (\(b.balls))")
                    .font(FishersTheme.subhead.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
            }
        }
    }

    private func overStrip(_ inn: InningsState) -> some View {
        HStack(spacing: 6) {
            Text("This over")
                .font(FishersTheme.overline)
                .foregroundStyle(.secondary)
            ForEach(inn.currentOverBalls) { ball in
                Text(ball.label)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .frame(minWidth: 26, minHeight: 26)
                    .background(ballColour(ball).opacity(0.18), in: Circle())
                    .foregroundStyle(ballColour(ball))
            }
            Spacer(minLength: 0)
        }
    }

    private func ballColour(_ ball: DeliveryRecord) -> Color {
        if ball.isWicket { return FishersTheme.seam }
        if !ball.isLegal { return FishersTheme.maybe }
        if ball.runs >= 4 { return FishersTheme.pitch }
        return FishersTheme.ink
    }

    private func statsRow(_ inn: InningsState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                Label(String(format: "CRR %.2f", inn.runRate), systemImage: "speedometer")
                if let rrr = store.state.requiredRunRate, inn.index >= 1 {
                    Label(String(format: "RRR %.2f", rrr), systemImage: "target")
                }
                Text("P'ship \(inn.partnershipRuns) (\(inn.partnershipBalls))")
                if inn.oversAvailable > 0 {
                    Text("\(inn.oversAvailable) ov")
                        .foregroundStyle(.secondary)
                }
            }
            .font(FishersTheme.caption)
            .foregroundStyle(.secondary)
            if let chase = store.state.chaseLine {
                Text(chase)
                    .font(FishersTheme.subhead.weight(.semibold))
                    .foregroundStyle(FishersTheme.accent)
            }
        }
    }

    /// DLS from the first ball of the chase, so an abandoned match always has a
    /// result. Computed on the device; the API agrees ball for ball.
    @ViewBuilder
    private var dlsRow: some View {
        if let inn = innings, inn.index >= 1, let par = store.dlsPar {
            HStack(spacing: 8) {
                Image(systemName: "cloud.rain")
                    .font(.caption2)
                    .foregroundStyle(par.aheadBy >= 0 ? FishersTheme.available : FishersTheme.maybe)
                Text(par.summary)
                    .font(FishersTheme.caption)
                    .foregroundStyle(par.aheadBy >= 0 ? FishersTheme.available : FishersTheme.maybe)
                Spacer(minLength: 0)
                Text("Target \(par.target)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Commentary

    @ViewBuilder
    private var commentaryPanel: some View {
        if let inn = innings, !inn.deliveries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(CricketCommentary.feed(for: inn, in: store.state, limit: 3)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.marker)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)
                        Text(entry.text)
                            .font(.caption)
                            .foregroundStyle(entry.isWicket ? FishersTheme.seam : .primary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                spacing: 10
            ) {
                ForEach(0..<7, id: \.self) { runs in
                    runButton(runs)
                }
                Button { showExtras = true } label: {
                    Text("Extras")
                        .font(FishersTheme.headline)
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Extras")
            }
            HStack(spacing: 10) {
                Button { showWicket = true } label: {
                    Text("Wicket")
                        .font(FishersTheme.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(FishersTheme.seam)
                .accessibilityLabel("Wicket")

                Button {
                    if store.append(.undoLast) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
                .disabled(store.state.lastSeq == 0)
                .accessibilityLabel("Undo last ball")
            }
            HStack {
                Button("Change bowler") { showBowler = true }
                Spacer()
                Button("End innings") { confirmEndInnings = true }
                    .disabled(innings?.complete != false)
            }
            .font(FishersTheme.subhead)
        }
        .disabled(!isLive)
        .opacity(isLive ? 1 : 0.5)
    }

    private func runButton(_ runs: Int) -> some View {
        Button {
            score(runs)
        } label: {
            Text("\(runs)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(runs >= 4 ? FishersTheme.pitch : FishersTheme.accent)
        .accessibilityLabel("\(runs) run\(runs == 1 ? "" : "s")")
    }

    /// The wheel is asked for *before* the ball is written, so the shot rides
    /// on the same event and an undo takes both away together.
    private func score(_ runs: Int) {
        guard let striker = innings?.strikerId else { return }
        let commit: (ShotRecord?) -> Void = { shot in
            guard store.append(.deliveryRecorded(
                runs: UInt8(runs),
                isLegal: true,
                isBoundaryFour: runs == 4,
                isBoundarySix: runs == 6,
                shot: shot
            )) else { return }
            if runs >= 4 {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            promptForBowlerIfOverEnded()
        }

        if wheelMode.asks(forRuns: runs) {
            pendingShot = PendingShot(
                runs: runs,
                batterName: store.name(for: striker),
                batsLeft: store.state.batsLeft(striker),
                commit: commit
            )
        } else {
            commit(nil)
        }
    }

    /// Mint a secure live link and post it into the fixture/club chat thread.
    private func shareLiveLink() async {
        guard let matchId = store.matchId else {
            shareNotice = "Match is not synced yet — keep scoring, then try again."
            return
        }
        isSharing = true
        defer { isSharing = false }
        do {
            let share = try await FishersAPI.shareScoreboard(matchId: matchId, postToChat: true)
            UIPasteboard.general.string = share.url
            if share.conversationId != nil {
                shareNotice = "Live link posted to chat and copied."
            } else {
                shareNotice = "Live link copied. Open chat if it was not posted automatically."
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            shareNotice = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func promptForBowlerIfOverEnded() {
        guard let inn = store.state.currentInnings, !inn.complete else { return }
        if inn.ballsInCurrentOver == 0 && inn.legalBalls > 0 {
            showBowler = true
        }
    }

    // MARK: Sync chip

    private var syncBar: some View {
        HStack(spacing: 8) {
            Image(systemName: syncIcon)
                .font(.caption2)
                .foregroundStyle(syncColour)
            Text(syncLabel)
                .font(FishersTheme.footnote)
                .foregroundStyle(.secondary)
            if let err = store.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(FishersTheme.unavailable)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var syncLabel: String {
        switch store.syncStatus {
        case .saved: return "Saved"
        case .syncing: return "Syncing…"
        case .offline: return "Offline — saved on this phone"
        }
    }

    private var syncIcon: String {
        switch store.syncStatus {
        case .saved: return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .offline: return "wifi.slash"
        }
    }

    private var syncColour: Color {
        switch store.syncStatus {
        case .saved: return FishersTheme.available
        case .syncing: return FishersTheme.maybe
        case .offline: return FishersTheme.unavailable
        }
    }
}

// MARK: - Extras

/// A wide they ran a single off is two runs; a no ball hit for four is five and
/// four of them belong to the batter. The sheet makes that difference explicit
/// rather than asking the scorer to do the arithmetic.
private struct ExtrasSheet: View {
    @ObservedObject var store: CricketMatchStore
    let wheelMode: WagonWheelMode
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ExtraKind = .wide
    @State private var runs = 0
    @State private var boundary = false
    @State private var offTheBat = true
    @State private var showWheel = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(ExtraKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(kind.footnote)
                }

                if kind != .penalty {
                    Section {
                        Stepper(runsLabel, value: $runs, in: runRange)
                        Toggle("Went to the boundary", isOn: $boundary)
                            .disabled(runs < 4)
                        if kind == .noBall {
                            Picker("Those runs came", selection: $offTheBat) {
                                Text("Off the bat").tag(true)
                                Text("As byes").tag(false)
                            }
                            .pickerStyle(.segmented)
                        }
                    } header: {
                        Text(kind == .bye || kind == .legBye ? "Runs run" : "Runs on top")
                    } footer: {
                        Text(explanation)
                    }
                }

                Section {
                    HStack {
                        Text("Total to the side")
                        Spacer()
                        Text("\(totalRuns)")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(FishersTheme.accent)
                    }
                }
            }
            .navigationTitle("Extras")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }.bold()
                }
            }
            .onChange(of: kind) { _, new in
                runs = new == .penalty ? 5 : 0
                boundary = false
                offTheBat = true
            }
            .onChange(of: runs) { _, new in
                if new < 4 { boundary = false }
            }
            .sheet(isPresented: $showWheel) {
                if let striker = store.state.currentInnings?.strikerId {
                    WagonWheelPicker(
                        batterName: store.name(for: striker),
                        batsLeft: store.state.batsLeft(striker),
                        runs: Int(runs),
                        onSave: { commit(shot: $0) },
                        onSkip: { commit(shot: nil) }
                    )
                }
            }
        }
        .presentationDetents([.large])
    }

    private var runRange: ClosedRange<Int> {
        switch kind {
        case .wide, .noBall: return 0...6
        case .bye, .legBye: return 1...6
        case .penalty: return 5...5
        }
    }

    private var runsLabel: String {
        switch kind {
        case .wide, .noBall: return runs == 0 ? "None" : "\(runs)"
        default: return "\(runs)"
        }
    }

    private var totalRuns: Int {
        (kind == .wide || kind == .noBall ? 1 : 0) + runs
    }

    private var explanation: String {
        switch kind {
        case .wide:
            return runs == 0
                ? "One run for the wide."
                : "One for the wide plus \(runs) run — \(totalRuns) to the side, all wides."
        case .noBall where offTheBat:
            return runs == 0
                ? "One run for the no ball."
                : "One for the no ball plus \(runs) off the bat — the batter gets \(runs)."
        case .noBall:
            return "One for the no ball plus \(runs) bye\(runs == 1 ? "" : "s"). Only the no ball is charged to the bowler."
        case .bye, .legBye:
            return "A legal ball. Nothing against the bowler, nothing to the batter."
        case .penalty:
            return "Five penalty runs. No ball is bowled."
        }
    }

    private func add() {
        // Only runs off the bat are a shot worth plotting.
        let plottable = kind == .noBall && offTheBat && runs > 0
        if plottable && wheelMode.asks(forRuns: runs) {
            showWheel = true
        } else {
            commit(shot: nil)
        }
    }

    private func commit(shot: ShotRecord?) {
        _ = store.append(.extrasRecorded(
            kind: kind,
            runs: UInt8(runs),
            boundary: boundary,
            offTheBat: offTheBat,
            shot: shot
        ))
        dismiss()
    }
}

// MARK: - Rain

/// Overs lost to weather. DLS reads this, so the par score moves the moment the
/// umpires do.
private struct RevisedOversSheet: View {
    @ObservedObject var store: CricketMatchStore
    @Environment(\.dismiss) private var dismiss
    @State private var overs: Int = 20
    @State private var inningsIndex: Int = 0
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                if store.state.innings.count > 1 {
                    Section("Which innings") {
                        Picker("Innings", selection: $inningsIndex) {
                            ForEach(Array(store.state.innings.enumerated()), id: \.offset) { index, inn in
                                Text(store.state.name(for: inn.batting)).tag(index)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section {
                    Stepper("Overs: \(overs)", value: $overs, in: bowledSoFar...50)
                } header: {
                    Text("That innings now has")
                } footer: {
                    Text("\(bowledSoFar) over\(bowledSoFar == 1 ? "" : "s") already bowled. The DLS par score updates immediately — including when the first innings was the one cut short.")
                }
                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle("Overs reduced")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }.bold()
                }
            }
            .onAppear {
                inningsIndex = max(0, store.state.innings.count - 1)
                overs = Int(selectedInnings?.oversAvailable ?? store.state.oversLimit)
            }
            .onChange(of: inningsIndex) { _, _ in
                overs = Int(selectedInnings?.oversAvailable ?? store.state.oversLimit)
            }
        }
        .presentationDetents([.medium])
    }

    private var selectedInnings: InningsState? {
        store.state.innings.indices.contains(inningsIndex)
            ? store.state.innings[inningsIndex]
            : store.state.currentInnings
    }

    private var bowledSoFar: Int {
        guard let inn = selectedInnings else { return 1 }
        return max(1, (Int(inn.legalBalls) + 5) / 6)
    }

    private func apply() {
        guard let inn = selectedInnings else { return }
        if store.append(.oversRevised(inningsIndex: inn.index, overs: UInt8(overs))) {
            dismiss()
        } else {
            message = store.lastError
        }
    }
}

// MARK: - Wicket

/// Who is out, how, who did it, and who is coming in. A run out can take the
/// batter at either end, and can have runs completed first.
private struct WicketSheet: View {
    @ObservedObject var store: CricketMatchStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: DismissalKind = .bowled
    @State private var outIsStriker = true
    @State private var fielderId: UUID?
    @State private var newBatterId: UUID?
    @State private var completedRuns = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("How") {
                    Picker("Dismissal", selection: $kind) {
                        ForEach(DismissalKind.allCases) { Text($0.label).tag($0) }
                    }
                }

                if kind.canDismissNonStriker {
                    Section("Who is out") {
                        Picker("Batter", selection: $outIsStriker) {
                            Text(strikerName).tag(true)
                            Text(nonStrikerName).tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if kind.allowsCompletedRuns {
                    Section {
                        Stepper("Runs completed: \(completedRuns)", value: $completedRuns, in: 0...4)
                    } footer: {
                        Text("Runs finished before the throw came in. The batters cross on an odd number.")
                    }
                }

                if kind.needsFielder {
                    Section(fielderLabel) {
                        Picker("Fielder", selection: $fielderId) {
                            Text("—").tag(UUID?.none)
                            ForEach(fielders) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    }
                }

                Section("New batter") {
                    if nextIn.isEmpty {
                        Text("That is all out — no one left to come in.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("In next", selection: $newBatterId) {
                            Text("—").tag(UUID?.none)
                            ForEach(nextIn) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    }
                }
            }
            .navigationTitle("Wicket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Out") { record() }.bold().disabled(!canRecord)
                }
            }
            .onAppear { newBatterId = nextIn.first?.id }
            .onChange(of: kind) { _, new in
                if !new.canDismissNonStriker { outIsStriker = true }
                if !new.allowsCompletedRuns { completedRuns = 0 }
                if !new.needsFielder { fielderId = nil }
            }
        }
        .presentationDetents([.large])
    }

    private var innings: InningsState? { store.state.currentInnings }

    private var strikerName: String {
        innings?.strikerId.map { store.name(for: $0) } ?? "Striker"
    }

    private var nonStrikerName: String {
        innings?.nonStrikerId.map { store.name(for: $0) } ?? "Non-striker"
    }

    private var outBatterId: UUID? {
        outIsStriker ? innings?.strikerId : innings?.nonStrikerId
    }

    private var fielderLabel: String {
        switch kind {
        case .caught: return "Caught by"
        case .stumped: return "Stumped by"
        default: return "Fielder"
        }
    }

    private var fielders: [MatchPlayer] {
        guard let inn = innings else { return [] }
        return store.state.players(for: inn.bowling)
    }

    private var nextIn: [MatchPlayer] {
        guard let inn = innings else { return [] }
        let atCrease = [inn.strikerId, inn.nonStrikerId].compactMap { $0 }
        let dismissed = Set(inn.batters.filter(\.out).map(\.playerId))
        return store.state.players(for: inn.batting).filter {
            !dismissed.contains($0.id) && !atCrease.contains($0.id)
        }
    }

    private var isLastWicket: Bool {
        guard let inn = innings else { return false }
        return inn.wickets + 1 >= inn.wicketsAllowed
    }

    private var canRecord: Bool {
        guard outBatterId != nil else { return false }
        return isLastWicket || newBatterId != nil
    }

    private func record() {
        guard let batterId = outBatterId else { return }
        let ok = store.append(.wicketRecorded(
            batterId: batterId,
            kind: kind,
            fielderId: fielderId,
            newBatterId: newBatterId,
            runs: UInt8(completedRuns)
        ))
        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            dismiss()
        }
    }

}

// MARK: - Bowler

private struct BowlerSheet: View {
    @ObservedObject var store: CricketMatchStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(available) { player in
                        row(player, reason: nil)
                    }
                } header: {
                    Text("Can bowl")
                } footer: {
                    if store.state.conditions.oversPerBowler > 0 {
                        Text("\(store.state.conditions.oversPerBowler) overs each. Nobody bowls two overs in a row.")
                    } else {
                        Text("No allocation agreed. Nobody bowls two overs in a row.")
                    }
                }

                if !unavailable.isEmpty {
                    Section("Cannot bowl this over") {
                        ForEach(unavailable, id: \.0.id) { player, reason in
                            row(player, reason: reason)
                        }
                    }
                }
            }
            .navigationTitle("Bowler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ player: MatchPlayer, reason: String?) -> some View {
        Button {
            guard reason == nil else { return }
            _ = store.append(.bowlerChanged(bowlerId: player.id))
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .foregroundStyle(reason == nil ? .primary : .secondary)
                    if let reason {
                        Text(reason).font(.caption2).foregroundStyle(FishersTheme.unavailable)
                    } else if let left = store.state.oversLeftForBowler(player.id) {
                        Text("\(left) over\(left == 1 ? "" : "s") left")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let figures = figures(for: player.id) {
                    Text(figures)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if store.state.currentInnings?.bowlerId == player.id {
                    Image(systemName: "checkmark").foregroundStyle(FishersTheme.accent)
                }
            }
        }
        .disabled(reason != nil)
        .accessibilityLabel(
            reason.map { "\(player.name), \($0)" } ?? player.name
        )
    }

    private var fielding: [MatchPlayer] {
        guard let inn = store.state.currentInnings else { return [] }
        return store.state.players(for: inn.bowling)
    }

    private var available: [MatchPlayer] {
        fielding.filter { store.state.bowlerUnavailableReason($0.id) == nil }
    }

    private var unavailable: [(MatchPlayer, String)] {
        fielding.compactMap { player in
            store.state.bowlerUnavailableReason(player.id).map { (player, $0) }
        }
    }

    private func figures(for id: UUID) -> String? {
        store.state.currentInnings?.bowlers.first { $0.playerId == id }?.figures
    }
}

// MARK: - Second innings

private struct SecondInningsSheet: View {
    @ObservedObject var store: CricketMatchStore
    @Environment(\.dismiss) private var dismiss

    @State private var strikerId: UUID?
    @State private var nonStrikerId: UUID?
    @State private var bowlerId: UUID?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                if let target = store.state.target {
                    Section {
                        Text("\(store.state.name(for: batting)) need \(target) to win.")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Section("Opening pair") {
                    picker("Striker", $strikerId, batters)
                    picker("Non-striker", $nonStrikerId, batters)
                }
                Section("Opening bowler") {
                    picker("Bowler", $bowlerId, bowlersAvailable)
                }
                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle("Second innings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { start() }.bold()
                }
            }
            .onAppear {
                strikerId = batters.first?.id
                nonStrikerId = batters.dropFirst().first?.id
                bowlerId = bowlersAvailable.first?.id
            }
        }
    }

    private var batting: MatchSide {
        store.state.innings.first?.batting.opposite ?? .away
    }

    private var batters: [MatchPlayer] { store.state.players(for: batting) }
    private var bowlersAvailable: [MatchPlayer] { store.state.players(for: batting.opposite) }

    private func picker(
        _ title: String,
        _ selection: Binding<UUID?>,
        _ players: [MatchPlayer]
    ) -> some View {
        Picker(title, selection: selection) {
            Text("—").tag(UUID?.none)
            ForEach(players) { Text($0.name).tag(UUID?.some($0.id)) }
        }
    }

    private func start() {
        guard let s = strikerId, let ns = nonStrikerId, let b = bowlerId, s != ns else {
            message = "Pick two different batters and a bowler."
            return
        }
        if store.append(.inningsStarted(
            inningsIndex: 1, batting: batting,
            strikerId: s, nonStrikerId: ns, bowlerId: b
        )) {
            dismiss()
        } else {
            message = store.lastError
        }
    }
}
