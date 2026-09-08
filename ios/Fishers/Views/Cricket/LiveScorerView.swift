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
    @State private var showHandover = false
    @State private var showAward = false
    @State private var showSuperOver = false
    @State private var showPenalty = false
    @State private var showCorrection = false
    @State private var showField = false
    @State private var confirmEndInnings = false
    @State private var pendingShot: PendingShot?
    /// Model-written lines keyed by ball. The line the app writes from the log
    /// shows instantly; this replaces it only if something better arrives.
    @State private var aiLines: [String: String] = [:]
    @State private var isSharing = false
    @State private var shareNotice: String?
    @State private var shareSheetItems: [Any]?
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

    /// An over has finished and the same bowler is still down for the next one.
    ///
    /// The engine refuses this — nobody bowls two in a row — so the controls
    /// have to refuse it too, or a scorer meets a rejection instead of a
    /// question.
    private var needsNewBowler: Bool {
        guard let inn = innings, !inn.complete else { return false }
        guard inn.ballsInCurrentOver == 0,
              inn.legalBalls > 0,
              let bowler = inn.bowlerId,
              inn.lastOverBowler == bowler else { return false }
        return store.state.xi(inn.bowling).count > 1
    }
    private var wheelMode: WagonWheelMode {
        WagonWheelMode(rawValue: wheelModeRaw) ?? .everyScoringShot
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 16) {
                    ScrollView { VStack(spacing: 14) { scoreHeader; commentaryPanel } }
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 10) {
                        bowlerGate
                        controls
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 12) {
                    scoreHeader
                    commentaryPanel
                    Spacer(minLength: 0)
                    bowlerGate
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
        .sheet(isPresented: $showHandover) { HandoverSheet(store: store) }
        .sheet(isPresented: $showAward) { AwardSheet(store: store) }
        .sheet(isPresented: $showSuperOver) { SuperOverSheet(store: store) }
        .sheet(isPresented: $showPenalty) { PenaltySheet(store: store) }
        .sheet(isPresented: $showCorrection) { BallCorrectionSheet(store: store) }
        .sheet(isPresented: $showField) { FieldSheet(store: store) }
        .sheet(isPresented: Binding(
            get: { shareSheetItems != nil },
            set: { if !$0 { shareSheetItems = nil } }
        )) {
            if let items = shareSheetItems {
                ShareSheet(items: items) {
                    shareSheetItems = nil
                }
            }
        }
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
                Menu {
                    Button {
                        Task { await shareLiveLink(postToChat: false, presentSheet: true) }
                    } label: {
                        Label("Share via WhatsApp, Mail…", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        Task { await shareLiveLink(postToChat: true, presentSheet: true) }
                    } label: {
                        Label("Share and post to club chat", systemImage: "bubble.left.and.bubble.right")
                    }
                } label: {
                    if isSharing {
                        ProgressView()
                    } else {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isSharing || store.matchId == nil)
                .accessibilityLabel("Share live scoreboard")
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
                        showCorrection = true
                    } label: {
                        Label("Correct an earlier ball", systemImage: "arrow.uturn.backward.badge.clock")
                    }
                    Button {
                        showField = true
                    } label: {
                        Label("Set the field", systemImage: "circle.dashed.inset.filled")
                    }
                    Button {
                        showPenalty = true
                    } label: {
                        Label("Penalty runs", systemImage: "exclamationmark.triangle")
                    }
                    Divider()
                    Button {
                        showHandover = true
                    } label: {
                        Label("Hand the book over", systemImage: "person.2.arrow.trianglehead.swap")
                    }
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
                if inn.superOver {
                    Label("SUPER OVER \(store.state.superOvers) — one over, two wickets", systemImage: "bolt.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FishersTheme.seam)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(FishersTheme.seam.opacity(0.15), in: Capsule())
                } else if inn.inPowerplay {
                    Label(
                        "POWERPLAY — \(inn.powerplayOversLeft) over\(inn.powerplayOversLeft == 1 ? "" : "s") left",
                        systemImage: "circle.dashed"
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FishersTheme.pitch)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(FishersTheme.pitch.opacity(0.15), in: Capsule())
                    .accessibilityLabel("Powerplay, \(inn.powerplayOversLeft) overs left")
                }
                if inn.freeHit {
                    Label("FREE HIT — only a run out can get them", systemImage: "shield.lefthalf.filled")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FishersTheme.maybe)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(FishersTheme.maybe.opacity(0.15), in: Capsule())
                        .accessibilityLabel("Free hit")
                }
                let breaches = inn.fieldingBreaches(store.state.conditions)
                if !breaches.isEmpty {
                    ForEach(breaches, id: \.self) { breach in
                        Label(breach, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FishersTheme.unavailable)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 10)
                            .background(FishersTheme.unavailable.opacity(0.14), in: Capsule())
                    }
                }
                overStrip(inn)
                statsRow(inn)
                overRateRow(inn)
                dlsRow
            }

            if store.state.status == .inningsBreak {
                Button("Start second innings") { showSecondInnings = true }
                    .buttonStyle(.borderedProminent)
                    .tint(FishersTheme.accent)
            }
            if store.state.needsASuperOver {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        store.state.superOvers == 0
                            ? "Scores level. It goes to a super over."
                            : "Still level after \(store.state.superOvers) super over\(store.state.superOvers == 1 ? "" : "s").",
                        systemImage: "bolt.fill"
                    )
                    .font(FishersTheme.headline)
                    .foregroundStyle(FishersTheme.seam)
                    Button("Start the super over") { showSuperOver = true }
                        .buttonStyle(.borderedProminent)
                        .tint(FishersTheme.seam)
                }
            }
            if store.state.status.isFinished {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.state.margin ?? "Match complete")
                        .font(FishersTheme.headline)
                        .foregroundStyle(FishersTheme.pitch)
                    if let award = store.state.playerOfTheMatch {
                        Label("Player of the match: \(store.name(for: award))", systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FishersTheme.maybe)
                    }
                    HStack {
                        Button(store.state.playerOfTheMatch == nil ? "Award" : "Change award") {
                            showAward = true
                        }
                        .buttonStyle(.bordered)
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
        if ball.runs >= 6 { return FishersTheme.six }
        if ball.runs >= 4 { return FishersTheme.four }
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

    /// How the over rate is going, when anyone is counting. The app measures it;
    /// the umpire decides what to do about it.
    @ViewBuilder
    private func overRateRow(_ inn: InningsState) -> some View {
        let target = store.state.conditions.targetOversPerHour
        if target > 0, let rate = inn.oversPerHour, let behind = inn.oversBehind(target: target) {
            let late = behind >= 1
            HStack(spacing: 8) {
                Image(systemName: late ? "clock.badge.exclamationmark" : "clock")
                    .font(.caption2)
                Text(String(format: "%.1f overs an hour", rate))
                Text("·")
                Text(
                    behind >= 0
                        ? String(format: "%.1f over%@ behind", behind, abs(behind) == 1 ? "" : "s")
                        : String(format: "%.1f ahead", -behind)
                )
                .fontWeight(late ? .semibold : .regular)
                Spacer(minLength: 0)
            }
            .font(FishersTheme.caption)
            .foregroundStyle(late ? FishersTheme.unavailable : .secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                late
                    ? "Behind the over rate by \(String(format: "%.1f", behind)) overs"
                    : "On the over rate"
            )
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
                        Text(aiLines[entry.id] ?? entry.text)
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
            .task(id: inn.deliveries.count) { await fetchCommentary(for: inn) }
        }
    }

    /// Colour for the ball just bowled.
    ///
    /// Deliberately after the fact and deliberately silent on failure: the
    /// model sits on the network and takes seconds, the ball is already in the
    /// log, and the line written from that log is correct on its own. Nothing
    /// here blocks scoring, and a failure leaves the written line alone.
    private func fetchCommentary(for inn: InningsState) async {
        guard let matchId = store.matchId, let ball = inn.deliveries.last else { return }
        let key = "\(ball.over).\(ball.ballInOver)-\(ball.label)-\(ball.runs)"
        guard aiLines[key] == nil else { return }
        guard let reply = try? await FishersAPI.commentary(
            matchId: matchId,
            over: Int(ball.over),
            ballInOver: Int(ball.ballInOver)
        ), let line = reply.line else { return }
        aiLines[key] = line
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            // Three rows, the six on its own and larger: the shot you most
            // want to hit is the easiest to reach, and hardest to mis-tap.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(0..<6, id: \.self) { runs in
                    runButton(runs)
                }
            }
            runButton(6, big: true)
            Button { showExtras = true } label: {
                Text("Extras")
                    .font(FishersTheme.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Extras")
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
        .disabled(!isLive || needsNewBowler)
        .opacity(isLive && !needsNewBowler ? 1 : 0.5)
    }

    /// Says why the buttons are dead, and offers the way out.
    @ViewBuilder
    private var bowlerGate: some View {
        if needsNewBowler, let inn = innings {
            let last = inn.lastOverBowler.map { store.name(for: $0) } ?? "That bowler"
            Button { showBowler = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Over \(Int(inn.legalBalls) / 6) done — who bowls next?")
                            .font(FishersTheme.headline)
                        Text("\(last) bowled it, and nobody bowls two in a row.")
                            .font(FishersTheme.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FishersTheme.maybe.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose the next bowler to carry on scoring")
        }
    }

    private func runButton(_ runs: Int, big: Bool = false) -> some View {
        Button {
            score(runs)
        } label: {
            Text("\(runs)")
                .font(.system(size: big ? 40 : 28, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: big ? 84 : 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(runButtonTint(runs))
        .accessibilityLabel("\(runs) run\(runs == 1 ? "" : "s")")
    }

    private func runButtonTint(_ runs: Int) -> Color {
        switch runs {
        case 6: return FishersTheme.six
        case 4: return FishersTheme.four
        default: return FishersTheme.accent
        }
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

    /// Mint a secure live link, then open the system share sheet so it can go
    /// straight to WhatsApp, Mail, Messages, and the rest.
    private func shareLiveLink(postToChat: Bool, presentSheet: Bool) async {
        guard let matchId = store.matchId else {
            shareNotice = "Match is not synced yet — keep scoring, then try again."
            return
        }
        isSharing = true
        defer { isSharing = false }
        do {
            let share = try await FishersAPI.shareScoreboard(
                matchId: matchId,
                postToChat: postToChat
            )
            UIPasteboard.general.string = share.url
            let headline = "\(store.state.homeName) vs \(store.state.awayName) — live scoreboard"
            let message = "\(headline)\n\(share.url)"
            if presentSheet {
                var items: [Any] = [message]
                if let url = URL(string: share.url) {
                    items.append(url)
                }
                shareSheetItems = items
            }
            if postToChat, share.conversationId != nil {
                shareNotice = "Link ready to share — also posted to club chat."
            } else {
                shareNotice = "Link ready — pick WhatsApp, Mail, or copy."
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            shareNotice = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func promptForBowlerIfOverEnded() {
        if needsNewBowler { showBowler = true }
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
    @State private var onExtra = false

    private var isFreeHit: Bool { store.state.currentInnings?.freeHit ?? false }

    var body: some View {
        NavigationStack {
            Form {
                if isFreeHit {
                    Section {
                        Label(
                            "Free hit — only a run out can get them.",
                            systemImage: "shield.lefthalf.filled"
                        )
                        .font(.footnote)
                        .foregroundStyle(FishersTheme.maybe)
                    }
                }
                Section("How") {
                    Picker("Dismissal", selection: $kind) {
                        ForEach(allowedKinds) { Text($0.label).tag($0) }
                    }
                }

                if kind.canFollowAnExtra {
                    Section {
                        Toggle("Off a wide or a no ball", isOn: $onExtra)
                    } footer: {
                        Text("The delivery is already in the book as an extra, so it is not counted twice.")
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

                Section {
                    if nextIn.isEmpty && resuming.isEmpty {
                        Text("That is all out — no one left to come in.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("In next", selection: $newBatterId) {
                            Text("—").tag(UUID?.none)
                            ForEach(nextIn) { Text($0.name).tag(UUID?.some($0.id)) }
                            ForEach(resuming) {
                                Text("\($0.name) (resuming)").tag(UUID?.some($0.id))
                            }
                        }
                    }
                } header: {
                    Text("New batter")
                } footer: {
                    if !resuming.isEmpty {
                        Text("Anyone who retired hurt can come back in.")
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
                if !new.canFollowAnExtra { onExtra = false }
            }
            .onAppear {
                if !allowedKinds.contains(kind) { kind = allowedKinds.first ?? .runOut }
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

    /// On a free hit the Laws allow very little.
    private var allowedKinds: [DismissalKind] {
        isFreeHit
            ? DismissalKind.allCases.filter(\.allowedOnAFreeHit)
            : DismissalKind.allCases
    }

    private var nextIn: [MatchPlayer] {
        guard let inn = innings else { return [] }
        let atCrease = [inn.strikerId, inn.nonStrikerId].compactMap { $0 }
        let unavailable = Set(
            inn.batters.filter { $0.out || $0.retiredHurt }.map(\.playerId)
        )
        return store.state.players(for: inn.batting).filter {
            !unavailable.contains($0.id) && !atCrease.contains($0.id)
        }
    }

    /// Batters who retired hurt and are fit to come back.
    private var resuming: [MatchPlayer] {
        guard let inn = innings else { return [] }
        let atCrease = [inn.strikerId, inn.nonStrikerId].compactMap { $0 }
        return inn.batters
            .filter { $0.canResume && !atCrease.contains($0.playerId) }
            .map { MatchPlayer(id: $0.playerId, name: store.name(for: $0.playerId)) }
    }

    private var isLastWicket: Bool {
        guard let inn = innings else { return false }
        return inn.wickets + 1 >= inn.wicketsAllowed
    }

    private var canRecord: Bool {
        guard outBatterId != nil else { return false }
        // Retiring hurt still needs someone to come in, unless nobody is left.
        if isLastWicket && kind.costsAWicket { return true }
        return newBatterId != nil || (nextIn.isEmpty && resuming.isEmpty)
    }

    private func record() {
        guard let batterId = outBatterId else { return }
        let ok = store.append(.wicketRecorded(
            batterId: batterId,
            kind: kind,
            fielderId: fielderId,
            newBatterId: newBatterId,
            runs: UInt8(completedRuns),
            onExtra: onExtra
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

// MARK: - Handing the book over

/// While one person is scoring, nobody else can alter the match. That only
/// changes when they hand it over here — or when a captain takes it because the
/// phone is dead, which the trail records either way.
private struct HandoverSheet: View {
    @ObservedObject var store: CricketMatchStore
    @Environment(\.dismiss) private var dismiss

    @State private var officials: [MatchOfficialRow] = []
    @State private var trail: [ScorerHandover] = []
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(
                        "You hold the book. Nobody else can change this match until you pass it on.",
                        systemImage: "lock.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section {
                    if officials.isEmpty {
                        Text("Nobody else is appointed to this match. Add an umpire or scorer from the match setup first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(officials) { official in
                            Button {
                                Task { await handOver(to: official) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(official.name)
                                        Text(official.label)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if isWorking {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "arrow.right.circle")
                                            .foregroundStyle(FishersTheme.accent)
                                    }
                                }
                            }
                            .disabled(isWorking)
                        }
                    }
                } header: {
                    Text("Hand over to")
                } footer: {
                    Text("They pick it up on their own phone. Anything you have not synced yet goes up first.")
                }

                if !trail.isEmpty {
                    Section("Who has had it") {
                        ForEach(trail) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.summary)
                                    .font(.footnote)
                                    .foregroundStyle(entry.isOverride ? FishersTheme.maybe : .primary)
                                Text(entry.createdAt, format: .dateTime.hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle("The book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard let matchId = store.matchId else { return }
        officials = (try? await FishersAPI.matchOfficials(matchId: matchId)) ?? []
        trail = (try? await FishersAPI.scorerTrail(matchId: matchId)) ?? []
    }

    private func handOver(to official: MatchOfficialRow) async {
        guard let matchId = store.matchId else { return }
        isWorking = true
        defer { isWorking = false }
        // Everything scored so far goes up before the book moves, or it would
        // be stranded on this phone.
        await CricketSyncService.shared.flush()
        do {
            _ = try await FishersAPI.handOverScoring(matchId: matchId, toUserId: official.userId)
            store.releaseScoring()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Player of the match

private struct AwardSheet: View {
    @ObservedObject var store: CricketMatchStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(candidates) { player in
                Button {
                    _ = store.append(.playerOfTheMatch(playerId: player.id))
                    dismiss()
                } label: {
                    HStack {
                        Text(player.name)
                        Spacer()
                        if store.state.playerOfTheMatch == player.id {
                            Image(systemName: "star.fill").foregroundStyle(FishersTheme.maybe)
                        }
                    }
                }
            }
            .navigationTitle("Player of the match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var candidates: [MatchPlayer] {
        store.state.players(for: .home) + store.state.players(for: .away)
    }
}

// MARK: - Super over

/// One over a side, two wickets, three batters. Whoever batted second in the
/// match bats first here.
private struct SuperOverSheet: View {
    @ObservedObject var store: CricketMatchStore
    @Environment(\.dismiss) private var dismiss

    @State private var strikerId: UUID?
    @State private var nonStrikerId: UUID?
    @State private var bowlerId: UUID?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        "One over each. Two wickets down and the innings is over.",
                        systemImage: "bolt.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("\(store.state.name(for: batting)) bat first")
                } footer: {
                    Text("The side that batted second in the match opens the super over.")
                }

                Section("Openers") {
                    picker("Striker", $strikerId, batters)
                    picker("Non-striker", $nonStrikerId, batters)
                }
                Section("Bowler") {
                    picker("Bowler", $bowlerId, bowlers)
                }

                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle("Super over")
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
                bowlerId = bowlers.first?.id
            }
        }
    }

    private var batting: MatchSide {
        store.state.superOverFirstBatting ?? .away
    }

    private var batters: [MatchPlayer] { store.state.players(for: batting) }
    private var bowlers: [MatchPlayer] { store.state.players(for: batting.opposite) }

    private func picker(
        _ title: String, _ selection: Binding<UUID?>, _ players: [MatchPlayer]
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
        let next = UInt8(store.state.innings.count)
        if store.append(.inningsStarted(
            inningsIndex: next, batting: batting,
            strikerId: s, nonStrikerId: ns, bowlerId: b, superOver: true
        )) {
            dismiss()
        } else {
            message = store.lastError
        }
    }
}

// MARK: - Penalty runs

/// Runs the umpire awards that nobody bowled or ran.
private struct PenaltySheet: View {
    @ObservedObject var store: CricketMatchStore
    @Environment(\.dismiss) private var dismiss

    @State private var runs = 5
    @State private var reason = PenaltyReason.slowOverRate
    @State private var otherReason = ""
    @State private var toSide: MatchSide = .home

    enum PenaltyReason: String, CaseIterable, Identifiable {
        case slowOverRate = "Slow over rate"
        case helmet = "Ball hit a fielding helmet"
        case fielding = "Fielding infringement"
        case damage = "Damaging the pitch"
        case other = "Other"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(runs) run\(runs == 1 ? "" : "s")", value: $runs, in: 1...10)
                } header: {
                    Text("Award")
                } footer: {
                    Text("Five is the usual. They go to the side batting, and against nobody's bowling figures.")
                }

                Section {
                    Picker("To", selection: $toSide) {
                        Text(store.state.homeName).tag(MatchSide.home)
                        Text(store.state.awayName).tag(MatchSide.away)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Who gets them")
                } footer: {
                    Text(sideFootnote)
                }

                Section("What for") {
                    Picker("Reason", selection: $reason) {
                        ForEach(PenaltyReason.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if reason == .other {
                        TextField("Reason", text: $otherReason)
                    }
                }
            }
            .navigationTitle("Penalty runs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Award") {
                        let text = reason == .other
                            ? otherReason.trimmingCharacters(in: .whitespaces)
                            : reason.rawValue
                        _ = store.append(.penaltyRuns(
                            runs: UInt8(runs),
                            reason: text.isEmpty ? "Penalty" : text,
                            toSide: toSide
                        ))
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .onAppear {
            toSide = store.state.currentInnings?.batting ?? .home
        }
        .presentationDetents([.medium, .large])
    }

    /// Runs awarded to a side that has not batted yet wait and open their
    /// innings — five runs are five runs whether or not anyone has faced a ball.
    private var sideFootnote: String {
        let batting = store.state.currentInnings?.batting
        if toSide == batting {
            return "They go straight onto the score, and against nobody's bowling figures."
        }
        let alreadyBatted = store.state.innings.contains { $0.batting == toSide }
        return alreadyBatted
            ? "\(store.state.name(for: toSide)) have batted, so the runs go onto that innings."
            : "\(store.state.name(for: toSide)) have not batted yet, so the runs open their innings."
    }
}

// MARK: - Correcting an earlier ball

/// Scorers get it wrong three balls ago, not just on the last one. This winds
/// the innings back to a chosen delivery so it can be re-entered — the log stays
/// append-only, because winding back is itself recorded as undo events.
private struct BallCorrectionSheet: View {
    @ObservedObject var store: CricketMatchStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirming: Int?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(
                        "Pick the ball that was wrong. Everything after it comes off, and you score them again.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if recent.isEmpty {
                    Text("Nothing bowled yet.").foregroundStyle(.secondary)
                } else {
                    Section("Recent balls") {
                        ForEach(recent, id: \.offset) { entry in
                            Button {
                                confirming = entry.offset
                            } label: {
                                HStack(spacing: 12) {
                                    Text(CricketCommentary.marker(for: entry.delivery))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 38, alignment: .leading)
                                    Text(entry.delivery.label)
                                        .font(.subheadline.weight(.semibold))
                                        .frame(width: 44, alignment: .leading)
                                    Text(summary(entry.delivery))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    if entry.offset == 0 {
                                        Text("last")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Correct a ball")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isWorking { ProgressView().controlSize(.large) }
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: Binding(
                    get: { confirming != nil },
                    set: { if !$0 { confirming = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Wind back", role: .destructive) {
                    if let offset = confirming { rewind(by: offset + 1) }
                }
                Button("Cancel", role: .cancel) { confirming = nil }
            } message: {
                Text("You will score them again from there.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Newest first, with how far back each one is.
    private var recent: [(offset: Int, delivery: DeliveryRecord)] {
        guard let inn = store.state.currentInnings else { return [] }
        return inn.deliveries.suffix(12).reversed().enumerated().map {
            (offset: $0.offset, delivery: $0.element)
        }
    }

    private var confirmationTitle: String {
        guard let offset = confirming else { return "" }
        let count = offset + 1
        return count == 1
            ? "Take off the last ball?"
            : "Take off the last \(count) balls?"
    }

    private func summary(_ delivery: DeliveryRecord) -> String {
        guard let inn = store.state.currentInnings else { return "" }
        return CricketCommentary.line(for: delivery, in: store.state, innings: inn)
    }

    private func rewind(by count: Int) {
        confirming = nil
        isWorking = true
        defer { isWorking = false }
        // One undo per event, checking as we go: extras and wickets are events
        // too, so the count of deliveries is what has to come down.
        let target = (store.state.currentInnings?.deliveries.count ?? 0) - count
        var guardRail = 0
        while (store.state.currentInnings?.deliveries.count ?? 0) > max(target, 0),
              guardRail < 60 {
            guardRail += 1
            if !store.append(.undoLast) { break }
        }
        dismiss()
    }
}

// MARK: - Where the field is

/// The two counts the Laws actually restrict. The app does not police the field
/// — it tells the scorer when the field they have entered breaks the
/// restriction, and the umpire calls it.
struct FieldSheet: View {
    @ObservedObject var store: CricketMatchStore
    @Environment(\.dismiss) private var dismiss

    @State private var outside = 2
    @State private var behindSquare = 2

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(outside) outside the circle", value: $outside, in: 0...11)
                } header: {
                    Text("Fielders")
                } footer: {
                    Text(circleFootnote)
                }

                Section {
                    Stepper(
                        "\(behindSquare) behind square on the leg side",
                        value: $behindSquare,
                        in: 0...11
                    )
                } footer: {
                    Text("Two at most, in every format.")
                }

                if !breaches.isEmpty {
                    Section {
                        ForEach(breaches, id: \.self) { breach in
                            Label(breach, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(FishersTheme.unavailable)
                        }
                    } header: {
                        Text("That field is not legal")
                    } footer: {
                        Text("The umpire calls a no ball for this — the app only tells you it has happened.")
                    }
                }
            }
            .navigationTitle("The field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        _ = store.append(.fieldSet(
                            outsideCircle: UInt8(outside),
                            behindSquareLeg: UInt8(behindSquare)
                        ))
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                if let inn = store.state.currentInnings {
                    outside = Int(inn.fieldersOutside
                        ?? store.state.conditions.fieldersAllowedOutside(inPowerplay: inn.inPowerplay))
                    behindSquare = Int(inn.fieldersBehindSquareLeg ?? 2)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var circleFootnote: String {
        guard let inn = store.state.currentInnings else { return "" }
        let allowed = store.state.conditions.fieldersAllowedOutside(inPowerplay: inn.inPowerplay)
        return inn.inPowerplay
            ? "\(allowed) allowed during the powerplay."
            : "\(allowed) allowed outside the powerplay."
    }

    /// Checked against what is being entered, not what was last saved.
    private var breaches: [String] {
        guard var inn = store.state.currentInnings else { return [] }
        inn.fieldersOutside = UInt8(outside)
        inn.fieldersBehindSquareLeg = UInt8(behindSquare)
        return inn.fieldingBreaches(store.state.conditions)
    }
}
