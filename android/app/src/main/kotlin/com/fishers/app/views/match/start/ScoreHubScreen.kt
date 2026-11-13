package com.fishers.app.views.match.start

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.AssistChip
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fishers.app.fixtures.formatWhen
import com.fishers.app.i18n.t
import com.fishers.app.match.start.FixtureRow
import com.fishers.app.match.start.HubFilter
import com.fishers.app.match.start.PhoneMatch
import com.fishers.app.match.start.ScoreHubState

/** `ScoreHubPane`: start a match, pick up one under way, read one that is finished. */
@Composable
fun ScoreHubScreen(
    state: ScoreHubState,
    onBack: () -> Unit,
    onStartMatch: () -> Unit,
    onFilter: (HubFilter) -> Unit,
    onSearch: (String) -> Unit,
    onNewestFirst: (Boolean) -> Unit,
    onRefresh: () -> Unit,
    onLoadMore: () -> Unit,
    onOpen: (FixtureRow) -> Unit,
    onOpenPhone: (PhoneMatch) -> Unit,
) {
    StartPage(
        title = t("cl.matches"),
        onBack = onBack,
        scroll = false,
        actions = {
            IconButton(onClick = onRefresh) { Icon(Icons.Filled.Refresh, contentDescription = t("rest.refresh")) }
        },
    ) {
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(t("sr.two_sides_right_now"), style = MaterialTheme.typography.titleMedium)
                        Footnote(t("sc.no_fixture_needed"))
                        Button(
                            onClick = onStartMatch,
                            modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
                        ) {
                            Icon(Icons.Filled.Add, contentDescription = null)
                            Text(t("sr.start_a_match_now"), style = MaterialTheme.typography.titleMedium,
                                modifier = Modifier.padding(start = 8.dp))
                        }
                    }
                }
            }
            if (state.onThisPhone.isNotEmpty()) {
                item { OnThisPhone(state.onThisPhone, onOpenPhone) }
            }
            item {
                OutlinedTextField(
                    value = state.search,
                    onValueChange = onSearch,
                    placeholder = { Text(t("sr.search_fixtures_or_teams")) },
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            item { Choices(HubFilter.entries, state.filter, { it.label }, onFilter) }
            item {
                // One chip that says the order and flips it: two chips beside
                // the count did not fit a 360dp phone and stacked in a corner.
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Box(Modifier.weight(1f)) {
                        if (state.total > 0) {
                            Footnote(
                                t("cl.showing_range_of_total", vars = mapOf(
                                    "from" to 1, "to" to state.rows.size, "total" to state.total,
                                )),
                            )
                        }
                    }
                    AssistChip(
                        onClick = { onNewestFirst(!state.newestFirst) },
                        label = {
                            Text(
                                if (state.newestFirst) t("ld.newest_first") else t("ld.soonest_first"),
                                maxLines = 1,
                            )
                        },
                        leadingIcon = { Icon(Icons.Filled.SwapVert, contentDescription = null, Modifier.size(18.dp)) },
                        modifier = Modifier.heightIn(min = 48.dp),
                    )
                }
            }
            state.error?.let { item { ErrorLine(it) } }
            if (state.isFirstLoad && state.isLoading) {
                item { Box(Modifier.fillMaxWidth().padding(32.dp), Alignment.Center) { CircularProgressIndicator() } }
            } else if (state.rows.isEmpty() && state.error == null) {
                item {
                    Footnote(
                        if (state.search.isBlank() && state.filter == HubFilter.All) t("ev.no_cricket_fixtures_yet")
                        else t("ev.nothing_matches_that"),
                    )
                }
            }
            items(state.rows, key = { it.eventId }) { row ->
                FixtureRowView(row, onClick = { onOpen(row) })
                HorizontalDivider()
            }
            if (state.hasMore) {
                item {
                    LaunchedEffect(state.rows.size) { onLoadMore() }
                    Box(Modifier.fillMaxWidth().padding(16.dp), Alignment.Center) { CircularProgressIndicator() }
                }
            }
        }
    }
}

/** A fixture, and how far its match has got — `ScoreFixtureRow`. */
@Composable
private fun FixtureRowView(row: FixtureRow, onClick: () -> Unit) {
    val (label, tint) = when (row.stage) {
        FixtureRow.Stage.Live -> t("status.live") to MaterialTheme.colorScheme.error
        FixtureRow.Stage.Finished -> t("sc.finished") to MaterialTheme.colorScheme.primary
        FixtureRow.Stage.NotStarted -> t("sc.not_started") to MaterialTheme.colorScheme.onSurfaceVariant
        FixtureRow.Stage.SettingUp -> t("status.${row.matchStatus}") to MaterialTheme.colorScheme.tertiary
    }
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(onClick = onClick)
            .semantics(mergeDescendants = true) {}
            .padding(vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(row.sides, style = MaterialTheme.typography.titleMedium, maxLines = 2)
        Footnote(formatWhen(row.startAt))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Pill(label, tint)
            row.score?.takeIf { it.isNotBlank() }?.let {
                Pill(it, MaterialTheme.colorScheme.onSurface)
            }
            if (row.hasScorer && row.stage == FixtureRow.Stage.Live) Footnote(t("sr.being_scored"))
        }
        row.result?.takeIf { it.isNotBlank() }?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary)
        }
    }
}

@Composable
private fun Pill(text: String, tint: Color) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = tint,
        modifier = Modifier
            .background(tint.copy(alpha = 0.12f), RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 3.dp),
    )
}
