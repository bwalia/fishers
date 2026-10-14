import SwiftUI
import UIKit

/// How often the scorer is asked where the ball went.
enum WagonWheelMode: String, CaseIterable, Identifiable {
    case off, boundaries, everyScoringShot

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return tr("Off")
        case .boundaries: return tr("Boundaries")
        case .everyScoringShot: return tr("Every shot")
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
    @State private var showCallOff = false
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
    /// Which side this phone plays for and who the visitors are — the server's
    /// to say, and only asked at an innings break.
    @State private var matchInfo: CricketMatchDTO?
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
    /// The side batting next, when handing them the book would help — not
    /// when this phone is already on that side, and not when that side is not
    /// a club on Fishers, where nobody has an account to hand it to.
    private var handOverTo: MatchSide? {
        guard let match = matchInfo, let batting = innings?.batting else { return nil }
        let next = batting.opposite
        guard match.myClubSide != next, next == .home || match.opponentClubId != nil else { return nil }
        return next
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
        .overlay(alignment: .top) { MomentsBanner(state: store.state) }
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
        .sheet(isPresented: $showCallOff) { CallItOffSheet(store: store) }
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
                            Button(t("ev.done")) { showScorecard = false }
                        }
                    }
            }
        }
        .confirmationDialog(tr("End the innings here?"),
            isPresented: $confirmEndInnings,
            titleVisibility: .visible
        ) {
            Button(t("sc.end_innings"), role: .destructive) {
                _ = store.append(.inningsCompleted(declared: false, forfeited: false))
            }
            if store.state.conditions.twoInnings {
                // Only a declaration game has these, and only there do they mean
                // anything: a closed innings, one given up, or a drawn match.
                Button(t("sc.declare")) {
                    _ = store.append(.inningsCompleted(declared: true, forfeited: false))
                }
                Button(t("sc.forfeit_the_innings"), role: .destructive) {
                    _ = store.append(.inningsCompleted(declared: false, forfeited: true))
                }
                Button(t("sc.match_drawn")) {
                    _ = store.append(.matchCompleted(winner: nil, margin: "Match drawn"))
                }
            }
            Button(t("sc.keep_scoring"), role: .cancel) {}
        } message: {
            Text(t("sc.declarations_and_rain"))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await shareLiveLink(postToChat: false, presentSheet: true) }
                    } label: {
                        Label(t("sc.share_via_whatsapp_mail"), systemImage: "square.and.arrow.up")
                    }
                    Button {
                        Task { await shareLiveLink(postToChat: true, presentSheet: true) }
                    } label: {
                        Label(t("sc.share_and_post_to_club_chat"), systemImage: "bubble.left.and.bubble.right")
                    }
                } label: {
                    if isSharing {
                        ProgressView()
                    } else {
                        Label(t("sc.share"), systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isSharing || store.matchId == nil)
                .accessibilityLabel(tr("Share live scoreboard"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(tr("Wagon wheel"), selection: $wheelModeRaw) {
                        ForEach(WagonWheelMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    Divider()
                    Button {
                        showCorrection = true
                    } label: {
                        Label(t("sc.correct_an_earlier_ball"), systemImage: "arrow.uturn.backward.badge.clock")
                    }
                    Button {
                        showField = true
                    } label: {
                        Label(t("sc.set_the_field"), systemImage: "circle.dashed.inset.filled")
                    }
                    Button {
                        showPenalty = true
                    } label: {
                        Label(t("sc.penalty_runs"), systemImage: "exclamationmark.triangle")
                    }
                    Divider()
                    Button {
                        showHandover = true
                    } label: {
                        Label(t("sc.hand_the_book_over"), systemImage: "person.2.arrow.trianglehead.swap")
                    }
                    Button {
                        showRain = true
                    } label: {
                        Label(t("sc.overs_reduced_rain"), systemImage: "cloud.rain.fill")
                    }
                    Button {
                        showScorecard = true
                    } label: {
                        Label(t("ld.scorecard"), systemImage: "list.bullet.rectangle")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showCallOff = true
                    } label: {
                        Label(t("la.call_this_match_off"), systemImage: "xmark.octagon")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: store.state.status) {
            guard store.state.status == .inningsBreak, matchInfo == nil, let id = store.matchId else { return }
            matchInfo = try? await FishersAPI.match(matchId: id)
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
                .accessibilityLabel(tr("Full scorecard"))
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
                    Label(t("sc.super_over_n", vars: ["n": store.state.superOvers]), systemImage: "bolt.fill")
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
                    .accessibilityLabel(t("sc.powerplay_n_overs_left", vars: ["n": inn.powerplayOversLeft]))
                }
                if inn.freeHit {
                    Label(t("sc.free_hit_banner"), systemImage: "shield.lefthalf.filled")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FishersTheme.maybe)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(FishersTheme.maybe.opacity(0.15), in: Capsule())
                        .accessibilityLabel(tr("Free hit"))
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

            // The reply to a super over also arrives at an innings break, and
            // it is not "the second innings": it is one over, two wickets, and
            // the other side's turn. Sending it down the normal path is what
            // gave one side three innings and the other one.
            if store.state.status == .inningsBreak && store.state.nextIsSuperOver {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        "\(store.state.name(for: store.state.superOverNextBatting ?? .away)) reply — one over, two wickets.",
                        systemImage: "bolt.fill"
                    )
                    .font(FishersTheme.headline)
                    .foregroundStyle(FishersTheme.seam)
                    Button(t("la.start_the_reply")) { showSuperOver = true }
                        .buttonStyle(.borderedProminent)
                        .tint(FishersTheme.accent)
                }
            } else if store.state.status == .inningsBreak {
                // The first decision of the break: naming the openers of a
                // side you do not know is the wrong job, and this is the
                // moment to pass it on.
                if let next = handOverTo {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("sc.the_side_batting_normally_keeps_their"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            showHandover = true
                        } label: {
                            Label(t("sc.hand_the_book_to", vars: ["name": store.state.name(for: next)]), systemImage: "book")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Button(t("sc.start_second_innings")) { showSecondInnings = true }
                    .buttonStyle(.borderedProminent)
                    .tint(FishersTheme.accent)
            }
            if store.state.needsASuperOver {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        store.state.superOvers == 0
                            ? tr("Scores level. It goes to a super over.")
                            : "Still level after \(store.state.superOvers) super over\(store.state.superOvers == 1 ? "" : "s").",
                        systemImage: "bolt.fill"
                    )
                    .font(FishersTheme.headline)
                    .foregroundStyle(FishersTheme.seam)
                    Button(t("la.start_the_super_over")) { showSuperOver = true }
                        .buttonStyle(.borderedProminent)
                        .tint(FishersTheme.seam)
                }
            }
            if store.state.status.isFinished {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.state.margin ?? tr("Match complete"))
                        .font(FishersTheme.headline)
                        .foregroundStyle(FishersTheme.pitch)
                    if let award = store.state.playerOfTheMatch {
                        Label(t("sc.player_of_the_match_is", vars: ["name": store.name(for: award)]), systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FishersTheme.maybe)
                    }
                    HStack {
                        Button(store.state.playerOfTheMatch == nil ? tr("Award") : tr("Change award")) {
                            showAward = true
                        }
                        .buttonStyle(.bordered)
                        Button(t("ld.scorecard")) { showScorecard = true }
                            .buttonStyle(.bordered)
                        Button(t("ev.done"), action: onDone)
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
            Text(onStrike ? tr("STRIKER") : tr("NON-STRIKER"))
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
            Text(t("rest.this_over"))
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
                Label(String(format: tr("CRR %.2f"), inn.runRate), systemImage: "speedometer")
                if let rrr = store.state.requiredRunRate, inn.index >= 1 {
                    Label(String(format: tr("RRR %.2f"), rrr), systemImage: "target")
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
                Text(String(format: tr("%.1f overs an hour"), rate))
                Text("·")
                Text(
                    behind >= 0
                        ? String(format: tr("%.1f over%@ behind"), behind, abs(behind) == 1 ? "" : "s")
                        : String(format: tr("%.1f ahead"), -behind)
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
                    : tr("On the over rate")
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
            .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 10))
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
            .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 10))
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
                Text(t("la.extras"))
                    .font(FishersTheme.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(tr("Extras"))
            HStack(spacing: 10) {
                Button { showWicket = true } label: {
                    Text(t("sc.wicket"))
                        .font(FishersTheme.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(FishersTheme.seam)
                .accessibilityLabel(tr("Wicket"))

                Button {
                    if store.append(.undoLast) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    Label(t("sc.undo"), systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
                .disabled(store.state.lastSeq == 0)
                .accessibilityLabel(tr("Undo last ball"))
            }
            HStack {
                Button(t("sc.change_bowler")) { showBowler = true }
                Spacer()
                Button(t("sc.end_innings")) { confirmEndInnings = true }
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
            let last = inn.lastOverBowler.map { store.name(for: $0) } ?? tr("That bowler")
            Button { showBowler = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("sc.over_n_done_who_next", vars: ["n": Int(inn.legalBalls) / 6]))
                            .font(FishersTheme.headline)
                        Text(t("sc.bowled_it_nobody_two_in_row", vars: ["name": last]))
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
            .accessibilityHint(tr("Choose the next bowler to carry on scoring"))
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
        .accessibilityLabel(t("la.over_runs", count: runs, vars: ["n": runs]))
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
                shortRuns: 0,
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
        case .saved: return tr("Saved")
        case .syncing: return tr("Syncing…")
        case .offline: return tr("Offline — saved on this phone")
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
                    Picker(tr("Type"), selection: $kind) {
                        ForEach(ExtraKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(kind.footnote)
                }

                if kind != .penalty {
                    Section {
                        Stepper(runsLabel, value: $runs, in: runRange)
                        Toggle(t("sc.went_to_the_boundary"), isOn: $boundary)
                            .disabled(runs < 4)
                        if kind == .noBall {
                            Picker(tr("Those runs came"), selection: $offTheBat) {
                                Text(t("sc.off_the_bat")).tag(true)
                                Text(t("sc.as_byes")).tag(false)
                            }
                            .pickerStyle(.segmented)
                        }
                    } header: {
                        Text(kind == .bye || kind == .legBye ? tr("Runs run") : tr("Runs on top"))
                    } footer: {
                        Text(explanation)
                    }
                }

                Section {
                    HStack {
                        Text(t("sc.total_to_the_side"))
                        Spacer()
                        Text("\(totalRuns)")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(FishersTheme.accent)
                    }
                }
            }
            .fishersList()
            .navigationTitle(t("la.extras"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("sc.add")) { add() }.bold()
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
                ? tr("One run for the wide.")
                : "One for the wide plus \(runs) run — \(totalRuns) to the side, all wides."
        case .noBall where offTheBat:
            return runs == 0
                ? tr("One run for the no ball.")
                : "One for the no ball plus \(runs) off the bat — the batter gets \(runs)."
        case .noBall:
            return "One for the no ball plus \(runs) bye\(runs == 1 ? "" : "s"). Only the no ball is charged to the bowler."
        case .bye, .legBye:
            return tr("A legal ball. Nothing against the bowler, nothing to the batter.")
        case .penalty:
            return tr("Five penalty runs. No ball is bowled.")
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
                    Section(tr("Which innings")) {
                        Picker(tr("Innings"), selection: $inningsIndex) {
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
                    Text(t("sc.that_innings_now_has"))
                } footer: {
                    Text(t("sc.dls_par_first_innings_cut", count: bowledSoFar, vars: ["n": bowledSoFar]))
                }
                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle(t("sc.overs_reduced"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("sc.apply")) { apply() }.bold()
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
                        Label(t("sc.free_hit_sentence"),
                            systemImage: "shield.lefthalf.filled"
                        )
                        .font(.footnote)
                        .foregroundStyle(FishersTheme.maybe)
                    }
                }
                Section(tr("How")) {
                    Picker(tr("Dismissal"), selection: $kind) {
                        ForEach(allowedKinds) { Text($0.label).tag($0) }
                    }
                }

                if kind.canFollowAnExtra {
                    Section {
                        Toggle(t("sc.off_a_wide_or_no_ball"), isOn: $onExtra)
                    } footer: {
                        Text(t("sc.already_in_the_book_as_extra"))
                    }
                }

                if kind.canDismissNonStriker {
                    Section(tr("Who is out")) {
                        Picker(tr("Batter"), selection: $outIsStriker) {
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
                        Text(t("sc.runs_finished_before_throw"))
                    }
                }

                if kind.needsFielder {
                    Section(fielderLabel) {
                        Picker(tr("Fielder"), selection: $fielderId) {
                            Text("—").tag(UUID?.none)
                            ForEach(fielders) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    }
                }

                Section {
                    if nextIn.isEmpty && resuming.isEmpty {
                        Text(t("sc.that_is_all_out"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(tr("In next"), selection: $newBatterId) {
                            Text("—").tag(UUID?.none)
                            ForEach(nextIn) { Text($0.name).tag(UUID?.some($0.id)) }
                            ForEach(resuming) {
                                Text("\($0.name) (resuming)").tag(UUID?.some($0.id))
                            }
                        }
                    }
                } header: {
                    Text(t("sc.new_batter"))
                } footer: {
                    if !resuming.isEmpty {
                        Text(t("sc.retired_hurt_can_return"))
                    }
                }
            }
            .navigationTitle(t("sc.wicket"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("sc.out")) { record() }.bold().disabled(!canRecord)
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
        innings?.strikerId.map { store.name(for: $0) } ?? tr("Striker")
    }

    private var nonStrikerName: String {
        innings?.nonStrikerId.map { store.name(for: $0) } ?? tr("Non-striker")
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
                    Text(t("sc.can_bowl"))
                } footer: {
                    if store.state.conditions.oversPerBowler > 0 {
                        Text(t("sc.overs_each_no_two_in_row", vars: ["n": store.state.conditions.oversPerBowler]))
                    } else {
                        Text(t("sc.no_allocation_agreed"))
                    }
                }

                if !unavailable.isEmpty {
                    Section(tr("Cannot bowl this over")) {
                        ForEach(unavailable, id: \.0.id) { player, reason in
                            row(player, reason: reason)
                        }
                    }
                }
            }
            .navigationTitle(t("sc.bowler"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
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
                        Text(t("sc.n_overs_left", count: Int(left), vars: ["n": left]))
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
                        Text(t("sc.team_need_to_win", vars: ["team": store.state.name(for: batting), "runs": target]))
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Section(tr("Opening pair")) {
                    picker("Striker", $strikerId, batters)
                    picker("Non-striker", $nonStrikerId, batters)
                }
                Section(tr("Opening bowler")) {
                    picker("Bowler", $bowlerId, bowlersAvailable)
                }
                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle(t("sc.second_innings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("sc.start")) { start() }.bold()
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
            inningsIndex: UInt8(store.state.innings.count), batting: batting,
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
    @State private var squads: MatchSquads?
    @State private var trail: [ScorerHandover] = []
    @State private var chosen: UUID?
    @State private var isWorking = false
    @State private var message: String?

    /// Officials first — they are usually who it should go to — then each
    /// side. Nobody appears twice, and you are never offered yourself.
    private var candidates: [PeoplePickerView.Group] {
        // Never offer yourself: you are the one holding it.
        var seen = Set([KeychainStore.get("user_id").flatMap(UUID.init(uuidString:))].compactMap { $0 })
        func take(_ people: [PeoplePickerView.Person]) -> [PeoplePickerView.Person] {
            people.filter { seen.insert($0.id).inserted }
        }
        return [
            .init(label: tr("Umpires"),
                  people: take(officials.map { .init(id: $0.userId, name: $0.name, note: $0.label) })),
            .init(label: squads?.home.teamName ?? tr("Home"),
                  people: take((squads?.home.players ?? []).map { .init(id: $0.id, name: $0.name) })),
            .init(label: squads?.away.teamName ?? tr("Away"),
                  people: take((squads?.away.players ?? []).map { .init(id: $0.id, name: $0.name) })),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(t("sc.you_hold_the_book"),
                        systemImage: "lock.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section {
                    PeoplePickerView(
                        groups: candidates,
                        chosen: $chosen,
                        empty: "Nobody else is named on this match yet. Pick the teams first, or appoint an umpire from the match setup."
                    )
                } header: {
                    Text(t("sc.hand_over_to"))
                } footer: {
                    Text(t("sc.anyone_playing_can_take_it"))
                }

                if chosen != nil {
                    Section {
                        Button {
                            Task { await handOver() }
                        } label: {
                            HStack {
                                Text(isWorking ? tr("Handing over…") : tr("Hand it over"))
                                Spacer()
                                if isWorking { ProgressView() }
                            }
                        }
                        .disabled(isWorking)
                    }
                }

                if !trail.isEmpty {
                    Section(tr("Who has had it")) {
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
            .navigationTitle(t("sc.the_book"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.close")) { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard let matchId = store.matchId else { return }
        officials = (try? await FishersAPI.matchOfficials(matchId: matchId)) ?? []
        squads = try? await FishersAPI.squads(matchId: matchId)
        trail = (try? await FishersAPI.scorerTrail(matchId: matchId)) ?? []
    }

    private func handOver() async {
        guard let matchId = store.matchId, let to = chosen else { return }
        isWorking = true
        defer { isWorking = false }
        // Everything scored so far goes up before the book moves, or it would
        // be stranded on this phone.
        await CricketSyncService.shared.flush()
        do {
            _ = try await FishersAPI.handOverScoring(matchId: matchId, toUserId: to)
            store.releaseScoring()
            dismiss()
        } catch let failure {
            message = (failure as? APIError)?.friendlyMessage ?? failure.localizedDescription
        }
    }
}

// MARK: - Calling the match off

/// Two different things, and the difference matters.
///
/// A match with balls in it is *abandoned*: the scorecard survives, the
/// averages count, and it goes down as no result. One nobody has scored in was
/// a mistake, and is deleted. The server draws the line; this only offers the
/// one that applies, so nobody is invited to throw away an afternoon's scoring
/// by tapping the wrong button.
private struct CallItOffSheet: View {
    @ObservedObject var store: CricketMatchStore
    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""
    @State private var isWorking = false
    @State private var message: String?

    private var hasBeenScored: Bool { store.state.lastSeq > 0 && !store.state.innings.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if hasBeenScored {
                    Section {
                        TextField(t("sc.rain_bad_light_ground_unfit"), text: $reason)
                    } header: {
                        Text(t("ev.why"))
                    } footer: {
                        Text(t("sc.no_result_explainer"))
                    }

                    Section {
                        Button(role: .destructive) {
                            Task { await abandon() }
                        } label: {
                            HStack {
                                Text(isWorking ? tr("Calling it off…") : tr("Abandon — no result"))
                                Spacer()
                                if isWorking { ProgressView() }
                            }
                        }
                        .disabled(isWorking)
                    }
                } else {
                    Section {
                        Button(role: .destructive) {
                            Task { await remove() }
                        } label: {
                            HStack {
                                Text(isWorking ? tr("Deleting…") : tr("Delete this match"))
                                Spacer()
                                if isWorking { ProgressView() }
                            }
                        }
                        .disabled(isWorking)
                    } footer: {
                        Text(t("sc.nothing_scored_removes_match"))
                    }
                }

                if let message {
                    Section {
                        Text(message).font(.footnote).foregroundStyle(FishersTheme.unavailable)
                    }
                }
            }
            .navigationTitle(t("ld.call_it_off"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.keep_playing")) { dismiss() }
                }
            }
        }
    }

    private func abandon() async {
        guard let matchId = store.matchId else { return }
        isWorking = true
        defer { isWorking = false }
        // Anything still on this phone goes up first, or the abandoned card is
        // missing its last over.
        await CricketSyncService.shared.flush()
        do {
            _ = try await FishersAPI.abandonMatch(
                matchId: matchId,
                reason: reason.trimmingCharacters(in: .whitespaces)
            )
            dismiss()
        } catch let failure {
            message = (failure as? APIError)?.friendlyMessage ?? failure.localizedDescription
        }
    }

    private func remove() async {
        guard let matchId = store.matchId else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await FishersAPI.deleteMatch(matchId: matchId)
            dismiss()
        } catch let failure {
            message = (failure as? APIError)?.friendlyMessage ?? failure.localizedDescription
        }
    }
}

// MARK: - Player of the match

private struct AwardSheet: View {
    @ObservedObject var store: CricketMatchStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !ranked.isEmpty {
                    Section {
                        ForEach(ranked) { player in
                            row(
                                id: player.playerId,
                                name: player.name,
                                detail: "\(store.state.name(for: player.side)) · \(player.line)",
                                suggested: player.playerId == ranked[0].playerId
                            )
                        }
                    } header: {
                        Text(t("sc.who_had_the_game"))
                    } footer: {
                        Text(t("sc.ranked_off_the_scorecard"))
                    }
                }
                if !others.isEmpty {
                    Section(tr("Did not feature")) {
                        ForEach(others) { player in
                            row(id: player.id, name: player.name, detail: nil, suggested: false)
                        }
                    }
                }
            }
            .navigationTitle(t("sc.player_of_the_match"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func row(id: UUID, name: String, detail: String?, suggested: Bool) -> some View {
        Button {
            _ = store.append(.playerOfTheMatch(playerId: id))
            dismiss()
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if store.state.playerOfTheMatch == id {
                    Image(systemName: "star.fill").foregroundStyle(FishersTheme.maybe)
                } else if suggested {
                    Text(t("sc.suggested"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityLabel(accessibilityLabel(name: name, detail: detail, suggested: suggested))
        // The label reads the whole row out; the identifier stays the bare
        // name so the tour can still tap a player by name.
        .accessibilityIdentifier(name)
    }

    private func accessibilityLabel(name: String, detail: String?, suggested: Bool) -> String {
        [suggested ? "Suggested" : nil, name, detail]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    /// Everyone who batted, bowled or took a catch, best game first.
    private var ranked: [PlayerImpact] { store.state.impact }

    /// The rest of both sheets — a twelfth man can still be given it.
    private var others: [MatchPlayer] {
        let listed = Set(ranked.map(\.playerId))
        return (store.state.players(for: .home) + store.state.players(for: .away))
            .filter { !listed.contains($0.id) }
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
                    Label(t("sc.one_over_each"),
                        systemImage: "bolt.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } header: {
                    Text(t("sc.team_bat_first", vars: ["team": store.state.name(for: batting)]))
                } footer: {
                    Text(t("sc.second_batting_side_opens_super_over"))
                }

                Section(tr("Openers")) {
                    picker("Striker", $strikerId, batters)
                    picker("Non-striker", $nonStrikerId, batters)
                }
                Section(tr("Bowler")) {
                    picker("Bowler", $bowlerId, bowlers)
                }

                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle(t("la.super_over"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("sc.start")) { start() }.bold()
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
        store.state.superOverNextBatting ?? .away
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
                    Text(t("sh.award"))
                } footer: {
                    Text(t("sc.five_is_the_usual"))
                }

                Section {
                    Picker(tr("To"), selection: $toSide) {
                        Text(store.state.homeName).tag(MatchSide.home)
                        Text(store.state.awayName).tag(MatchSide.away)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(t("sc.who_gets_them"))
                } footer: {
                    Text(sideFootnote)
                }

                Section(tr("What for")) {
                    Picker(tr("Reason"), selection: $reason) {
                        ForEach(PenaltyReason.allCases) { Text(tr($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if reason == .other {
                        TextField(t("sc.reason"), text: $otherReason)
                    }
                }
            }
            .navigationTitle(t("sc.penalty_runs"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("sh.award")) {
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
                    Label(t("sc.pick_the_wrong_ball"),
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if recent.isEmpty {
                    Text(t("sc.nothing_bowled_yet")).foregroundStyle(.secondary)
                } else {
                    Section(tr("Recent balls")) {
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
                                        Text(t("sc.last"))
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
            .navigationTitle(t("sc.correct_a_ball"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
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
                Button(t("sc.wind_back"), role: .destructive) {
                    if let offset = confirming { rewind(by: offset + 1) }
                }
                Button(t("sc.cancel"), role: .cancel) { confirming = nil }
            } message: {
                Text(t("sc.score_them_again_from_there"))
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
                    Text(t("sc.fielders"))
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
                    Text(t("sc.two_at_most_every_format"))
                }

                if !breaches.isEmpty {
                    Section {
                        ForEach(breaches, id: \.self) { breach in
                            Label(breach, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(FishersTheme.unavailable)
                        }
                    } header: {
                        Text(t("sc.field_not_legal"))
                    } footer: {
                        Text(t("sc.umpire_calls_no_ball"))
                    }
                }
            }
            .navigationTitle(t("sc.the_field"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("sc.set")) {
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
