package com.fishers.app.views.match.scoring

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fishers.app.cricket.Commentary
import com.fishers.app.cricket.DlsPar
import com.fishers.app.cricket.InningsView
import com.fishers.app.cricket.MatchView
import com.fishers.app.cricket.rate
import com.fishers.app.i18n.t

/**
 * The card people read after the game, and while it is on: the result or the
 * chase, then each innings — batting, extras and total, fall of wickets,
 * bowling — and the ball-by-ball. `CricketScorecardView.swift`.
 *
 * Shared by the follower's screen and the scorer's "full scorecard", so the
 * two cannot disagree about how a card reads.
 */
@Composable
fun ScorecardContent(
    view: MatchView,
    modifier: Modifier = Modifier,
    dls: DlsPar? = null,
    header: LazyListScope.() -> Unit = {},
) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    Column(modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab) {
            Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text(t("ld.scorecard")) })
            Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text(t("sr.wagon_wheel")) })
            Tab(selected = tab == 2, onClick = { tab = 2 }, text = { Text(t("sc.commentary")) })
        }
        when (tab) {
            0 -> CardTab(view, dls, header)
            1 -> PerInnings(view, header) { inn -> item { WheelChart(view, inn) } }
            else -> PerInnings(view, header) { inn -> ballByBall(view, inn) }
        }
    }
}

@Composable
private fun CardTab(view: MatchView, dls: DlsPar?, header: LazyListScope.() -> Unit) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        header()
        item { Summary(view) }
        if (dls != null && view.current?.index == 1 && !view.isFinished) {
            item {
                Text(
                    t("sc.dls_par_line", vars = mapOf("par" to dls.par, "target" to dls.target)),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (view.innings.isEmpty()) {
            item { Text(t("sc.no_scoring_yet"), color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        // The innings being played first: it is the one anybody opening this wants.
        view.innings.reversed().forEach { inn ->
            item(key = "inn-${inn.index}") { InningsCard(view, inn) }
        }
    }
}

/** Every innings' score on a line, then the result or the chase. */
@Composable
internal fun Summary(view: MatchView) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        view.innings.forEach { inn ->
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    view.sideName(inn.batting),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(inn.score, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text(
                    " (${inn.overs})",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        val result = view.margin
        when {
            result != null -> Text(
                result,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Bold,
            )
            view.chaseLine != null -> Text(
                view.chaseLine!!,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.primary,
            )
            view.innings.isEmpty() -> Text(t("sc.not_started"), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        view.playerOfTheMatch?.let {
            Text(
                t("sc.player_of_the_match_is", vars = mapOf("name" to view.name(it))),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun InningsCard(view: MatchView, inn: InningsView) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    t("sc.team_innings", vars = mapOf("team" to view.sideName(inn.batting))),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f),
                )
                Text("${inn.score} (${inn.overs})", style = MaterialTheme.typography.titleMedium)
            }

            // Batting
            TableHeader(t("sr.batter"), listOf("R" to 34.dp, "B" to 34.dp, t("sh.col_fours") to 30.dp, t("sh.col_sixes") to 30.dp, t("cl.sr") to 48.dp))
            inn.batted.forEach { b ->
                val onStrike = inn.strikerId == b.playerId && !b.out && !inn.complete
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            view.name(b.playerId) + if (onStrike) " *" else "",
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = if (!b.out) FontWeight.SemiBold else FontWeight.Normal,
                        )
                        Text(
                            view.dismissalText(b),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Num("${b.runs}", 34.dp, bold = true)
                    Num("${b.balls}", 34.dp)
                    Num("${b.fours}", 30.dp)
                    Num("${b.sixes}", 30.dp)
                    Num(if (b.balls == 0) "—" else String.format(java.util.Locale.ROOT, "%.1f", b.strikeRate), 48.dp)
                }
            }
            inn.didNotBat.takeIf { it.isNotEmpty() }?.let { rest ->
                Text(
                    t("sc.did_not_bat_names", vars = mapOf("names" to rest.joinToString(", ") { view.name(it.playerId) })),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            HorizontalDivider()
            Row {
                Text(t("la.extras"), modifier = Modifier.weight(1f))
                Text(inn.extrasBreakdown, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(8.dp))
                Text("${inn.extras}", fontWeight = FontWeight.SemiBold)
            }
            Row {
                Text(t("sh.total"), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                Text(inn.score, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(6.dp))
                Text(
                    t("sc.overs_and_run_rate", vars = mapOf("overs" to inn.overs, "rr" to rate(inn.runRate))),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Fall of wickets, and the stand that is still going.
            if (inn.fall.isNotEmpty()) {
                HorizontalDivider()
                SectionLabel(t("rest.fall_of_wickets"))
                inn.fall.forEach { f ->
                    Row {
                        Text("${f.wickets}-${f.score}", fontWeight = FontWeight.Bold, modifier = Modifier.width(56.dp))
                        Text(view.name(f.batterId), modifier = Modifier.weight(1f))
                        Text(
                            "${f.partnershipRuns} (${f.partnershipBalls})  ${f.overBall}",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                if (inn.partnershipBalls > 0 && !inn.complete) {
                    Row {
                        Text(t("sc.unbroken"), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        Text("${inn.partnershipRuns} (${inn.partnershipBalls})", color = MaterialTheme.colorScheme.primary)
                    }
                }
            }

            // Bowling
            HorizontalDivider()
            Text(
                t("sc.team_bowling", vars = mapOf("team" to view.sideName(inn.bowling))),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
            )
            TableHeader(t("sc.bowler"), listOf("O" to 40.dp, "M" to 28.dp, "R" to 34.dp, "W" to 28.dp, t("sr.econ") to 48.dp))
            inn.bowlers.filter { it.balls > 0 || it.runs > 0 }.forEach { bowler ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(view.name(bowler.playerId), style = MaterialTheme.typography.bodyLarge)
                        val extras = listOfNotNull(
                            bowler.wides.takeIf { it > 0 }?.let { "$it wd" },
                            bowler.noBalls.takeIf { it > 0 }?.let { "$it nb" },
                        )
                        if (extras.isNotEmpty()) {
                            Text(
                                extras.joinToString(", "),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    Num(bowler.overs, 40.dp)
                    Num("${bowler.maidens}", 28.dp)
                    Num("${bowler.runs}", 34.dp)
                    Num("${bowler.wickets}", 28.dp, bold = true)
                    Num(if (bowler.balls == 0) "—" else rate(bowler.economy), 48.dp)
                }
            }
        }
    }
}

@Composable
private fun TableHeader(first: String, columns: List<Pair<String, Dp>>) {
    Row {
        Text(
            first.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        columns.forEach { (label, width) ->
            Text(
                label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.End,
                modifier = Modifier.width(width),
            )
        }
    }
}

@Composable
private fun Num(text: String, width: Dp, bold: Boolean = false) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal,
        textAlign = TextAlign.End,
        modifier = Modifier.width(width),
    )
}

/** One innings at a time, the one being played first; the others a tap away. */
@Composable
private fun PerInnings(view: MatchView, header: LazyListScope.() -> Unit, body: LazyListScope.(InningsView) -> Unit) {
    var chosen by rememberSaveable { mutableIntStateOf(-1) }
    val index = if (chosen in view.innings.indices) chosen else view.innings.lastIndex
    val inn = view.innings.getOrNull(index)
    LazyColumn(contentPadding = PaddingValues(16.dp), modifier = Modifier.fillMaxSize()) {
        header()
        if (view.innings.size > 1) {
            item {
                WordChoice(
                    options = view.innings.mapIndexed { i, it -> i to view.sideName(it.batting) },
                    selected = index,
                    onSelect = { chosen = it },
                )
                Spacer(Modifier.height(8.dp))
            }
        }
        if (inn == null) {
            item { Text(t("sc.no_innings_yet"), color = MaterialTheme.colorScheme.onSurfaceVariant) }
        } else {
            body(inn)
        }
    }
}

/** Each ball, newest first. */
private fun LazyListScope.ballByBall(view: MatchView, inn: InningsView) {
    val lines = Commentary.lines(view, inn)
    if (lines.isEmpty()) {
        item { Text(t("sc.nothing_bowled_yet"), color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
    items(lines) { line ->
        Row(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
            Text(
                line.marker,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.width(48.dp),
            )
            Text(
                line.text,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = if (line.isWicket || line.isBoundary) FontWeight.SemiBold else FontWeight.Normal,
                color = if (line.isWicket) BallColours.wicket else MaterialTheme.colorScheme.onSurface,
            )
        }
        HorizontalDivider()
    }
}
