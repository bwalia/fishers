package com.fishers.app.views.scores

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fishers.app.scores.BattingRow
import com.fishers.app.scores.BowlingRow
import com.fishers.app.scores.CurrentPlayer
import com.fishers.app.scores.Innings
import com.fishers.app.scores.WorldMatchState
import com.fishers.app.scores.sideScore
import com.fishers.app.scores.tabLabel
import com.fishers.app.scores.title

/**
 * One match in full — the scorecard.
 *
 * Innings are tabs rather than a stack: a Test has four of them, and scrolling
 * past a hundred batting rows to reach the one you wanted is hunting rather
 * than reading.
 */
@Composable
fun WorldMatchScreen(
    state: WorldMatchState,
    onOpenTab: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val view = state.view

    if (state.isFirstLoad && view == null) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }
    if (view == null) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                state.error ?: "Could not load that match.",
                color = MaterialTheme.colorScheme.error,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(24.dp),
            )
        }
        return
    }

    val innings = view.detail?.innings.orEmpty()
    val open = state.tab?.let { innings.getOrNull(it) }

    LazyColumn(
        modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { MatchHeader(view.summary, innings) }

        view.detail?.venue?.let { venue ->
            item {
                Text(
                    venue,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        val batting = view.detail?.battingNow.orEmpty()
        val bowling = view.detail?.bowlingNow.orEmpty()
        if (batting.isNotEmpty() || bowling.isNotEmpty()) {
            item { Crease(batting, bowling) }
        }

        if (innings.size > 1) {
            item { InningsTabs(innings, state.tab ?: 0, onOpenTab) }
        }

        if (open != null) {
            item { InningsCard(open, innings.title(state.tab ?: 0)) }
        } else if (view.detail == null) {
            item {
                Empty(
                    "No scorecard for this match yet.",
                    "If it has not started, there is nothing to show.",
                )
            }
        } else {
            item {
                Empty(
                    "Not a ball bowled yet.",
                    "The card will fill in once the match is under way.",
                )
            }
        }

        item {
            Text(
                buildString {
                    append("Scorecard updated ${view.freshness()}.")
                    append(
                        if (view.summary.phase == "done") {
                            " This match has finished, so this is the final card."
                        } else {
                            " It comes from a free feed and runs a few minutes behind play."
                        },
                    )
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun Empty(title: String, note: String) {
    Column {
        Text(title, style = MaterialTheme.typography.titleSmall)
        Text(
            note,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * The match itself. Scores read off the card when there is one: the summary and
 * the card are fetched separately and can be a quarter of an hour apart, and
 * two different numbers for the same thing on one screen reads as a bug.
 */
@Composable
private fun MatchHeader(summary: com.fishers.app.scores.WorldMatch, innings: List<Innings>) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            summary.leagueName,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Side(
            summary.homeTeamName,
            innings.sideScore(summary.homeTeamName) ?: summary.homeScore,
            summary.homeInfo,
            summary.homeBatting,
        )
        Side(
            summary.awayTeamName,
            innings.sideScore(summary.awayTeamName) ?: summary.awayScore,
            summary.awayInfo,
            summary.awayBatting,
        )
        summary.report?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(
            summary.state.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = if (summary.isLive) {
                MaterialTheme.colorScheme.error
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
    }
}

@Composable
private fun Side(name: String, score: String?, info: String?, batting: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            name,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (batting) FontWeight.Bold else FontWeight.Normal,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        Column(horizontalAlignment = Alignment.End) {
            Text(score ?: "—", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            info?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * Grouped under two headings rather than a label on every row: repeated four
 * times the label is four wasted lines on a phone.
 */
@Composable
private fun Crease(batting: List<CurrentPlayer>, bowling: List<CurrentPlayer>) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text("At the crease", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
        Text(
            "Who is in, and who is bowling at them, right now.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (batting.isNotEmpty()) {
            SubHead("Batting")
            batting.forEach { CreaseRow(it) }
        }
        if (bowling.isNotEmpty()) {
            SubHead("Bowling")
            bowling.forEach { CreaseRow(it) }
        }
    }
}

@Composable
private fun SubHead(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.Bold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 6.dp),
    )
}

@Composable
private fun CreaseRow(player: CurrentPlayer) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            player.name,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        Text(player.line, style = MaterialTheme.typography.bodyMedium)
    }
}

/** A chip per innings, with its score, scrolling sideways when four will not fit. */
@Composable
private fun InningsTabs(innings: List<Innings>, open: Int, onOpen: (Int) -> Unit) {
    Row(
        Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        innings.forEachIndexed { i, inn ->
            val selected = i == open
            Column(
                Modifier
                    .clip(RoundedCornerShape(22.dp))
                    .background(
                        if (selected) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.surfaceVariant
                        },
                    )
                    // 44dp is the tap target whatever the chip looks like.
                    .heightIn(min = 44.dp)
                    .selectable(selected = selected, role = Role.Tab) { onOpen(i) }
                    .padding(horizontal = 14.dp, vertical = 6.dp),
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    innings.tabLabel(i),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (selected) {
                        MaterialTheme.colorScheme.onPrimary
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                )
                Text(
                    inn.score ?: "—",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (selected) {
                        MaterialTheme.colorScheme.onPrimary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
        }
    }
}

@Composable
private fun InningsCard(innings: Innings, title: String) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.weight(1f),
            )
            innings.score?.let {
                Text(it, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            }
        }

        SubHead("Batting")
        BatHead()
        innings.batting.forEach { BatRow(it) }

        innings.extras.total?.let { total ->
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Row {
                Text("Extras", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                innings.extras.breakdown?.let {
                    Text(
                        " ($it)",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                } ?: Box(Modifier.weight(1f))
                Text("$total", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            }
        }

        if (innings.bowling.isNotEmpty()) {
            SubHead("Bowling")
            innings.bowling.forEach { BowlRow(it) }
        }

        if (innings.fallOfWickets.isNotEmpty()) {
            SubHead("Fall of wickets")
            Text(
                innings.fallOfWickets.joinToString("  ·  ") { f ->
                    "${f.wicket}–${f.runs ?: "—"} ${f.batter.orEmpty()}".trim()
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun BatHead() {
    Row {
        Text(
            "BATTER",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        listOf("R", "B", "SR").forEach {
            Text(
                it,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.End,
                modifier = Modifier.width(if (it == "SR") 46.dp else 34.dp),
            )
        }
    }
}

@Composable
private fun BatRow(row: BattingRow) {
    Row(Modifier.padding(vertical = 3.dp)) {
        Column(Modifier.weight(1f)) {
            Text(
                row.name,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = if (row.notOut) FontWeight.Bold else FontWeight.Normal,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            // The reason a scorecard is readable: a sentence, not a code.
            Text(
                row.howOut,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Cell(row.runs?.toString() ?: "—", 34.dp, bold = true)
        Cell(row.balls?.toString() ?: "—", 34.dp)
        Cell(row.strikeRate?.let { "%.1f".format(it) } ?: "—", 46.dp)
    }
}

@Composable
private fun BowlRow(row: BowlingRow) {
    Row(Modifier.padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(
            row.name,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        // O–M–R–W, the way figures are read out.
        val overs = row.overs?.let { if (it == Math.floor(it)) it.toInt().toString() else it.toString() } ?: "—"
        Text(
            "$overs–${row.maidens ?: "—"}–${row.runs ?: "—"}–${row.wickets ?: "—"}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun Cell(text: String, width: androidx.compose.ui.unit.Dp, bold: Boolean = false) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal,
        textAlign = TextAlign.End,
        modifier = Modifier.width(width),
    )
}
