import SwiftUI

/// One outside match in full — the scorecard.
///
/// Costs the server a request for this one match, where the list costs one for
/// every match being played anywhere. So the screen says how old the card is,
/// and a finished match's card is fetched once and kept for good.
struct WorldMatchView: View {
    let matchId: String

    @State private var view: WorldMatchDetailView?
    @State private var error: String?
    @State private var loaded = false
    /// Which innings is open. Nil until the card arrives, then the latest —
    /// what is happening now is what somebody came to see, not the first day.
    @State private var tab: Int?

    var body: some View {
        List {
            if let error, view == nil {
                Text(error).foregroundStyle(FishersTheme.red600)
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if let view {
                header(view)
                if let detail = view.detail {
                    if !detail.battingNow.isEmpty || !detail.bowlingNow.isEmpty {
                        crease(detail)
                    }
                    // Tabs, not a stack. A Test has four innings, and scrolling
                    // past a hundred batting rows to reach the one you wanted
                    // is hunting rather than reading.
                    if detail.innings.count > 1 {
                        inningsTabs(detail.innings)
                    }
                    if let at = tab, detail.innings.indices.contains(at) {
                        InningsSection(
                            innings: detail.innings[at],
                            title: detail.innings.title(at: at)
                        )
                    }
                    if detail.innings.isEmpty {
                        Section {
                            Text("Not a ball bowled yet.").font(.headline)
                            Text("The card will fill in once the match is under way.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        Text("No scorecard for this match yet.").font(.headline)
                        Text("If it has not started, there is nothing to show.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                freshness(view)
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .navigationTitle("Scorecard")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
            await load()
            // Only while it is actually being played. This is the one screen
            // that costs a request per match, so a finished card is never
            // asked for twice.
            while !Task.isCancelled, view?.summary.isLive == true {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                await load()
            }
        }
    }

    /// The innings picker: a chip each, with its score, scrolling sideways when
    /// four of them will not fit.
    private func inningsTabs(_ innings: [WorldInnings]) -> some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(innings.indices, id: \.self) { i in
                        Button {
                            tab = i
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(innings.tabLabel(at: i))
                                    .font(.caption.weight(.bold))
                                Text(innings[i].score ?? "—")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .opacity(0.85)
                            }
                            .padding(.horizontal, 12)
                            // 44pt is the tap target, whatever the chip looks like.
                            .frame(minHeight: 44)
                            .background(
                                Capsule().fill(
                                    tab == i ? FishersTheme.accent : Color.secondary.opacity(0.12)
                                )
                            )
                            .foregroundStyle(tab == i ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(innings.title(at: i)), \(innings[i].score ?? "no score")")
                        .accessibilityAddTraits(tab == i ? [.isSelected, .isButton] : .isButton)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        }
    }

    @ViewBuilder
    private func header(_ v: WorldMatchDetailView) -> some View {
        Section {
            ScoreSummaryRow(match: v.summary, innings: v.detail?.innings ?? [])
            if let venue = v.detail?.venue {
                Label(venue, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func crease(_ d: WorldMatchDetail) -> some View {
        Section {
            ForEach(d.battingNow) { CreaseRow(role: "Batting", player: $0) }
            ForEach(d.bowlingNow) { CreaseRow(role: "Bowling", player: $0) }
        } header: {
            Text("At the crease")
        } footer: {
            Text("Who is in, and who is bowling at them, right now.")
        }
    }

    private func freshness(_ v: WorldMatchDetailView) -> some View {
        Section {
            Text(
                v.detailAsOf == nil
                    ? "No scorecard loaded."
                    : v.summary.phase == "done"
                        ? "Scorecard updated \(v.freshness). This match has finished, so this is the final card."
                        : "Scorecard updated \(v.freshness). It comes from a free feed and runs a few minutes behind play."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        do {
            let next = try await FishersAPI.worldMatch(matchId)
            view = next
            let count = next.detail?.innings.count ?? 0
            // A refresh must not throw somebody back to the innings they were
            // not reading — only a first load picks for them.
            if count == 0 {
                tab = nil
            } else if tab == nil || (tab ?? 0) >= count {
                tab = count - 1
            }
            error = nil
        } catch {
            // Keep whatever is on screen: a momentary failure should not blank
            // a card somebody is reading.
            if view == nil { self.error = error.localizedDescription }
        }
        loaded = true
    }
}

/// The match itself, at the top of its own page.
private struct ScoreSummaryRow: View {
    let match: WorldMatch
    /// The card is fetched separately from the summary and can be a quarter of
    /// an hour fresher, so the header reads off the card when there is one.
    /// Two different numbers for the same thing on one screen reads as a bug.
    let innings: [WorldInnings]

    private var homeScore: String? { innings.sideScore(for: match.homeTeamName) ?? match.homeScore }
    private var awayScore: String? { innings.sideScore(for: match.awayTeamName) ?? match.awayScore }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(match.leagueName)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            side(match.homeTeamName, homeScore, match.homeInfo, match.homeBatting)
            side(match.awayTeamName, awayScore, match.awayInfo, match.awayBatting)
            if let report = match.report {
                Text(report).font(.caption).foregroundStyle(.secondary)
            }
            Text(match.state)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(match.isLive ? FishersTheme.red600 : Color.secondary)
        }
        .padding(.vertical, 2)
    }

    private func side(_ name: String, _ score: String?, _ info: String?, _ batting: Bool) -> some View {
        HStack {
            Text(name).font(.subheadline.weight(batting ? .bold : .regular)).lineLimit(1)
            if batting {
                Text("· batting").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(score ?? "—").font(.subheadline.weight(.semibold)).monospacedDigit()
                if let info {
                    Text(info).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }
}

private struct CreaseRow: View {
    let role: String
    let player: WorldCurrentPlayer

    var body: some View {
        HStack {
            Text(role.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(player.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 8)
            Text(player.line).font(.subheadline).monospacedDigit()
        }
    }
}

/// One innings: who batted, who bowled, and how it came apart.
private struct InningsSection: View {
    let innings: WorldInnings
    let title: String

    var body: some View {
        Section {
            ForEach(innings.batting) { BatRow(row: $0) }
            if let total = innings.extras.total {
                HStack {
                    Text("WorldExtras").font(.subheadline.weight(.semibold))
                    if let b = innings.extras.breakdown {
                        Text("(\(b))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(total)").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
            }
            if !innings.fallOfWickets.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FALL OF WICKETS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(
                        innings.fallOfWickets
                            .map { fow in
                                let runs = fow.runs.map(String.init) ?? "—"
                                return "\(fow.wicket)–\(runs) \(fow.batter ?? "")"
                                    .trimmingCharacters(in: .whitespaces)
                            }
                            .joined(separator: " · ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            ForEach(innings.bowling) { BowlRow(row: $0) }
        } header: {
            HStack {
                Text(title)
                Spacer()
                if let score = innings.score {
                    Text(score).monospacedDigit()
                }
            }
        }
    }
}

private struct BatRow: View {
    let row: WorldBattingRow

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.subheadline.weight(row.notOut ? .bold : .regular))
                    .lineLimit(1)
                // The reason a scorecard is readable: a sentence, not a code.
                Text(row.howOut).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(row.runs.map(String.init) ?? "—")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
            Text(row.balls.map(String.init) ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }
}

private struct BowlRow: View {
    let row: WorldBowlingRow

    var body: some View {
        HStack {
            Text(row.name).font(.subheadline).lineLimit(1)
            Spacer(minLength: 8)
            // O–M–R–W, the way figures are read out.
            Text(figures).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var figures: String {
        let o = row.overs.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? "—"
        let m = row.maidens.map(String.init) ?? "—"
        let r = row.runs.map(String.init) ?? "—"
        let w = row.wickets.map(String.init) ?? "—"
        return "\(o)–\(m)–\(r)–\(w)"
    }
}
