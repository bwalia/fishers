package com.fishers.app.views.selection

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.fixtures.AvailabilityStatus
import com.fishers.app.fixtures.SelectionBoard
import com.fishers.app.fixtures.SelectionCandidate
import com.fishers.app.fixtures.SelectionState
import com.fishers.app.fixtures.SelectionUiState
import com.fishers.app.fixtures.SelectionViewModel
import com.fishers.app.fixtures.SquadProposal
import com.fishers.app.fixtures.formatWhen
import com.fishers.app.i18n.t
import com.fishers.app.net.FixturesApi
import com.fishers.app.views.fixtures.ErrorText
import com.fishers.app.views.fixtures.Loading
import com.fishers.app.views.fixtures.PushedScreen
import com.fishers.app.views.fixtures.SectionHeading
import com.fishers.app.views.fixtures.availabilityColour
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.Route

/** The captain's selection board for one fixture. `SelectionBoardView.swift`. */
data class SelectionBoardRoute(val eventId: String) : Route {
    @Composable override fun Content() = SelectionBoardScreen(eventId)
}

/**
 * Who is available, what the ranking (or the assistant) would pick and why,
 * and one button to tell the squad. Tap a player to put them in or take them
 * out; once the side is full, a tap makes them a reserve.
 */
@Composable
private fun SelectionBoardScreen(eventId: String) {
    val deps = LocalAppDeps.current
    val model = remember { SelectionViewModel(deps.service<FixturesApi>(), eventId) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { model.load() }

    PushedScreen(
        title = t("ld.selection"),
        bottomBar = {
            if (state.board != null) {
                PublishBar(state, onSave = model::saveDraft, onPublish = model::publish)
            }
        },
    ) { padding ->
        val board = state.board
        if (board == null) {
            if (state.isLoading) Loading(Modifier.padding(padding))
            else Box(Modifier.padding(padding).padding(24.dp)) {
                ErrorText(state.error ?: t("ld.could_not_load_the_selection_board"))
            }
            return@PushedScreen
        }
        LazyColumn(
            Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item { Header(board, state) }
            item {
                Helpers(
                    board = board,
                    thinking = state.isThinking,
                    onSuggest = model::suggest,
                    onAskAssistant = model::askAssistant,
                )
            }
            state.error?.let { item { ErrorText(it) } }
            state.message?.let {
                item { Text(it, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodyMedium) }
            }
            state.proposal?.let { item { ProposalCard(it) } }

            val squad = state.selected.mapNotNull(board::candidate)
            if (squad.isNotEmpty()) {
                item { SectionHeading("${t("sc.squad")} · ${squad.size}/${state.squadSize}", Modifier.padding(top = 8.dp)) }
                items(squad, key = { "in-" + it.userId }) {
                    CandidateRow(it, board.reasons(it.userId), SelectionState.Selected, onTap = { model.toggle(it.userId) })
                }
            }

            val reserves = state.reserves.mapNotNull(board::candidate)
            if (reserves.isNotEmpty()) {
                item { SectionHeading(t("ev.reserves"), Modifier.padding(top = 8.dp)) }
                items(reserves, key = { "res-" + it.userId }) {
                    CandidateRow(it, board.reasons(it.userId), SelectionState.Reserve, onTap = { model.toggle(it.userId) })
                }
                // Somebody dropped out: fill the gap from the reserves, in order, and tell them.
                item {
                    TextButton(onClick = model::promoteReserves, modifier = Modifier.heightIn(min = 48.dp)) {
                        Text(t("ld.move_reserves_up"))
                    }
                }
            }

            item {
                Column(Modifier.padding(top = 8.dp)) {
                    SectionHeading(t("ld.available_best_first"))
                    Text(
                        if (state.isFull) t("ld.side_is_full") + " · " + t("ld.tap_to_pick") else t("ld.tap_to_pick"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            items(state.pool, key = { "pool-" + it.userId }) {
                CandidateRow(it, board.reasons(it.userId), null, onTap = { model.toggle(it.userId) })
            }

            if (state.saidNo.isNotEmpty()) {
                item { SectionHeading(t("rest.said_no"), Modifier.padding(top = 8.dp)) }
                items(state.saidNo, key = { "no-" + it.userId }) {
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(it.name, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                        Text(t("ld.unavailable"), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
    }
}

@Composable
private fun Header(board: SelectionBoard, state: SelectionUiState) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(board.title, style = MaterialTheme.typography.titleLarge)
        Text(formatWhen(board.startsAt), style = MaterialTheme.typography.bodyMedium)
        Text(
            "${state.selected.size}/${state.squadSize} · " +
                t("fix.n_confirmed", vars = mapOf("n" to board.confirmedCount)),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (board.status != "scheduled") {
            Text(
                when (board.status) {
                    "postponed" -> t("ld.postponed")
                    "cancelled" -> t("ld.cancelled")
                    else -> t("ld.finished")
                },
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.error,
            )
        }
        board.statusNote?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
        Text(
            t("ev.reconfirm_and_drop_hours", vars = mapOf("confirm" to board.confirmLeadHours, "drop" to board.dropLeadHours)),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** A side to start from — the ranking always, the assistant when the club allows it. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Helpers(board: SelectionBoard, thinking: Boolean, onSuggest: () -> Unit, onAskAssistant: () -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        AssistChip(
            onClick = onSuggest,
            enabled = !thinking,
            label = { Text(if (thinking) t("ld.thinking") else t("ld.suggest_from_ranking")) },
            leadingIcon = { Icon(Icons.Filled.FormatListNumbered, contentDescription = null) },
            modifier = Modifier.heightIn(min = 48.dp),
        )
        if (board.isAssistantAvailable) {
            AssistChip(
                onClick = onAskAssistant,
                enabled = !thinking,
                label = { Text(t("ld.let_the_assistant_pick")) },
                leadingIcon = { Icon(Icons.Filled.AutoAwesome, contentDescription = null) },
                modifier = Modifier.heightIn(min = 48.dp),
            )
        }
    }
}

@Composable
private fun ProposalCard(proposal: SquadProposal) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                if (proposal.isFromAssistant) t("sc.the_assistants_side") else t("sc.the_rankings_side"),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary,
            )
            proposal.announcement?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
            proposal.concerns?.let {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Filled.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(18.dp))
                    Text(it, style = MaterialTheme.typography.bodySmall)
                }
            }
            if (proposal.published) {
                Text(t("ld.published_to_the_squad"), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            }
        }
    }
}

/** One player: why the ranking rates them, how available they are, and whether they are in. */
@Composable
private fun CandidateRow(
    candidate: SelectionCandidate,
    reasons: List<String>,
    role: SelectionState?,
    onTap: () -> Unit,
) {
    Surface(
        shape = MaterialTheme.shapes.medium,
        color = if (role != null) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceContainerLow,
        modifier = Modifier
            .fillMaxWidth()
            .semantics { selected = role != null }
            .clickable(role = Role.Checkbox, onClick = onTap),
    ) {
        Row(
            Modifier.padding(horizontal = 12.dp, vertical = 10.dp).heightIn(min = 36.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(candidate.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                    if (candidate.isConfirmed) {
                        Icon(
                            Icons.Filled.Verified,
                            contentDescription = t("sel.confirmed"),
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                }
                if (reasons.isNotEmpty()) {
                    Text(
                        reasons.joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            candidate.availability?.let { AvailabilityDot(it) }
            role?.let {
                Text(
                    if (it == SelectionState.Selected) t("ev.playing") else t("ev.reserve"),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                )
            }
        }
    }
}

/** Green, amber or red — and said in words to a screen reader. */
@Composable
private fun AvailabilityDot(status: AvailabilityStatus) {
    Box(
        Modifier
            .size(10.dp)
            .background(availabilityColour(status), CircleShape)
            .semantics { contentDescription = status.label },
    )
}

@Composable
private fun PublishBar(state: SelectionUiState, onSave: () -> Unit, onPublish: () -> Unit) {
    Surface(tonalElevation = 3.dp) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedButton(
                onClick = onSave,
                enabled = !state.isSaving && !state.isPublishing,
                modifier = Modifier.weight(1f).heightIn(min = 48.dp),
            ) { Text(t("ld.save_as_a_draft")) }
            Button(
                onClick = onPublish,
                enabled = state.selected.isNotEmpty() && !state.isPublishing && !state.isSaving,
                modifier = Modifier.weight(1f).heightIn(min = 48.dp),
            ) { Text(if (state.isPublishing) t("ld.announcing") else t("ld.publish_squad")) }
        }
    }
}
