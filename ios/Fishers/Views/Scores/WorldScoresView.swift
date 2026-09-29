import SwiftUI

/// Scores from the wider game — internationals and domestic competitions.
///
/// Read from our own API, which reads the score provider on a budget of a
/// hundred requests a day for the whole deployment. That is why the screen
/// always says how old the scores are instead of pretending to be a
/// broadcast: they run a few minutes behind, and a stale score that does not
/// admit it is worse than one that does.
struct WorldScoresView: View {
    @State private var scores: WorldScores?
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(FishersTheme.red600)
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if let scores, scores.enabled {
                freshnessNote(scores)
                section(
                    "Being played now",
                    note: "Matches in progress, including the intervals.",
                    matches: scores.live,
                    empty: "Nothing is being played at the moment."
                )
                section(
                    "Coming up",
                    note: "Due to start soon.",
                    matches: scores.upcoming,
                    empty: "No fixtures listed for the next few days."
                )
                section(
                    "Recent results",
                    note: "Matches that have finished.",
                    matches: scores.recent,
                    empty: "No results yet."
                )
            } else {
                offState
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .navigationTitle("Cricket scores")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await load() }
        .task {
            await load()
            // Our own API, not the score provider — this costs a database
            // query, never one of the day's hundred requests.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                await load()
            }
        }
    }

    private func freshnessNote(_ scores: WorldScores) -> some View {
        Section {
            Label(
                "Scores updated \(scores.freshness). They come from a free feed and run a few minutes behind live play.",
                systemImage: "clock"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func section(
        _ title: String,
        note: String,
        matches: [WorldMatch],
        empty: String
    ) -> some View {
        Section {
            if matches.isEmpty {
                Text(empty).font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(matches) { match in
                    NavigationLink { WorldMatchView(matchId: match.id) } label: {
                        ScoreRow(match: match)
                    }
                }
            }
        } header: {
            Text(title)
        } footer: {
            // Cricket's words do not mean quite what they do in other sports —
            // a Test at stumps is still being played — so each group says what
            // it holds.
            Text(note)
        }
    }

    private var offState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sportscourt")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("World scores aren't switched on here.").font(.headline)
            Text("They run only where a score feed is configured.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowSeparator(.hidden)
    }

    private func load() async {
        do {
            scores = try await FishersAPI.worldScores()
            error = nil
        } catch {
            // Keep whatever is on screen: a momentary failure should not blank
            // a score somebody is reading.
            if scores == nil { self.error = error.localizedDescription }
        }
        loaded = true
    }
}

/// One match, in the shape a scorecard is normally read in: who, what they
/// made, and then the sentence saying where the game stands.
private struct ScoreRow: View {
    let match: WorldMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(match.leagueName)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                stateBadge
            }

            side(
                name: match.homeTeamName,
                initials: match.homeInitials,
                logo: match.homeTeamLogo,
                score: match.homeScore,
                info: match.homeInfo,
                batting: match.homeBatting
            )
            side(
                name: match.awayTeamName,
                initials: match.awayInitials,
                logo: match.awayTeamLogo,
                score: match.awayScore,
                info: match.awayInfo,
                batting: match.awayBatting
            )

            if let report = match.report {
                Divider()
                Text(report).font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if let format = match.formatLabel {
                    Text(format)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                if match.phase == "pending", let start = match.startLabel {
                    Text("Starts \(start)").font(.caption2).foregroundStyle(.secondary)
                }
                if let country = match.countryName {
                    Text(country).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// The word is always there — "In play", "Tea", "Stumps". Colour is on top
    /// of the text, never instead of it.
    private var stateBadge: some View {
        HStack(spacing: 4) {
            if match.isLive {
                Circle().frame(width: 6, height: 6)
            }
            Text(match.state)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
        }
        .foregroundStyle(match.isLive ? FishersTheme.red600 : Color.secondary)
        .fixedSize()
    }

    private func side(
        name: String,
        initials: String,
        logo: String?,
        score: String?,
        info: String?,
        batting: Bool
    ) -> some View {
        HStack(spacing: 10) {
            badge(logo: logo, initials: initials)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.subheadline.weight(batting ? .bold : .regular))
                    .lineLimit(1)
                if batting {
                    // In words, so it survives a screen reader and a
                    // colour-blind reader alike.
                    Text("batting").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(score ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let info {
                    Text(info).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func badge(logo: String?, initials: String) -> some View {
        let side: CGFloat = 26
        if let logo, let url = URL(string: logo) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.secondary.opacity(0.1)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: side, height: side)
                .overlay(
                    Text(initials)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                )
        }
    }
}

/// The home screen's strip: what the rest of the world is playing.
///
/// Placed under the club's own "In progress" section and worded so the two
/// cannot be confused — somebody glancing at their home screen has to be able
/// to tell at once that India are 307 for 5 and their own third XI are not.
/// Shows nothing at all when the feed is off or quiet, because a section that
/// exists only to say it is empty is worse than no section.
struct WorldScoresSection: View {
    @State private var scores: WorldScores?

    var body: some View {
        Group {
            if let scores, scores.enabled, !showing.isEmpty {
                Section {
                    ForEach(showing.prefix(2)) { match in
                    NavigationLink { WorldMatchView(matchId: match.id) } label: {
                        ScoreRow(match: match)
                    }
                }
                    NavigationLink {
                        WorldScoresView()
                    } label: {
                        Text("All cricket scores").font(.subheadline.weight(.medium))
                    }
                } header: {
                    Text("Around the world")
                        .font(FishersTheme.overline)
                        .tracking(0.8)
                } footer: {
                    Text(
                        scores.live.isEmpty
                            ? "No international or domestic cricket on right now."
                            : "Internationals and domestic cricket, updated \(scores.freshness)."
                    )
                    .font(FishersTheme.footnote)
                }
            } else {
                // A zero-height row rather than an EmptyView: the load below
                // has to hang on something that exists, or the section could
                // never appear in the first place.
                Color.clear.frame(height: 0).listRowSeparator(.hidden)
            }
        }
        .task { scores = try? await FishersAPI.worldScores() }
    }

    private var showing: [WorldMatch] {
        guard let scores else { return [] }
        return scores.live.isEmpty ? scores.upcoming : scores.live
    }
}
