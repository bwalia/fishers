import Charts
import SwiftUI

/// "My game": the season's good news first, then the numbers, the form, the
/// bests and the milestones. Section by section, in the order the website
/// shows them, so the email, the web page and the phone tell one story.
struct MyGameSections: View {
    let game: PlayerGame
    /// False for a club-mate's game. The highlights, the trend sentences and
    /// "where you stand" are written to the reader, so they are left out
    /// rather than telling somebody that *they* reached double figures.
    var isMe = true
    /// "See the club's leaderboards", from the rank section.
    var openClub: (GameClubRank) -> Void = { _ in }

    var body: some View {
        if game.totals.matches == 0 {
            empty
        } else {
            if isMe { highlights }
            tiles
            FormSection(form: game.form, isMe: isMe)
            bests
            milestones
            if isMe, let rank = game.clubRank { rankSection(rank) }
        }
    }

    // MARK: Empty

    /// A season not started yet is an invitation, not a page of zeros.
    private var empty: some View {
        Section {
            ContentUnavailableView {
                Label(t("ss.empty_title", vars: ["season": game.season]), systemImage: "figure.cricket")
            } description: {
                VStack(spacing: 8) {
                    Text(t("ss.empty_body"))
                    if game.career.matches > 0 {
                        Text(t("ss.empty_career", count: game.career.matches, vars: ["n": game.career.matches]))
                    }
                }
            }
        }
    }

    // MARK: Highlights

    @ViewBuilder
    private var highlights: some View {
        if !game.highlights.isEmpty {
            Section(t("ss.highlights_title", vars: ["season": game.season])) {
                ForEach(Array(game.highlights.enumerated()), id: \.offset) { _, h in
                    let trophy = SeasonWords.isTrophy(h)
                    Label {
                        Text(SeasonWords.highlight(h))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: trophy ? "trophy.fill" : "checkmark.circle.fill")
                            .foregroundStyle(trophy ? FishersTheme.maybe : FishersTheme.pitch)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: Headline numbers

    private var tiles: some View {
        Section {
            SeasonTileGrid(tiles: SeasonTile.headline(now: game.totals, before: game.previous))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(
                    isMe ? t("ss.season_numbers", vars: ["season": game.season]) : t("cl.season_stats")
                )
        }
    }

    // MARK: Bests and milestones

    @ViewBuilder
    private var bests: some View {
        if !game.bests.isEmpty {
            Section(t("ss.bests_title")) {
                ForEach(game.bests) { b in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(SeasonWords.best(b.code))
                            if let where_ = bestWhere(b) {
                                Text(where_)
                                    .font(FishersTheme.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(b.value).font(FishersTheme.figure(.title3))
                            if b.thisSeason { NewThisSeasonTag() }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func bestWhere(_ b: GameBest) -> String? {
        guard let opposition = b.opposition else { return b.seasonYear.map(String.init) }
        var out = t("ss.v_opposition", vars: ["opposition": opposition])
        if let played = b.playedAt {
            out += " · \(SeasonWords.shortDate(played)) \(b.seasonYear.map(String.init) ?? "")"
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    @ViewBuilder
    private var milestones: some View {
        if !game.milestones.isEmpty {
            Section(t("ss.milestones_title")) {
                // Newest first: what just happened is what matters.
                ForEach(game.milestones.reversed()) { m in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(SeasonWords.milestone(m.code))
                            Text(milestoneWhen(m))
                                .font(FishersTheme.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if m.thisSeason { NewThisSeasonTag() }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func milestoneWhen(_ m: GameMilestone) -> String {
        let year = Calendar.current.component(.year, from: m.reachedAt)
        var out = "\(SeasonWords.shortDate(m.reachedAt)) \(year)"
        if !m.opposition.isEmpty {
            out += " · " + t("ss.v_opposition", vars: ["opposition": m.opposition])
        }
        return out
    }

    // MARK: Club rank

    @ViewBuilder
    private func rankSection(_ r: GameClubRank) -> some View {
        let shown: [(String, Int)] = [
            (t("ss.board.runs"), r.runs),
            (t("ss.board.wickets"), r.wickets),
            (t("ss.board.catches"), r.catches),
        ].compactMap { label, n in n.map { (label, $0) } }
        if !shown.isEmpty {
            Section(t("ss.rank_title", vars: ["club": r.clubName])) {
                SeasonTileGrid(tiles: shown.map { label, n in
                    SeasonTile(id: label, label: label, value: SeasonWords.place(n),
                               sub: t("ss.of_players", vars: ["n": r.players]))
                })
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                Button {
                    openClub(r)
                } label: {
                    Label(t("ss.see_leaderboards"), systemImage: "list.number")
                }
            }
        }
    }
}

// MARK: - Pieces

/// The gold "New this season" tag on a best or a milestone.
struct NewThisSeasonTag: View {
    var body: some View {
        Text(t("ss.new_this_season"))
            .font(FishersTheme.overline)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(FishersTheme.maybe)
            .background(FishersTheme.maybe.opacity(0.14), in: Capsule())
    }
}

/// Two columns of tiles. Better than last season gets the club's colour and
/// an arrow; anything else gets nothing, on purpose.
struct SeasonTileGrid: View {
    let tiles: [SeasonTile]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(tiles) { tile in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tile.label.uppercased())
                        .font(FishersTheme.overline)
                        .foregroundStyle(.secondary)
                    Text(tile.value)
                        .font(FishersTheme.figure(.title2))
                        .foregroundStyle(tile.up ? FishersTheme.pitch : FishersTheme.ink)
                    if let sub = tile.sub {
                        Text(sub)
                            .font(FishersTheme.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let was = tile.was {
                        // The arrow is the only marker there is. A figure
                        // that went down reads as last season, plainly.
                        Text((tile.up ? "▲ " : "") + t("ss.last_season", vars: ["value": was]))
                            .font(FishersTheme.caption)
                            .foregroundStyle(tile.up ? FishersTheme.pitch : .secondary)
                    }
                }
                // Every tile in a row the same height and read from the top,
                // whether or not it has a line for last season.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .fishersCard(padding: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: FishersTheme.corner, style: .continuous)
                        .strokeBorder(tile.up ? FishersTheme.pitch.opacity(0.5) : .clear, lineWidth: 1.5)
                )
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Form

/// The last ten matches: which way it is going, a bar a match, and the list.
struct FormSection: View {
    let form: GameForm
    var isMe = true

    /// Oldest on the left, so it reads the way the season went.
    private var oldestFirst: [GameFormEntry] { form.matches.reversed() }
    private var batted: Bool { form.matches.contains { $0.batted } }
    /// A column with nothing in it is a column of dashes: leave it out.
    private var bowled: Bool { form.matches.contains { $0.bowled } }

    var body: some View {
        if !form.matches.isEmpty {
            Section {
                if isMe {
                    let bat = SeasonWords.battingTrend(form.battingTrend, recent: form.recentBattingAverage)
                    let bowl = SeasonWords.bowlingTrend(form.bowlingTrend, recent: form.recentWicketsPerMatch)
                    ForEach([bat, bowl].compactMap { $0 }, id: \.self) { line in
                        Text(line)
                            .font(FishersTheme.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if batted {
                    RunsChart(matches: oldestFirst)
                        .padding(.vertical, 6)
                }
                ForEach(form.matches) { m in
                    row(m)
                }
            } header: {
                HStack {
                    Text(t("ss.form_title"))
                    Spacer()
                    Text(t("ss.last_n_matches", count: form.matches.count, vars: ["n": form.matches.count]))
                }
            }
        }
    }

    private func row(_ m: GameFormEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(m.opposition.isEmpty ? "–" : t("ss.v_opposition", vars: ["opposition": m.opposition]))
                    .font(FishersTheme.subhead.weight(.semibold))
                HStack(spacing: 6) {
                    Text(SeasonWords.shortDate(m.playedAt))
                    if m.playerOfMatch {
                        Text(t("ss.potm"))
                            .font(FishersTheme.overline)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .foregroundStyle(FishersTheme.maybe)
                            .background(FishersTheme.maybe.opacity(0.14), in: Capsule())
                    }
                }
                .font(FishersTheme.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if batted {
                    if m.batted {
                        Text("\(SeasonWords.score(m.runs, notOut: m.notOut)) (\(m.balls))")
                            .font(FishersTheme.subhead.monospacedDigit())
                    } else {
                        Text(t("ss.dnb")).font(FishersTheme.footnote).foregroundStyle(.secondary)
                    }
                }
                if bowled, m.bowled {
                    Text("\(m.wickets)/\(m.runsConceded) (\(m.overs))")
                        .font(FishersTheme.subhead.monospacedDigit())
                }
                result(m.won)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func result(_ won: Bool?) -> some View {
        let text: String
        switch won {
        case .some(true): text = t("ss.won")
        case .some(false): text = t("ss.lost")
        case .none: text = t("ss.tied_nr")
        }
        return Text(text)
            .font(FishersTheme.overline)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(won == true ? FishersTheme.pitch : .secondary)
            .background((won == true ? FishersTheme.pitch : Color.secondary).opacity(0.12), in: Capsule())
    }
}

/// Runs in each match, one bar each, oldest first. One series, so no legend:
/// the section heading names it. Only the best bar carries its number; the
/// list underneath has every one, and VoiceOver reads each bar in full.
struct RunsChart: View {
    let matches: [GameFormEntry]

    private var best: Int? {
        matches.indices.filter { matches[$0].batted }.max { matches[$0].runs < matches[$1].runs }
    }

    var body: some View {
        Chart {
            ForEach(Array(matches.enumerated()), id: \.element.id) { i, m in
                BarMark(
                    x: .value(t("ss.date"), String(i)),
                    y: .value(t("ss.runs"), m.batted ? m.runs : 0),
                    width: .ratio(0.6)
                )
                .foregroundStyle(i == best ? FishersTheme.pitch : FishersTheme.pitch.opacity(0.55))
                .cornerRadius(4)
                .annotation(position: .top, spacing: 3) {
                    if i == best {
                        Text(SeasonWords.score(m.runs, notOut: m.notOut))
                            .font(FishersTheme.caption.monospacedDigit())
                            .foregroundStyle(FishersTheme.pitch)
                    } else if !m.batted {
                        Text("–").font(FishersTheme.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("\(SeasonWords.shortDate(m.playedAt)) \(m.opposition)")
                .accessibilityValue(m.batted ? SeasonWords.score(m.runs, notOut: m.notOut) : t("ss.dnb"))
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                // Every other date when the bars are tight, newest always.
                if let i = value.as(String.self).flatMap(Int.init),
                   matches.count <= 6 || (matches.count - 1 - i) % 2 == 0 {
                    AxisValueLabel {
                        Text(SeasonWords.shortDate(matches[i].playedAt))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYScale(domain: 0...Double(max(10, (matches.map(\.runs).max() ?? 0))) * 1.15)
        .frame(height: 170)
        // A container, so each bar is still read on its own under the name.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("ss.runs_chart"))
    }
}
