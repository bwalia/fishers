import SwiftUI

/// Every season on record, one discipline at a time.
///
/// Career figures are the sum of the seasons, and the averages are worked out
/// from those sums — never averaged from the seasons' own averages, which is a
/// different and wrong number.
///
/// Kept whole and separate on purpose: if these figures ever sit behind a
/// subscription, this view is the thing to wrap.
struct CareerStatsView: View {
    enum Discipline: String, CaseIterable, Identifiable {
        case batting, bowling
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    let seasons: [PlayerSeasonStats]
    let discipline: Discipline

    @State private var season: Int?

    private var years: [Int] {
        Array(Set(seasons.map(\.seasonYear))).sorted(by: >)
    }

    private var shown: [PlayerSeasonStats] {
        guard let season else { return seasons }
        return seasons.filter { $0.seasonYear == season }
    }

    var body: some View {
        if seasons.isEmpty {
            ContentUnavailableView {
                Label("No \(discipline.rawValue) figures yet",
                      systemImage: discipline == .batting ? "figure.cricket" : "circle.dotted")
            } description: {
                Text("These are worked out from matches scored on Fishers. Play one — or ask your scorer to record it here — and it shows up the same evening.")
            }
        } else {
            Section {
                if years.count > 1 {
                    seasonPicker
                }
                figures
                ForEach(shown) { row in
                    seasonRow(row)
                }
            } header: {
                Text(discipline.title)
            }

            Section("Best of it") {
                ForEach(highlights, id: \.label) { item in
                    LabeledContent {
                        Text(item.value).font(FishersTheme.figure(.title3))
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label)
                            if let when = item.season {
                                Text("\(String(when)) season")
                                    .font(FishersTheme.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private var seasonPicker: some View {
        Picker("Season", selection: $season) {
            Text("All").tag(Int?.none)
            ForEach(years, id: \.self) { year in
                Text(String(year)).tag(Int?.some(year))
            }
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    /// The four numbers a player quotes, before any table.
    private var figures: some View {
        let t = Totals(shown)
        let cells: [(String, String)] = discipline == .batting
            ? [("Runs", String(t.runs)),
               ("Innings", String(t.battingInnings)),
               ("Average", fmt(t.battingAverage)),
               ("Strike rate", fmt(t.strikeRate))]
            : [("Wickets", String(t.wickets)),
               ("Overs", fmt(t.overs, places: 1)),
               ("Average", fmt(t.bowlingAverage)),
               ("Economy", fmt(t.economy))]

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2),
                         spacing: FishersTheme.space2) {
            ForEach(cells, id: \.0) { label, value in
                VStack(spacing: 2) {
                    Text(value)
                        .font(FishersTheme.figure(.title))
                        .foregroundStyle(FishersTheme.pitch)
                    Text(label)
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, FishersTheme.space1)
                .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private func seasonRow(_ row: PlayerSeasonStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(row.seasonYear)).font(FishersTheme.headline)
                if let club = row.clubName {
                    Text(club).font(FishersTheme.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(row.matches) match\(row.matches == 1 ? "" : "es")")
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            }
            // A wrapping row of label/value pairs beats a table that scrolls
            // sideways on a phone.
            HStack(spacing: FishersTheme.space2) {
                if discipline == .batting {
                    stat("Runs", String(row.runs))
                    stat("HS", row.highScore.map(String.init) ?? "—")
                    stat("Avg", fmt(row.battingAverage))
                    stat("SR", fmt(row.strikeRate))
                } else {
                    stat("Wkts", String(row.wickets))
                    stat("Overs", fmt(row.oversBowled, places: 1))
                    stat("Avg", fmt(row.bowlingAverage))
                    stat("Econ", fmt(row.oversBowled > 0
                                     ? Double(row.bowlingRuns) / row.oversBowled : nil))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(FishersTheme.figure(.body))
            Text(label).font(FishersTheme.overline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var highlights: [(label: String, value: String, season: Int?)] {
        /// Lowest wins for economy, so that one ranks on the negative.
        func best(_ pick: (PlayerSeasonStats) -> Double?) -> PlayerSeasonStats? {
            shown.compactMap { row in pick(row).map { ($0, row) } }
                .max { $0.0 < $1.0 }?.1
        }

        if discipline == .batting {
            let hs = best { $0.highScore.map(Double.init) }
            let most = best { Double($0.runs) }
            let avg = best { $0.battingAverage }
            return [
                ("Highest score", hs?.highScore.map(String.init) ?? "—", hs?.seasonYear),
                ("Most runs in a season", most.map { String($0.runs) } ?? "—", most?.seasonYear),
                ("Best average", fmt(avg?.battingAverage), avg?.seasonYear),
            ]
        }
        let wkts = best { Double($0.wickets) }
        let econ = best { $0.oversBowled > 0 ? -Double($0.bowlingRuns) / $0.oversBowled : nil }
        let maidens = best { Double($0.maidens) }
        return [
            ("Most wickets in a season", wkts.map { String($0.wickets) } ?? "—", wkts?.seasonYear),
            ("Best economy",
             fmt(econ.flatMap { $0.oversBowled > 0 ? Double($0.bowlingRuns) / $0.oversBowled : nil }),
             econ?.seasonYear),
            ("Most maidens", maidens.map { String($0.maidens) } ?? "—", maidens?.seasonYear),
        ]
    }

    private func fmt(_ value: Double?, places: Int = 2) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.\(places)f", value)
    }
}

/// Career figures, summed. The averages come from these sums.
struct Totals {
    let matches: Int
    let runs: Int
    let wickets: Int
    let catches: Int
    let battingInnings: Int
    let notOuts: Int
    let ballsFaced: Int
    let overs: Double
    let bowlingRuns: Int

    init(_ seasons: [PlayerSeasonStats]) {
        matches = seasons.reduce(0) { $0 + $1.matches }
        runs = seasons.reduce(0) { $0 + $1.runs }
        wickets = seasons.reduce(0) { $0 + $1.wickets }
        catches = seasons.reduce(0) { $0 + $1.catches + $1.stumpings }
        battingInnings = seasons.reduce(0) { $0 + $1.battingInnings }
        notOuts = seasons.reduce(0) { $0 + $1.notOuts }
        ballsFaced = seasons.reduce(0) { $0 + $1.ballsFaced }
        overs = seasons.reduce(0) { $0 + $1.oversBowled }
        bowlingRuns = seasons.reduce(0) { $0 + $1.bowlingRuns }
    }

    /// Runs per dismissal. A player who was never out has no average, which is
    /// not the same as an average of zero.
    var battingAverage: Double? {
        let outs = battingInnings - notOuts
        return outs > 0 ? Double(runs) / Double(outs) : nil
    }

    var strikeRate: Double? {
        ballsFaced > 0 ? Double(runs) / Double(ballsFaced) * 100 : nil
    }

    var bowlingAverage: Double? {
        wickets > 0 ? Double(bowlingRuns) / Double(wickets) : nil
    }

    var economy: Double? {
        overs > 0 ? Double(bowlingRuns) / overs : nil
    }
}
