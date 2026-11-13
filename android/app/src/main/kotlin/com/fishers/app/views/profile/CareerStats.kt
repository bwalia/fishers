package com.fishers.app.views.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fishers.app.R
import com.fishers.app.i18n.t
import com.fishers.app.profile.PlayerSeasonStats
import com.fishers.app.profile.Totals
import com.fishers.app.profile.careerHighlights
import com.fishers.app.profile.figure

/**
 * Every season on record, one discipline at a time — `CareerStatsView.swift`.
 *
 * Career figures are the sum of the seasons, and the averages are worked out
 * from those sums, never averaged from the seasons' own averages.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun CareerStats(seasons: List<PlayerSeasonStats>) {
    var batting by rememberSaveable { mutableStateOf(true) }
    var season by rememberSaveable { mutableStateOf<Int?>(null) }
    val years = seasons.map { it.seasonYear }.distinct().sortedDescending()
    val shown = seasons.filter { season == null || it.seasonYear == season }.sortedByDescending { it.seasonYear }

    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = if (batting) 0 else 1) {
            Tab(selected = batting, onClick = { batting = true }, text = { Text(t("ss.batting")) })
            Tab(selected = !batting, onClick = { batting = false }, text = { Text(t("ss.bowling")) })
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (seasons.isEmpty()) {
                SectionCard(
                    t("rest.no_figures_yet", vars = mapOf("discipline" to if (batting) t("ss.batting") else t("ss.bowling"))),
                ) {
                    Text(
                        t("rest.worked_out_from_matches_on", vars = mapOf("brand" to stringResource(R.string.brand_name))),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                return@Column
            }

            if (years.size > 1) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = season == null, onClick = { season = null }, label = { Text(t("cl.all")) })
                    years.forEach { year ->
                        FilterChip(selected = season == year, onClick = { season = year }, label = { Text("$year") })
                    }
                }
            }

            val totals = Totals(shown)
            SectionCard(if (batting) t("ss.batting") else t("ss.bowling")) {
                FigureGrid(
                    if (batting) {
                        listOf(
                            "${totals.runs}" to t("rest.runs"),
                            "${totals.battingInnings}" to t("cl.innings"),
                            figure(totals.battingAverage) to t("rest.average"),
                            figure(totals.strikeRate) to t("cl.strike_rate"),
                        )
                    } else {
                        listOf(
                            "${totals.wickets}" to t("rest.wickets"),
                            figure(totals.overs, places = 1) to t("cl.overs"),
                            figure(totals.bowlingAverage) to t("rest.average"),
                            figure(totals.economy) to t("cl.economy"),
                        )
                    },
                )
                shown.forEach { SeasonRow(it, batting) }
            }

            SectionCard(t("cl.best_of_it")) {
                careerHighlights(shown, batting).forEach { item ->
                    Row(Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f)) {
                            Text(t(item.labelKey), style = MaterialTheme.typography.bodyMedium)
                            item.season?.let {
                                Text(t("pf.season_year", vars = mapOf("year" to it)), style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        Text(item.value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

/** A season in a line: year, club, matches, then the four numbers for the discipline. */
@Composable
internal fun SeasonRow(row: PlayerSeasonStats, batting: Boolean) {
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row {
            Text("${row.seasonYear}", style = MaterialTheme.typography.titleSmall)
            Text(
                row.clubName?.let { "  $it" }.orEmpty(),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                modifier = Modifier.weight(1f),
            )
            Text(
                t("rest.n_matches", count = row.matches, vars = mapOf("n" to row.matches)),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Row {
            val cells = if (batting) {
                listOf(
                    "${row.runs}" to t("cl.runs"),
                    (row.highScore?.toString() ?: "—") to t("cl.hs"),
                    figure(row.battingAverage) to t("cl.avg"),
                    figure(row.strikeRate) to t("cl.sr"),
                )
            } else {
                listOf(
                    "${row.wickets}" to t("cl.wkts"),
                    figure(row.oversBowled, places = 1) to t("cl.overs"),
                    figure(row.bowlingAverage) to t("cl.avg"),
                    figure(row.economy) to t("sr.econ"),
                )
            }
            cells.forEach { (value, label) ->
                Column(Modifier.weight(1f)) {
                    Text(value, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                    Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}
