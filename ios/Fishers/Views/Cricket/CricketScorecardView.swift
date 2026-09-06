import SwiftUI

/// The full card: batting, extras, total, fall of wickets, bowling, partnerships
/// — the thing people actually read after the game.
struct CricketScorecardView: View {
    let state: MatchState
    /// Supplied by the API when it has computed it; otherwise worked out here.
    var dls: DlsPar?

    @State private var tab: Tab = .card
    @State private var wheelBatter: UUID?
    @State private var inningsIndex: Int = 0

    enum Tab: String, CaseIterable, Identifiable {
        case card = "Scorecard"
        case wheel = "Wagon wheel"
        case commentary = "Commentary"
        var id: String { rawValue }
    }

    init(state: MatchState, dls: DlsPar? = nil) {
        self.state = state
        self.dls = dls ?? state.dlsPar
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            switch tab {
            case .card: card
            case .wheel: wheel
            case .commentary: commentary
            }
        }
        .navigationTitle("Scorecard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { inningsIndex = max(0, state.innings.count - 1) }
        .onChange(of: inningsIndex) { _, _ in wheelBatter = nil }
    }

    // MARK: Wagon wheel

    /// Whichever innings the reader has picked — the first innings' wheel and
    /// commentary stay reachable once the chase is under way.
    private var selectedInnings: InningsState? {
        state.innings.indices.contains(inningsIndex)
            ? state.innings[inningsIndex]
            : state.innings.last
    }

    @ViewBuilder
    private var inningsPicker: some View {
        if state.innings.count > 1 {
            Picker("Innings", selection: $inningsIndex) {
                ForEach(Array(state.innings.enumerated()), id: \.offset) { index, inn in
                    Text(state.name(for: inn.batting)).tag(index)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var wheel: some View {
        List {
            if state.innings.count > 1 {
                Section { inningsPicker }
            }
            if let innings = selectedInnings {
                Section {
                    Picker("Batter", selection: $wheelBatter) {
                        Text("Whole innings").tag(UUID?.none)
                        ForEach(innings.batters.filter(\.hasBatted)) { batter in
                            Text(state.name(for: batter.playerId)).tag(UUID?.some(batter.playerId))
                        }
                    }
                }
                Section {
                    WagonWheelChart(state: state, innings: innings, batterId: wheelBatter)
                        .padding(.vertical, 8)
                } footer: {
                    Text("Shots the scorer plotted. Boundaries reach the rope.")
                }
                if let batter = wheelBatter,
                   let stats = innings.batters.first(where: { $0.playerId == batter }) {
                    Section("\(state.name(for: batter))") {
                        LabeledContent("Runs", value: "\(stats.runs) (\(stats.balls))")
                        LabeledContent("Boundaries", value: "\(stats.fours)x4, \(stats.sixes)x6")
                        LabeledContent("Strike rate", value: String(format: "%.1f", stats.strikeRate))
                    }
                }
            } else {
                Text("No innings yet.").foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Commentary

    private var commentary: some View {
        List {
            if state.innings.count > 1 {
                Section { inningsPicker }
            }
            if let innings = selectedInnings, !innings.deliveries.isEmpty {
                ForEach(CricketCommentary.feed(for: innings, in: state, limit: 120)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(entry.marker)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .leading)
                        Text(entry.text)
                            .font(.subheadline)
                            .foregroundStyle(entry.isWicket ? FishersTheme.seam : .primary)
                            .fontWeight(entry.isWicket || entry.isBoundary ? .semibold : .regular)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text("Nothing bowled yet.").foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }

    // MARK: Scorecard

    private var card: some View {
        List {
            if let margin = state.margin {
                Section {
                    Label(margin, systemImage: "trophy.fill")
                        .font(FishersTheme.headline)
                        .foregroundStyle(FishersTheme.pitch)
                }
            } else if let chase = state.chaseLine {
                Section {
                    Text(chase)
                        .font(FishersTheme.headline)
                        .foregroundStyle(FishersTheme.accent)
                }
            }

            if let dls {
                Section {
                    LabeledContent("Par now", value: "\(dls.par)")
                    LabeledContent("Target", value: "\(dls.target)")
                    LabeledContent(
                        "Resources used",
                        value: String(format: "%.1f%% of %.1f%%", dls.resourcesUsed, dls.resourcesSecond)
                    )
                } header: {
                    Text("Duckworth–Lewis–Stern")
                } footer: {
                    Text("\(dls.summary). \(dls.methodLabel).")
                }
            }

            Section("Conditions") {
                Text(state.conditions.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let home = state.agreedHome, let away = state.agreedAway {
                    Label("Agreed by \(home) and \(away)", systemImage: "checkmark.seal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(state.innings.enumerated()), id: \.offset) { _, innings in
                battingSection(innings)
                extrasAndTotal(innings)
                if !innings.fall.isEmpty {
                    fallSection(innings)
                }
                bowlingSection(innings)
            }

            if state.innings.isEmpty {
                Section {
                    Text("No scoring yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Batting

    private func battingSection(_ innings: InningsState) -> some View {
        Section {
            HStack {
                Text("Batter").frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    Text("R").frame(width: 30, alignment: .trailing)
                    Text("B").frame(width: 30, alignment: .trailing)
                    Text("4s").frame(width: 26, alignment: .trailing)
                    Text("6s").frame(width: 26, alignment: .trailing)
                    Text("SR").frame(width: 46, alignment: .trailing)
                }
            }
            .font(FishersTheme.overline)
            .foregroundStyle(.secondary)

            ForEach(batted(innings)) { batter in
                batterRow(batter, innings: innings)
            }

            let notBatted = didNotBat(innings)
            if !notBatted.isEmpty {
                Text("Did not bat: \(notBatted.map { state.name(for: $0.playerId) }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("\(state.name(for: innings.batting)) innings")
                Spacer()
                Text("\(innings.runs)/\(innings.wickets) (\(innings.oversDisplay))")
                    .font(.caption.monospacedDigit())
            }
        }
    }

    private func batterRow(_ batter: BatterStats, innings: InningsState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(state.name(for: batter.playerId))
                            .font(.subheadline)
                        if innings.strikerId == batter.playerId && !batter.out {
                            Text("*").foregroundStyle(FishersTheme.accent)
                        }
                    }
                    Text(state.dismissalText(batter))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    Text("\(batter.runs)").frame(width: 30, alignment: .trailing).bold()
                    Text("\(batter.balls)").frame(width: 30, alignment: .trailing)
                    Text("\(batter.fours)").frame(width: 26, alignment: .trailing)
                    Text("\(batter.sixes)").frame(width: 26, alignment: .trailing)
                    Text(batter.balls == 0 ? "—" : String(format: "%.1f", batter.strikeRate))
                        .frame(width: 46, alignment: .trailing)
                }
                .font(.caption.monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func batted(_ innings: InningsState) -> [BatterStats] {
        innings.batters.filter { batter in
            batter.hasBatted
                || innings.strikerId == batter.playerId
                || innings.nonStrikerId == batter.playerId
        }
    }

    private func didNotBat(_ innings: InningsState) -> [BatterStats] {
        let played = Set(batted(innings).map(\.playerId))
        return innings.batters.filter { !played.contains($0.playerId) }
    }

    // MARK: Extras and total

    private func extrasAndTotal(_ innings: InningsState) -> some View {
        Section {
            HStack {
                Text("Extras")
                Spacer()
                Text(extrasBreakdown(innings))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(innings.extras)")
                    .font(.subheadline.monospacedDigit())
            }
            HStack {
                Text("Total").bold()
                Spacer()
                Text("\(innings.runs)/\(innings.wickets)")
                    .bold()
                    .monospacedDigit()
                Text("(\(innings.oversDisplay) ov, RR \(String(format: "%.2f", innings.runRate)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func extrasBreakdown(_ innings: InningsState) -> String {
        var parts: [String] = []
        if innings.byes > 0 { parts.append("b \(innings.byes)") }
        if innings.legByes > 0 { parts.append("lb \(innings.legByes)") }
        if innings.wides > 0 { parts.append("w \(innings.wides)") }
        if innings.noBalls > 0 { parts.append("nb \(innings.noBalls)") }
        if innings.penalties > 0 { parts.append("p \(innings.penalties)") }
        return parts.isEmpty ? "—" : "(\(parts.joined(separator: ", ")))"
    }

    // MARK: Fall of wickets and partnerships

    private func fallSection(_ innings: InningsState) -> some View {
        Section("Fall of wickets") {
            ForEach(Array(innings.fall.enumerated()), id: \.offset) { index, fall in
                HStack {
                    Text("\(index + 1)-\(fall.score)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .frame(width: 56, alignment: .leading)
                    Text(state.name(for: fall.batterId))
                        .font(.caption)
                    Spacer()
                    Text("\(fall.partnershipRuns) (\(fall.partnershipBalls))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(fall.overBall)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            if innings.partnershipBalls > 0 && !innings.complete {
                HStack {
                    Text("Unbroken")
                        .font(.caption.weight(.bold))
                        .frame(width: 56, alignment: .leading)
                    Spacer()
                    Text("\(innings.partnershipRuns) (\(innings.partnershipBalls))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(FishersTheme.accent)
                }
            }
        }
    }

    // MARK: Bowling

    private func bowlingSection(_ innings: InningsState) -> some View {
        Section {
            HStack {
                Text("Bowler").frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    Text("O").frame(width: 34, alignment: .trailing)
                    Text("M").frame(width: 24, alignment: .trailing)
                    Text("R").frame(width: 30, alignment: .trailing)
                    Text("W").frame(width: 24, alignment: .trailing)
                    Text("Econ").frame(width: 44, alignment: .trailing)
                }
            }
            .font(FishersTheme.overline)
            .foregroundStyle(.secondary)

            ForEach(innings.bowlers.filter { $0.balls > 0 || $0.runs > 0 }) { bowler in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.name(for: bowler.playerId))
                            .font(.subheadline)
                        if bowler.wides > 0 || bowler.noBalls > 0 {
                            Text(bowlerExtras(bowler))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Group {
                        Text(bowler.oversDisplay).frame(width: 34, alignment: .trailing)
                        Text("\(bowler.maidens)").frame(width: 24, alignment: .trailing)
                        Text("\(bowler.runs)").frame(width: 30, alignment: .trailing)
                        Text("\(bowler.wickets)").frame(width: 24, alignment: .trailing).bold()
                        Text(bowler.balls == 0 ? "—" : String(format: "%.2f", bowler.economy))
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.caption.monospacedDigit())
                }
            }
        } header: {
            Text("\(state.name(for: innings.bowling)) bowling")
        }
    }

    private func bowlerExtras(_ bowler: BowlerStats) -> String {
        var parts: [String] = []
        if bowler.wides > 0 { parts.append("\(bowler.wides) wd") }
        if bowler.noBalls > 0 { parts.append("\(bowler.noBalls) nb") }
        return parts.joined(separator: ", ")
    }
}

/// Compact live score for a fixture screen — tap through for the full card.
struct CricketScoreSummary: View {
    let state: MatchState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(state.innings.enumerated()), id: \.offset) { _, innings in
                HStack {
                    Text(state.name(for: innings.batting))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(innings.runs)/\(innings.wickets)")
                        .font(.subheadline.monospacedDigit().bold())
                    Text("(\(innings.oversDisplay))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let margin = state.margin {
                Text(margin)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FishersTheme.pitch)
            } else if let chase = state.chaseLine {
                Text(chase)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FishersTheme.accent)
            } else if state.innings.isEmpty {
                Text("Not started")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
