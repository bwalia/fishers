import SwiftUI
import UIKit

/// One-tap LIVE scorer — thumb-zone runs grid, wicket, extras, undo.
struct LiveScorerView: View {
    @ObservedObject var store: CricketMatchStore
    var onDone: () -> Void

    @State private var showExtras = false
    @State private var showWicket = false
    @State private var showBowler = false
    @State private var showScorecard = false
    @State private var showNewBatter = false
    @State private var pendingDismissal: DismissalKind = .bowled
    @State private var newBatterId: UUID?
    @State private var extraKind: ExtraKind = .wide
    @State private var extraRuns: Int = 1
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 0) {
                    scoreHeader.frame(maxWidth: .infinity)
                    controls.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 12) {
                    scoreHeader
                    controls
                }
            }
        }
        .padding()
        .safeAreaInset(edge: .bottom) {
            syncBar
        }
        .sheet(isPresented: $showExtras) { extrasSheet }
        .sheet(isPresented: $showWicket) { wicketSheet }
        .sheet(isPresented: $showBowler) { bowlerSheet }
        .sheet(isPresented: $showScorecard) {
            NavigationStack {
                CricketScorecardView(state: store.state, nameFor: store.name(for:))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showScorecard = false }
                        }
                    }
            }
        }
        .onChange(of: store.state.status) { _, status in
            if status == .inningsBreak || status == .complete {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private var scoreHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.state.scoreLine())
                    .font(FishersTheme.display)
                    .accessibilityLabel("Score \(store.state.scoreLine())")
                Spacer()
                Button { showScorecard = true } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .accessibilityLabel("Scorecard")
            }
            if let inn = store.state.currentInnings {
                HStack(spacing: 16) {
                    batterLine(id: inn.strikerId, label: "Striker", emphasise: true)
                    batterLine(id: inn.nonStrikerId, label: "Non-striker", emphasise: false)
                }
                if let bowler = inn.bowlerId {
                    Text("Bowling: \(store.name(for: bowler))")
                        .font(FishersTheme.subhead)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(String(format: "CRR %.2f", store.state.currentRunRate))
                    if let rrr = store.state.requiredRunRate {
                        Text(String(format: "RRR %.2f", rrr))
                    }
                    if let t = store.state.target {
                        Text("Target \(t)")
                    }
                }
                .font(FishersTheme.caption)
                .foregroundStyle(.secondary)
            }
            if store.state.status == .inningsBreak {
                Button("Start 2nd innings") { startSecondInnings() }
                    .buttonStyle(.borderedProminent)
                    .tint(FishersTheme.accent)
            }
            if store.state.status == .complete {
                Text(store.state.margin ?? "Match complete")
                    .font(FishersTheme.headline)
                Button("Done", action: onDone)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func batterLine(id: UUID?, label: String, emphasise: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(FishersTheme.overline)
                .foregroundStyle(.secondary)
            if let id, let inn = store.state.currentInnings,
               let b = inn.batters.first(where: { $0.playerId == id }) {
                Text("\(store.name(for: id)) \(b.runs) (\(b.balls))")
                    .font(emphasise ? FishersTheme.headline : FishersTheme.subhead)
                    .fontWeight(emphasise ? .bold : .regular)
            } else {
                Text("—")
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(0..<7, id: \.self) { runs in
                    runButton(runs)
                }
                Button {
                    showExtras = true
                } label: {
                    Text("Extras")
                        .font(FishersTheme.headline)
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Extras")
            }
            HStack(spacing: 10) {
                Button {
                    showWicket = true
                } label: {
                    Text("Wicket")
                        .font(FishersTheme.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(FishersTheme.seam)
                .accessibilityLabel("Wicket")

                Button {
                    _ = store.append(.undoLast)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text("Undo")
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Undo last ball")
            }
            HStack {
                Button("Change bowler") { showBowler = true }
                Spacer()
                Button("End innings") {
                    _ = store.append(.inningsCompleted)
                }
                .disabled(store.state.currentInnings?.complete == true)
            }
            .font(FishersTheme.subhead)
        }
        .disabled(store.state.status != .live)
    }

    private func runButton(_ runs: Int) -> some View {
        Button {
            let four = runs == 4
            let six = runs == 6
            _ = store.append(.deliveryRecorded(
                runs: UInt8(runs),
                isLegal: true,
                isBoundaryFour: four,
                isBoundarySix: six
            ))
            if four || six {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            if store.state.currentInnings?.ballsInCurrentOver == 0,
               (store.state.currentInnings?.legalBalls ?? 0) > 0 {
                showBowler = true
            }
        } label: {
            Text("\(runs)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(runs >= 4 ? FishersTheme.pitch : FishersTheme.accent)
        .accessibilityLabel("\(runs) run\(runs == 1 ? "" : "s")")
    }

    private var syncBar: some View {
        HStack {
            Text(syncLabel)
                .font(FishersTheme.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if let err = store.lastError {
                Text(err).font(.caption2).foregroundStyle(.red).lineLimit(1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var syncLabel: String {
        switch store.syncStatus {
        case .saved: return "Saved"
        case .syncing: return "Syncing…"
        case .offline: return "Offline"
        }
    }

    private var extrasSheet: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $extraKind) {
                    ForEach(ExtraKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
                Stepper("Runs: \(extraRuns)", value: $extraRuns, in: 1...7)
            }
            .navigationTitle("Extras")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showExtras = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        _ = store.append(.extrasRecorded(kind: extraKind, runs: UInt8(extraRuns)))
                        showExtras = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var wicketSheet: some View {
        let batting = store.state.currentInnings?.batting
        let xi = batting == .home ? store.state.homeXi : store.state.awayXi
        let candidates = xi.filter { id in
            !(store.state.currentInnings?.batters.contains { $0.playerId == id && $0.out } ?? false)
                && id != store.state.currentInnings?.strikerId
                && id != store.state.currentInnings?.nonStrikerId
        }
        return NavigationStack {
            Form {
                Picker("Dismissal", selection: $pendingDismissal) {
                    ForEach(DismissalKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
                Picker("New batter", selection: $newBatterId) {
                    Text("—").tag(UUID?.none)
                    ForEach(candidates, id: \.self) { id in
                        Text(store.name(for: id)).tag(UUID?.some(id))
                    }
                }
            }
            .navigationTitle("Wicket")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showWicket = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        guard let batter = store.state.currentInnings?.strikerId else { return }
                        let ok = store.append(.wicketRecorded(
                            batterId: batter,
                            kind: pendingDismissal,
                            fielderId: nil,
                            newBatterId: newBatterId
                        ))
                        if ok {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            showWicket = false
                        }
                    }
                }
            }
            .onAppear { newBatterId = candidates.first }
        }
        .presentationDetents([.medium])
    }

    private var bowlerSheet: some View {
        let bowling = store.state.currentInnings?.bowling
        let xi = bowling == .home ? store.state.homeXi : store.state.awayXi
        return NavigationStack {
            List(xi, id: \.self) { id in
                Button(store.name(for: id)) {
                    _ = store.append(.bowlerChanged(bowlerId: id))
                    showBowler = false
                }
            }
            .navigationTitle("New bowler")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showBowler = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func startSecondInnings() {
        let batting = store.state.innings.first?.batting.opposite ?? .away
        let batXi = batting == .home ? store.state.homeXi : store.state.awayXi
        let bowlXi = batting == .home ? store.state.awayXi : store.state.homeXi
        guard batXi.count >= 2, let bowler = bowlXi.first else { return }
        _ = store.append(.inningsStarted(
            inningsIndex: 1,
            batting: batting,
            strikerId: batXi[0],
            nonStrikerId: batXi[1],
            bowlerId: bowler
        ))
    }
}

struct CricketScorecardView: View {
    let state: MatchState
    var nameFor: (UUID) -> String

    var body: some View {
        List {
            if let margin = state.margin {
                Section("Result") { Text(margin) }
            }
            ForEach(Array(state.innings.enumerated()), id: \.offset) { _, inn in
                Section("\(state.name(for: inn.batting)) — \(inn.runs)/\(inn.wickets)") {
                    ForEach(inn.batters) { b in
                        HStack {
                            Text(nameFor(b.playerId))
                            Spacer()
                            Text("\(b.runs) (\(b.balls))")
                                .foregroundStyle(.secondary)
                            if b.out {
                                Text(b.dismissal?.label ?? "out")
                                    .font(.caption)
                                    .foregroundStyle(FishersTheme.seam)
                            }
                        }
                    }
                    Text("Extras \(inn.extras)").font(.footnote)
                }
                Section("Bowling") {
                    ForEach(inn.bowlers) { b in
                        HStack {
                            Text(nameFor(b.playerId))
                            Spacer()
                            Text("\(b.oversDisplay)-\(b.maidens)-\(b.runs)-\(b.wickets)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Scorecard")
    }
}
