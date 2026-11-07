import SwiftUI

/// The club's season: its record, the ten leaderboards, and for a secretary
/// the box that closes it.
struct ClubSeasonSections: View {
    let season: ClubSeason
    /// Whose rows to pick out on the boards.
    let meId: UUID?
    let onClosed: () -> Void

    /// Only ever set for somebody who may close the season.
    @State private var preview: SeasonClosePreview?

    var body: some View {
        Section {
            SeasonTileGrid(tiles: recordTiles)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(t("ss.club_record"))
        }
        // Here rather than on the close box: a List runs a view's task only
        // once it has a row on screen, and the box has none until this answers.
        .task(id: "\(season.clubId)|\(season.season)|\(season.closedAt == nil)") {
            preview = await CloseSeasonSection.preview(for: season)
        }

        CloseSeasonSection(season: season, preview: preview, onClosed: onClosed)

        if season.boards.isEmpty {
            Section {
                ContentUnavailableView(
                    t("ss.no_boards", vars: ["season": season.season]),
                    systemImage: "chart.bar"
                )
            }
        } else {
            ForEach(season.boards) { board in
                Section(SeasonWords.board(board.code)) {
                    ForEach(Array(board.leaders.enumerated()), id: \.offset) { i, leader in
                        leaderRow(position: i + 1, leader: leader)
                    }
                }
            }
        }
    }

    /// Won is the one with the club's colour, as on the web: it is the
    /// number a club is proudest of.
    private var recordTiles: [SeasonTile] {
        let r = season.record
        return [
            SeasonTile(id: "played", label: t("sh.played"), value: String(r.played)),
            SeasonTile(id: "won", label: t("sh.won"), value: String(r.won),
                       sub: r.winPercent.map { t("ss.win_pct", vars: ["n": $0]) }, up: r.won > 0),
            SeasonTile(id: "lost", label: t("sh.lost"), value: String(r.lost)),
            SeasonTile(id: "tied", label: t("ss.tied_nr"), value: String(r.tiedOrNoResult)),
            SeasonTile(id: "players", label: t("ss.players"), value: String(season.players)),
        ]
    }

    @ViewBuilder
    private func leaderRow(position: Int, leader: SeasonLeader) -> some View {
        let isMe = leader.userId == meId
        let content = HStack(spacing: 10) {
            Text(String(position))
                .font(FishersTheme.subhead.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(isMe ? "\(leader.name) · \(t("ss.you"))" : leader.name)
                    .fontWeight(isMe ? .bold : .regular)
                if let detail = leader.detail {
                    Text(detail)
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(leader.value)
                .font(FishersTheme.headline.monospacedDigit())
                .foregroundStyle(isMe ? FishersTheme.pitch : FishersTheme.ink)
        }
        .accessibilityElement(children: .combine)

        if isMe {
            content
                .listRowBackground(FishersTheme.pitch.opacity(0.12))
        } else {
            NavigationLink {
                PlayerProfileView(userId: leader.userId, knownName: leader.name)
            } label: {
                content
            }
        }
    }
}

/// For a secretary: close the season, once, and every member gets theirs by
/// email. The preview says who before anything is sent, because it cannot be
/// taken back. Players never see this — the preview is refused for them, and
/// the role is asked first so they are not even sent to ask.
struct CloseSeasonSection: View {
    let season: ClubSeason
    let preview: SeasonClosePreview?
    let onClosed: () -> Void

    @State private var confirming = false
    @State private var busy = false
    @State private var note: String?

    var body: some View {
        if let closedAt = season.closedAt {
            Section {
                Label(
                    t("ss.closed_on", vars: ["date": closedAt.formatted(
                        .dateTime.day().month(.wide).year().locale(SeasonWords.locale)
                    )]),
                    systemImage: "checkmark.seal.fill"
                )
                .font(FishersTheme.footnote)
                .foregroundStyle(.secondary)
                if let note {
                    Text(note).font(FishersTheme.footnote).foregroundStyle(.secondary)
                }
            }
        } else if let preview {
            box(preview)
        }
    }

    private func box(_ preview: SeasonClosePreview) -> some View {
        Section {
            Text(t("ss.close_explainer"))
                .font(FishersTheme.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                fact("envelope", t("ss.close_will_email", vars: ["n": preview.willEmail, "members": preview.members]))
                fact("figure.cricket", t("ss.close_played", vars: ["n": preview.played]))
                fact("heart", t("ss.close_thanks"))
            }
            .padding(.vertical, 4)
            Button {
                confirming = true
            } label: {
                // An HStack, not a Label: inside a List row a Label's icon
                // is dropped from a prominent button, leaving a gap.
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                    Text(t("ss.close_button", vars: ["season": season.season]))
                }
                .font(FishersTheme.headline)
                .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
            }
            .buttonStyle(.borderedProminent)
            .tint(FishersTheme.pitch)
            .disabled(busy)
            if busy { ProgressView().frame(maxWidth: .infinity) }
            if let note {
                Text(note).font(FishersTheme.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text(t("ss.close_title", vars: ["season": season.season]))
        }
        .alert(
            t("ss.close_title", vars: ["season": season.season]),
            isPresented: $confirming
        ) {
            Button(t("ss.close_confirm_button"), role: .destructive) {
                Task { await close() }
            }
            Button(t("sc.cancel"), role: .cancel) {}
        } message: {
            Text(t("ss.close_confirm", vars: ["season": season.season, "n": preview.willEmail]))
        }
    }

    private func fact(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(FishersTheme.subhead).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(FishersTheme.pitch)
        }
    }

    /// What closing would do, or nil for anybody who may not close it.
    static func preview(for season: ClubSeason) async -> SeasonClosePreview? {
        guard season.closedAt == nil else { return nil }
        // Ask what we may do first, as the club screen does: only somebody
        // who runs the club's operations is shown the box at all.
        guard let role = try? await FishersAPI.myClubRole(clubId: season.clubId),
              role.permissions.contains("manage_club_ops")
        else { return nil }
        return try? await FishersAPI.seasonClosePreview(clubId: season.clubId, season: season.season)
    }

    private func close() async {
        busy = true
        note = nil
        defer { busy = false }
        do {
            let done = try await FishersAPI.closeSeason(clubId: season.clubId, season: season.season)
            note = t("ss.closed_now", vars: ["n": done.queued])
            onClosed()
        } catch let APIError.http(code, _) where code == 409 {
            // Somebody else closed it a moment ago. Nothing is lost: reload
            // and the screen says when.
            onClosed()
        } catch {
            note = (error as? APIError)?.errorDescription ?? t("ss.could_not_close")
        }
    }
}
