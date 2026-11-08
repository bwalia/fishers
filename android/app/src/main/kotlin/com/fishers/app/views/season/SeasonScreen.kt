package com.fishers.app.views.season

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.SportsCricket
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fishers.app.R
import com.fishers.app.i18n.t
import com.fishers.app.season.Best
import com.fishers.app.season.ClubRank
import com.fishers.app.season.ClubSeason
import com.fishers.app.season.ClosePreview
import com.fishers.app.season.Form
import com.fishers.app.season.FormEntry
import com.fishers.app.season.Highlight
import com.fishers.app.season.Leaderboard
import com.fishers.app.season.Milestone
import com.fishers.app.season.PlayerGame
import com.fishers.app.season.SeasonState
import com.fishers.app.season.SeasonTab
import com.fishers.app.season.Totals
import com.fishers.app.season.bestLabel
import com.fishers.app.season.boardLabel
import com.fishers.app.season.headlineTiles
import com.fishers.app.season.highlightText
import com.fishers.app.season.isTrophy
import com.fishers.app.season.longDate
import com.fishers.app.season.milestoneLabel
import com.fishers.app.season.place
import com.fishers.app.season.score
import com.fishers.app.season.shortDate
import com.fishers.app.season.trendText
import com.fishers.app.season.yearOf
import com.fishers.app.theme.FishersTheme

/**
 * Stats, for players first — `web/src/app/stats/page.tsx`.
 *
 * "My game" opens on the good news in the season — a best, a milestone, a
 * number that went up — then the handful of figures that describe it, the
 * last ten matches, and the bests and milestones of a whole career. A lower
 * number than last season is shown as plain context, never in the error
 * colour: the page is for knowing your game, not for being marked down by it.
 *
 * "Club" is the season's record and its leaderboards, and for a secretary the
 * box that closes the season and sends every member theirs.
 */
@Composable
fun SeasonScreen(
    state: SeasonState,
    meId: String?,
    onTab: (SeasonTab) -> Unit,
    onSeason: (Int) -> Unit,
    onClub: (String) -> Unit,
    onClose: () -> Unit,
    onOpenFixtures: () -> Unit,
    onOpenClubs: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val brand = stringResource(R.string.brand_name)
    LazyColumn(
        modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    if (state.tab == SeasonTab.Mine) t("ss.my_game") else t("ss.club_season"),
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.semantics { heading() },
                )
                Text(
                    if (state.tab == SeasonTab.Mine) t("ss.my_game_intro")
                    else t("ss.club_intro", vars = mapOf("brand" to brand)),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        item { Controls(state, onTab, onSeason, onClub) }

        state.error?.let { error ->
            item {
                Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
            }
        }

        when {
            state.error != null -> Unit
            state.isLoading -> item {
                Box(Modifier.fillMaxWidth().height(160.dp), Alignment.Center) { CircularProgressIndicator() }
            }
            state.tab == SeasonTab.Mine -> state.game?.let {
                myGame(it, onOpenFixtures, onSeeLeaderboards = onClub)
            }
            state.clubId == null -> item {
                Empty(Icons.Filled.SportsCricket, t("ss.no_club")) {
                    OutlinedButton(onClick = onOpenClubs) { Text(t("rest.your_clubs")) }
                }
            }
            else -> state.club?.let { club ->
                clubSeason(
                    club = club,
                    meId = state.game?.userId ?: meId,
                    preview = state.preview,
                    isClosing = state.isClosing,
                    closeNote = state.closeNote,
                    onClose = onClose,
                )
            }
        }
    }
}

@Composable
private fun Controls(
    state: SeasonState,
    onTab: (SeasonTab) -> Unit,
    onSeason: (Int) -> Unit,
    onClub: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        TabRow(
            selectedTabIndex = state.tab.ordinal,
            modifier = Modifier.semantics { contentDescription = t("ss.view") },
        ) {
            SeasonTab.entries.forEach { tab ->
                Tab(
                    selected = state.tab == tab,
                    onClick = { onTab(tab) },
                    text = { Text(if (tab == SeasonTab.Mine) t("ss.tab_mine") else t("ss.tab_club")) },
                )
            }
        }
        ChipRow(t("sh.season")) {
            state.seasons.forEach { year ->
                FilterChip(
                    selected = state.season == year,
                    onClick = { onSeason(year) },
                    label = { Text(year.toString()) },
                )
            }
        }
        // A picker of one is not a choice; the club's name is in the heading below.
        if (state.tab == SeasonTab.Club && state.clubs.size > 1) {
            ChipRow(t("sh.club")) {
                state.clubs.forEach { club ->
                    FilterChip(
                        selected = state.clubId == club.id,
                        onClick = { onClub(club.id) },
                        label = { Text(club.name) },
                    )
                }
            }
        }
    }
}

@Composable
private fun ChipRow(label: String, chips: @Composable () -> Unit) {
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.labelLarge)
        chips()
    }
}

// MARK: My game

private fun LazyListScope.myGame(
    game: PlayerGame,
    onOpenFixtures: () -> Unit,
    onSeeLeaderboards: (String) -> Unit,
) {
    val s = game.totals
    if (s.matches == 0) {
        item {
            Empty(
                Icons.Filled.SportsCricket,
                t("ss.empty_title", vars = mapOf("season" to game.season)),
                body = t("ss.empty_body"),
                more = if (game.career.matches > 0) {
                    t("ss.empty_career", count = game.career.matches, vars = mapOf("n" to game.career.matches))
                } else {
                    null
                },
            ) {
                Button(onClick = onOpenFixtures) { Text(t("ss.see_fixtures")) }
            }
        }
        return
    }
    if (game.highlights.isNotEmpty()) item { Highlights(game.season, game.highlights) }
    item { Headline(s, game.previous, game.season) }
    if (game.form.matches.isNotEmpty()) item { FormPanel(game.form) }
    if (game.bests.isNotEmpty()) item { Bests(game.bests) }
    if (game.milestones.isNotEmpty()) item { Milestones(game.milestones) }
    game.clubRank?.let { rank ->
        if (listOfNotNull(rank.runs, rank.wickets, rank.catches).isNotEmpty()) {
            item { Rank(rank, onSee = { onSeeLeaderboards(rank.clubId) }) }
        }
    }
}

@Composable
private fun Highlights(season: Int, highlights: List<Highlight>) {
    Panel(t("ss.highlights_title", vars = mapOf("season" to season))) {
        highlights.forEach { h ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                Icon(
                    if (h.isTrophy) Icons.Filled.EmojiEvents else Icons.Filled.CheckCircle,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp),
                )
                Text(highlightText(h), style = MaterialTheme.typography.bodyLarge)
            }
        }
    }
}

/**
 * Better than last time gets the marker and the brand's colour; anything else
 * is plain context in the same grey as every other subtitle.
 */
@Composable
private fun Headline(now: Totals, before: Totals?, season: Int) {
    val tiles = headlineTiles(now, before)
    val label = t("ss.season_numbers", vars = mapOf("season" to season))
    Column(
        Modifier.semantics { contentDescription = label },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        tiles.chunked(2).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                pair.forEach { tile ->
                    StatTile(
                        label = tile.label,
                        value = tile.value,
                        sub = tile.sub,
                        emphasised = tile.up == true,
                        modifier = Modifier.weight(1f),
                    ) {
                        tile.was?.let { was ->
                            val up = tile.up == true
                            Text(
                                (if (up) "▲ " else "") + t("ss.last_season", vars = mapOf("value" to was)),
                                style = MaterialTheme.typography.labelSmall,
                                color = if (up) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                                fontWeight = if (up) FontWeight.SemiBold else FontWeight.Normal,
                            )
                        }
                    }
                }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun FormPanel(form: Form) {
    val bat = trendText(form.battingTrend, form.recentBattingAverage, batting = true)
    val bowl = trendText(form.bowlingTrend, form.recentWicketsPerMatch, batting = false)
    // Oldest on the left, so it reads the way the season went.
    val oldestFirst = form.matches.reversed()
    val batted = oldestFirst.any { it.batted }
    // A column with nothing in it is a column of dashes: leave it out.
    val bowled = oldestFirst.any { it.bowled }
    Panel(
        t("ss.form_title"),
        aside = t("ss.last_n_matches", count = oldestFirst.size, vars = mapOf("n" to oldestFirst.size)),
    ) {
        listOfNotNull(bat to form.battingTrend, bowl to form.bowlingTrend)
            .filter { it.first != null }
            .forEach { (sentence, trend) ->
                Text(
                    sentence!!,
                    style = MaterialTheme.typography.bodyMedium,
                    // Rising is worth the colour; a quieter patch is not
                    // worth a warning, so it reads like any other sentence.
                    color = if (trend == "rising") MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurface,
                )
            }
        if (batted) RunsChart(oldestFirst)
        Text(
            t("ss.form_table"),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 4.dp),
        )
        form.matches.forEachIndexed { i, m ->
            if (i > 0) HorizontalDivider()
            FormRow(m, showBatting = batted, showBowling = bowled)
        }
    }
}

@Composable
private fun FormRow(m: FormEntry, showBatting: Boolean, showBowling: Boolean) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                t("ss.v_opposition", vars = mapOf("opposition" to m.opposition.ifEmpty { "–" })),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    shortDate(m.playedAt),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (m.playerOfMatch) Tag(t("ss.potm"), gold = true)
            }
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (showBatting) {
                Text(
                    if (m.batted) "${score(m.runs, m.notOut)} (${m.balls})" else t("ss.dnb"),
                    style = if (m.batted) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.bodySmall,
                    color = if (m.batted) MaterialTheme.colorScheme.onSurface
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (showBowling && m.bowled) {
                Text(
                    "${m.wickets}/${m.runsConceded} (${m.overs})",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
        when (m.won) {
            true -> Tag(t("ss.won"))
            false -> Tag(t("ss.lost"), grey = true)
            null -> Tag(t("ss.tied_nr"), grey = true)
        }
    }
}

/**
 * Runs in each match, one bar each, oldest first. One series, so no legend:
 * the heading names it. Only the best bar carries its number — the rows
 * underneath have every one, and a screen reader is read all of them from
 * the content description, since a canvas has nothing else to say.
 */
@Composable
private fun RunsChart(matches: List<FormEntry>) {
    val bar = MaterialTheme.colorScheme.primary
    val axis = MaterialTheme.colorScheme.outlineVariant
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val ink = MaterialTheme.colorScheme.onSurface
    val measurer = rememberTextMeasurer()
    val tickStyle = TextStyle(fontSize = 10.sp, color = muted)
    val labelStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = ink)

    val max = maxOf(10, matches.maxOfOrNull { it.runs } ?: 0)
    // The first innings among the highest — what the web labels.
    val best = matches.withIndex().filter { it.value.batted }.maxByOrNull { it.value.runs }?.index
    val ticks = matches.map { shortDate(it.playedAt) }
    val described = t("ss.runs_chart") + ": " + matches.joinToString("; ") { m ->
        "${shortDate(m.playedAt)} ${m.opposition}: " +
            if (m.batted) score(m.runs, m.notOut) else t("ss.dnb")
    }

    Canvas(
        Modifier
            .fillMaxWidth()
            .height(190.dp)
            .semantics { contentDescription = described },
    ) {
        val top = 22.dp.toPx()
        val bottom = 24.dp.toPx()
        val side = 8.dp.toPx()
        val plot = size.height - top - bottom
        val slot = (size.width - side * 2) / matches.size
        val barW = minOf(36.dp.toPx(), slot - 6.dp.toPx()).coerceAtLeast(2f)
        val baseline = size.height - bottom
        // Dates only where they fit; every other one when the bars are tight.
        val every = if (slot >= 52.dp.toPx()) 1 else 2

        drawLine(axis, Offset(side, baseline), Offset(size.width - side, baseline), strokeWidth = 1.dp.toPx())
        matches.forEachIndexed { i, m ->
            val cx = side + slot * i + slot / 2
            val h = m.runs.toFloat() / max * plot
            if (m.batted) {
                if (h > 0f) {
                    val r = minOf(4.dp.toPx(), h)
                    drawRoundRect(
                        bar,
                        topLeft = Offset(cx - barW / 2, baseline - h),
                        size = Size(barW, h),
                        cornerRadius = CornerRadius(r, r),
                    )
                    // Rounded at the top only: a bar stands on the axis.
                    drawRect(bar, Offset(cx - barW / 2, baseline - r / 2), Size(barW, r / 2))
                }
            } else {
                val dash = measurer.measure("–", tickStyle)
                drawText(dash, topLeft = Offset(cx - dash.size.width / 2, baseline - dash.size.height - 2.dp.toPx()))
            }
            if (i == best) {
                val label = measurer.measure(score(m.runs, m.notOut), labelStyle)
                drawText(
                    label,
                    topLeft = Offset(cx - label.size.width / 2, baseline - h - label.size.height - 2.dp.toPx()),
                )
            }
            if ((matches.size - 1 - i) % every == 0) {
                val tick = measurer.measure(ticks[i], tickStyle)
                drawText(tick, topLeft = Offset(cx - tick.size.width / 2, baseline + 4.dp.toPx()))
            }
        }
    }
}

@Composable
private fun Bests(bests: List<Best>) {
    Panel(t("ss.bests_title")) {
        bests.forEachIndexed { i, b ->
            if (i > 0) HorizontalDivider()
            ListLine(
                label = bestLabel(b.code),
                sub = if (b.opposition != null) {
                    t("ss.v_opposition", vars = mapOf("opposition" to b.opposition)) +
                        (b.playedAt?.let { " · ${shortDate(it)} ${b.seasonYear ?: ""}" } ?: "")
                } else {
                    b.seasonYear?.toString()
                },
                value = b.value,
                fresh = b.thisSeason,
            )
        }
    }
}

@Composable
private fun Milestones(milestones: List<Milestone>) {
    Panel(t("ss.milestones_title")) {
        // Newest first: what just happened is what matters.
        milestones.reversed().forEachIndexed { i, m ->
            if (i > 0) HorizontalDivider()
            ListLine(
                label = milestoneLabel(m.code),
                sub = "${shortDate(m.reachedAt)} ${yearOf(m.reachedAt)}" +
                    if (m.opposition.isNotEmpty()) {
                        " · " + t("ss.v_opposition", vars = mapOf("opposition" to m.opposition))
                    } else {
                        ""
                    },
                value = null,
                fresh = m.thisSeason,
            )
        }
    }
}

@Composable
private fun ListLine(label: String, sub: String?, value: String?, fresh: Boolean) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            sub?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        value?.let { Text(it, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold) }
        if (fresh) Tag(t("ss.new_this_season"), gold = true)
    }
}

@Composable
private fun Rank(rank: ClubRank, onSee: () -> Unit) {
    val rows = listOf(
        t("ss.board.runs") to rank.runs,
        t("ss.board.wickets") to rank.wickets,
        t("ss.board.catches") to rank.catches,
    ).mapNotNull { (label, n) -> n?.let { label to it } }
    Panel(t("ss.rank_title", vars = mapOf("club" to rank.clubName))) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            rows.forEach { (label, n) ->
                StatTile(
                    label = label,
                    value = place(n),
                    sub = t("ss.of_players", vars = mapOf("n" to rank.players)),
                    modifier = Modifier.weight(1f),
                    inset = true,
                )
            }
        }
        TextButton(onClick = onSee) { Text(t("ss.see_leaderboards")) }
    }
}

// MARK: The club

private fun LazyListScope.clubSeason(
    club: ClubSeason,
    meId: String?,
    preview: ClosePreview?,
    isClosing: Boolean,
    closeNote: String?,
    onClose: () -> Unit,
) {
    item {
        Text(club.clubName, style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
    }
    item { Record(club) }
    item {
        CloseSeason(club, preview, isClosing, closeNote, onClose)
    }
    if (club.boards.isEmpty()) {
        item {
            Empty(Icons.Filled.SportsCricket, t("ss.no_boards", vars = mapOf("season" to club.season)))
        }
    } else {
        club.boards.forEach { board ->
            item(key = "board-${board.code}") { Board(board, meId) }
        }
    }
}

@Composable
private fun Record(club: ClubSeason) {
    val r = club.record
    val label = t("ss.club_record")
    Column(
        Modifier.semantics { contentDescription = label },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StatTile(t("sh.played"), r.played.toString(), modifier = Modifier.weight(1f))
            StatTile(
                t("sh.won"),
                r.won.toString(),
                sub = r.winPercent?.let { t("ss.win_pct", vars = mapOf("n" to it)) },
                emphasised = true,
                modifier = Modifier.weight(1f),
            )
            StatTile(t("sh.lost"), r.lost.toString(), modifier = Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StatTile(t("ss.tied_nr"), r.tiedOrNoResult.toString(), modifier = Modifier.weight(1f))
            StatTile(t("ss.players"), club.players.toString(), modifier = Modifier.weight(1f))
            Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun Board(board: Leaderboard, meId: String?) {
    Panel(boardLabel(board.code)) {
        board.leaders.forEachIndexed { i, l ->
            val me = l.userId == meId
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(
                        if (me) MaterialTheme.colorScheme.primaryContainer else androidx.compose.ui.graphics.Color.Transparent,
                        RoundedCornerShape(8.dp),
                    )
                    .padding(horizontal = 8.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(
                    "${i + 1}",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.width(20.dp),
                )
                Column(Modifier.weight(1f)) {
                    Text(
                        if (me) "${l.name} · ${t("ss.you")}" else l.name,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = if (me) FontWeight.Bold else FontWeight.Normal,
                    )
                    l.detail?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                Text(l.value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
        }
    }
}

/**
 * For a secretary: close the season, once, and every member gets theirs by
 * email. The facts say who before anything is sent and the dialog says it
 * cannot be undone, because it cannot. Players never see this — the view
 * model only fetches the preview for someone with `manage_club_ops`.
 */
@Composable
private fun CloseSeason(
    club: ClubSeason,
    preview: ClosePreview?,
    isClosing: Boolean,
    note: String?,
    onClose: () -> Unit,
) {
    if (club.closedAt != null) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            note?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Filled.CheckCircle,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(16.dp),
                )
                Text(
                    t("ss.closed_on", vars = mapOf("date" to longDate(club.closedAt))),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        return
    }
    if (preview == null) return

    var confirming by remember { mutableStateOf(false) }
    Panel(t("ss.close_title", vars = mapOf("season" to club.season)), outlined = true) {
        Text(
            t("ss.close_explainer"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        listOf(
            t("ss.close_will_email", vars = mapOf("n" to preview.willEmail, "members" to preview.members)),
            t("ss.close_played", vars = mapOf("n" to preview.played)),
            t("ss.close_thanks"),
        ).forEach { Text("•  $it", style = MaterialTheme.typography.bodyMedium) }
        Button(onClick = { confirming = true }, enabled = !isClosing) {
            Icon(Icons.Filled.Email, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(t("ss.close_button", vars = mapOf("season" to club.season)))
        }
        note?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
    }

    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(t("ss.close_title", vars = mapOf("season" to club.season))) },
            text = {
                Text(t("ss.close_confirm", vars = mapOf("season" to club.season, "n" to preview.willEmail)))
            },
            confirmButton = {
                TextButton(onClick = { confirming = false; onClose() }) {
                    Text(t("ss.close_confirm_button"))
                }
            },
            dismissButton = { TextButton(onClick = { confirming = false }) { Text(t("sc.cancel")) } },
        )
    }
}

// MARK: Parts

@Composable
private fun Panel(
    title: String,
    aside: String? = null,
    outlined: Boolean = false,
    content: @Composable () -> Unit,
) {
    Card(
        Modifier.fillMaxWidth(),
        border = if (outlined) {
            androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.primary)
        } else {
            androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
        },
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    title,
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                aside?.let {
                    Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            content()
        }
    }
}

@Composable
private fun StatTile(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    sub: String? = null,
    emphasised: Boolean = false,
    inset: Boolean = false,
    extra: @Composable () -> Unit = {},
) {
    Card(
        modifier,
        colors = CardDefaults.cardColors(
            containerColor = when {
                emphasised -> MaterialTheme.colorScheme.primaryContainer
                inset -> MaterialTheme.colorScheme.surfaceVariant
                else -> MaterialTheme.colorScheme.surface
            },
        ),
        border = if (inset) null else androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            sub?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            extra()
        }
    }
}

@Composable
private fun Tag(text: String, gold: Boolean = false, grey: Boolean = false) {
    Surface(
        shape = RoundedCornerShape(50),
        color = when {
            gold -> MaterialTheme.colorScheme.secondaryContainer
            grey -> MaterialTheme.colorScheme.surfaceVariant
            else -> MaterialTheme.colorScheme.primaryContainer
        },
        contentColor = when {
            gold -> MaterialTheme.colorScheme.onSecondaryContainer
            grey -> MaterialTheme.colorScheme.onSurfaceVariant
            else -> MaterialTheme.colorScheme.onPrimaryContainer
        },
    ) {
        Text(text, style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp))
    }
}

/** Friendly rather than a page of zeros: what will be here, and where to go next. */
@Composable
private fun Empty(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    body: String? = null,
    more: String? = null,
    action: @Composable () -> Unit = {},
) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            Modifier.fillMaxWidth().padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(28.dp))
            Text(title, style = MaterialTheme.typography.titleMedium, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            body?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
            }
            more?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
            }
            action()
        }
    }
}

@Preview(showBackground = true, heightDp = 1600)
@Composable
private fun MyGamePreview() {
    val form = listOf(12, 0, 34, 79, 52).mapIndexed { i, runs ->
        FormEntry(
            matchId = "m$i", playedAt = "2026-0${5 + i}-1${i}T12:00:00Z", opposition = "Radlett",
            won = i % 2 == 0, batted = i != 1, runs = runs, balls = runs + 4,
        )
    }.reversed()
    FishersTheme {
        SeasonScreen(
            state = SeasonState(
                season = 2026,
                game = PlayerGame(
                    userId = "me", season = 2026, seasons = listOf(2025, 2026),
                    totals = Totals(matches = 5, won = 3, battingInnings = 4, runs = 177, battingAverage = 44.3, strikeRate = 92.1),
                    previous = Totals(matches = 4, battingInnings = 4, runs = 120, battingAverage = 50.0, strikeRate = 80.0),
                    form = Form(matches = form, recentBattingAverage = 44.3, battingTrend = "rising"),
                    highlights = listOf(Highlight("season_best_score", "", "79", "Radlett")),
                    bests = listOf(Best("best_score", "79", "Radlett", "2026-08-13T12:00:00Z", 2026, true)),
                    milestones = listOf(Milestone("first_fifty", "2026-08-13T12:00:00Z", "Radlett", true)),
                ),
            ),
            meId = "me",
            onTab = {}, onSeason = {}, onClub = {}, onClose = {}, onOpenFixtures = {}, onOpenClubs = {},
        )
    }
}
