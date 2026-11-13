package com.fishers.app.views.fixtures

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.fixtures.Attendee
import com.fishers.app.fixtures.EventStatus
import com.fishers.app.fixtures.FishersEvent
import com.fishers.app.fixtures.FixtureDetailState
import com.fishers.app.fixtures.FixtureDetailViewModel
import com.fishers.app.fixtures.MatchAction
import com.fishers.app.fixtures.MatchOnFixture
import com.fishers.app.fixtures.RsvpStatus
import com.fishers.app.fixtures.SelectionBoard
import com.fishers.app.fixtures.SelectionCandidate
import com.fishers.app.fixtures.SelectionState
import com.fishers.app.fixtures.formatSpan
import com.fishers.app.i18n.t
import com.fishers.app.motm.MotmPollView
import com.fishers.app.motm.MotmViewModel
import com.fishers.app.net.FixturesApi
import com.fishers.app.views.match.MatchSetupRoute
import com.fishers.app.views.match.ScoreMatchRoute
import com.fishers.app.views.match.ScorecardRoute
import com.fishers.app.views.motm.MotmCard
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator
import com.fishers.app.views.profile.PlayerProfileRoute
import com.fishers.app.views.selection.SelectionBoardRoute
import java.time.Instant

/**
 * One fixture — `EventDetailView.swift`. What it is and when; the match on it;
 * your place in the side; your answer; the captain's tools; who is coming.
 */
@Composable
internal fun FixtureScreen(eventId: String) {
    val deps = LocalAppDeps.current
    val nav = LocalNavigator.current
    val meId = deps.user()?.id
    val model = remember { FixtureDetailViewModel(deps.service<FixturesApi>(), eventId, meId) }
    val state by model.state.collectAsStateWithLifecycle()
    // Again each time the page shows, so coming back from the scorer or the
    // selection board shows what they changed.
    LaunchedEffect(Unit) { model.load() }
    var changingStatus by rememberSaveable { mutableStateOf(false) }

    PushedScreen(
        title = state.event?.title ?: t("ev.event"),
        actions = {
            IconButton(onClick = model::load, enabled = !state.isLoading) {
                Icon(Icons.Filled.Refresh, contentDescription = t("rest.refresh"))
            }
        },
    ) { padding ->
        val event = state.event
        when {
            event == null && state.isLoading -> Loading(Modifier.padding(padding))
            event == null -> Column(Modifier.padding(padding).padding(24.dp)) {
                ErrorText(state.error ?: t("ld.could_not_load_this_fixture"))
            }
            else -> Column(
                Modifier
                    .padding(padding)
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Header(event, state)
                state.error?.let { ErrorText(it) }
                state.message?.let {
                    Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary)
                }

                MatchCard(
                    state = state,
                    onAction = { action ->
                        when (action) {
                            MatchAction.SetUp, MatchAction.ContinueSetup -> nav.push(MatchSetupRoute(eventId))
                            MatchAction.Score -> nav.push(ScoreMatchRoute(eventId))
                            MatchAction.Follow, MatchAction.Scorecard -> nav.push(ScorecardRoute(eventId))
                        }
                    },
                )

                state.myPlace(meId)?.let { me ->
                    state.board?.let { board ->
                        MyPlaceCard(me, board, busy = state.isResponding, onRespond = model::respondToSelection)
                    }
                }

                if (!event.isOff && event.isUpcoming()) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        SectionHeading(t("ev.are_you_playing"))
                        AnswerChips(answer = state.myAnswer, enabled = !state.isAnswering, onAnswer = model::answer)
                    }
                }

                if (state.canSelect) {
                    CaptainTools(
                        event = event,
                        onPickSide = { nav.push(SelectionBoardRoute(eventId)) },
                        onChangeStatus = { changingStatus = true },
                    )
                }

                state.board?.let { SquadCard(it) }

                state.motm?.let { MotmSection(it) }

                if (state.attendees.isNotEmpty()) {
                    WhoIsComing(
                        state.attendees,
                        onOpen = { nav.push(PlayerProfileRoute(it.userId, it.name)) },
                    )
                }
            }
        }
    }

    if (changingStatus) {
        state.event?.let { event ->
            StatusDialog(
                isOff = event.isOff,
                onDismiss = { changingStatus = false },
                onAnnounce = { status, note ->
                    changingStatus = false
                    model.changeStatus(status, note)
                },
            )
        }
    }
}

@Composable
private fun Header(event: FishersEvent, state: FixtureDetailState) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(event.title, style = MaterialTheme.typography.headlineSmall)
        Text(
            t(
                "ev.sport_and_kind",
                vars = mapOf("sport" to event.sport.replaceFirstChar(Char::uppercase), "kind" to event.subtype.label),
            ),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.secondary,
        )
        Labelled(t("ev.when"), formatSpan(event.startAt, event.endAt))
        Labelled(
            t("ev.where"),
            state.venue?.let { listOfNotNull(it.name, it.address).joinToString(", ") } ?: t("ev.not_decided_yet"),
        )
        // Called off has to shout. A cancelled fixture that looks like any
        // other is how a side turns up to an empty ground.
        if (event.isOff) {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Filled.EventBusy, contentDescription = null, tint = MaterialTheme.colorScheme.onErrorContainer)
                    Column {
                        Text(
                            if (event.status == EventStatus.Postponed) t("ld.postponed") else t("rest.called_off"),
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                        )
                        event.statusNote?.let {
                            Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onErrorContainer)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Labelled(label: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}

/**
 * The scorebook. Nothing yet → a scorer sets it up; on → score or follow;
 * done → the card. Each button opens a screen the match area draws.
 */
@Composable
private fun MatchCard(state: FixtureDetailState, onAction: (MatchAction) -> Unit) {
    val event = state.event ?: return
    if (!event.isCricketMatch) return
    val actions = state.matchActions()
    val match = when (val m = state.match) {
        is MatchOnFixture.SettingUp -> m.match
        is MatchOnFixture.Live -> m.match
        is MatchOnFixture.Finished -> m.match
        else -> null
    }
    if (actions.isEmpty() && match == null && state.match != MatchOnFixture.NotStarted) return

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (match != null) {
                Text(
                    listOf(match.homeName, match.awayName).filter { it.isNotBlank() }.joinToString(" v "),
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(
                    t("status.${match.status}"),
                    style = MaterialTheme.typography.labelLarge,
                    color = if (state.match is MatchOnFixture.Live) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            actions.forEachIndexed { i, action ->
                val label = when (action) {
                    MatchAction.SetUp -> t("sr.set_up_the_match")
                    MatchAction.ContinueSetup -> t("fix.carry_on_setting_up")
                    MatchAction.Score -> t("sc.continue_scoring")
                    MatchAction.Follow -> t("fix.follow_the_match")
                    MatchAction.Scorecard -> t("ev.full_scorecard")
                }
                val modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                // The first is the thing to do; any after it is the quieter alternative.
                if (i == 0) Button(onClick = { onAction(action) }, modifier = modifier) { Text(label) }
                else OutlinedButton(onClick = { onAction(action) }, modifier = modifier) { Text(label) }
            }
            if (actions.isEmpty() && state.match == MatchOnFixture.NotStarted) {
                Text(
                    t("ev.who_can_score_this"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * Shown to a player once a side is picked: in, on standby, or not this time —
 * and, for somebody picked, confirm or pull out well before the morning of
 * the game.
 */
@Composable
private fun MyPlaceCard(
    me: SelectionCandidate,
    board: SelectionBoard,
    busy: Boolean,
    onRespond: (Boolean) -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                when (me.state) {
                    SelectionState.Selected -> t("ld.youre_picked")
                    SelectionState.Confirmed -> t("le.you_re_in")
                    SelectionState.Reserve -> t("ld.youre_on_standby")
                    SelectionState.Dropped -> t("ld.your_place_went_to_a_reserve")
                    SelectionState.Declined -> t("ld.you_said_you_cant_make_it")
                    SelectionState.NotSelected -> t("ld.not_selected_this_time")
                    SelectionState.Pool -> t("ld.youre_in_the_mix")
                },
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.primary,
            )
            if (me.state.isInSquad) {
                Text(
                    t("ev.confirm_before_start", vars = mapOf("confirm" to board.confirmLeadHours, "drop" to board.dropLeadHours)),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            when (me.state) {
                // Picked: say yes or no. Only somebody picked is asked — the
                // server would otherwise put a left-out player straight in.
                SelectionState.Selected -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { onRespond(true) }, enabled = !busy, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) {
                        Text(t("ev.im_playing"))
                    }
                    OutlinedButton(onClick = { onRespond(false) }, enabled = !busy, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) {
                        Text(t("ev.cant_make_it"))
                    }
                }
                SelectionState.Confirmed -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Filled.Verified, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Text(t("ev.youre_confirmed"), style = MaterialTheme.typography.bodyMedium)
                    }
                    TextButton(onClick = { onRespond(false) }, enabled = !busy, modifier = Modifier.heightIn(min = 48.dp)) {
                        Text(t("ev.actually_i_cant_make_it"), color = MaterialTheme.colorScheme.error)
                    }
                }
                // On standby: no need to confirm, but say if they cannot come.
                SelectionState.Reserve -> TextButton(onClick = { onRespond(false) }, enabled = !busy, modifier = Modifier.heightIn(min = 48.dp)) {
                    Text(t("ev.cant_make_it"))
                }
                else -> Unit
            }
        }
    }
}

/** For whoever picks the side: pick it, or call the fixture off. */
@Composable
private fun CaptainTools(event: FishersEvent, onPickSide: () -> Unit, onChangeStatus: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (event.hasSelection && !event.isOff && event.isUpcoming(Instant.now())) {
            FilledTonalButton(onClick = onPickSide, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Icon(Icons.Filled.Groups, contentDescription = null)
                Text(t("ev.pick_the_squad"), Modifier.padding(start = 8.dp))
            }
        }
        // A game already played is not called off; one that was can be put back on.
        if (event.isOff || event.isUpcoming(Instant.now())) {
            OutlinedButton(onClick = onChangeStatus, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Text(if (event.isOff) t("ev.put_it_back_on") else t("ld.delay_or_call_off"))
            }
        }
    }
}

/** The side as published — everybody in the club can see who is playing. */
@Composable
private fun SquadCard(board: SelectionBoard) {
    val squad = board.candidates.filter { it.state.isInSquad }
    val reserves = board.candidates.filter { it.state == SelectionState.Reserve }
    if (squad.isEmpty() && reserves.isEmpty()) return
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            SectionHeading("${t("sc.squad")} · ${squad.size}/${board.requirements.size}")
            squad.forEach { player ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(player.name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                    if (player.isConfirmed || player.state == SelectionState.Confirmed) {
                        Icon(
                            Icons.Filled.Verified,
                            contentDescription = t("sel.confirmed"),
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }
            if (reserves.isNotEmpty()) {
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
                Text(t("ev.reserves"), style = MaterialTheme.typography.labelLarge)
                reserves.forEach { Text(it.name, style = MaterialTheme.typography.bodyMedium) }
            }
        }
    }
}

@Composable
private fun MotmSection(poll: MotmPollView) {
    val deps = LocalAppDeps.current
    val model = remember(poll.id) { MotmViewModel(deps.api, poll.id) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(poll.id) { model.load() }
    MotmCard(state = state, onVote = model::vote)
}

/** Everyone asked, available first, with the counts a captain reads before anything else. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WhoIsComing(attendees: List<Attendee>, onOpen: (Attendee) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHeading(t("ev.who_is_coming"))
        val n = { status: RsvpStatus -> attendees.count { it.status == status } }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(t("ev.n_playing", vars = mapOf("n" to n(RsvpStatus.Going))), style = MaterialTheme.typography.labelLarge)
            Text(t("ev.n_maybe", vars = mapOf("n" to n(RsvpStatus.Maybe))), style = MaterialTheme.typography.labelLarge)
            Text(t("ev.n_not_answered", vars = mapOf("n" to n(RsvpStatus.Invited))), style = MaterialTheme.typography.labelLarge)
        }
        // Two clubs asked about one fixture are two squads, not one heap of names.
        val sides = attendees.groupBy { it.clubName }
        Card(Modifier.fillMaxWidth()) {
            sides.entries.forEachIndexed { s, (club, people) ->
                if (sides.size > 1 && club != null) {
                    Text(
                        club,
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 16.dp, top = if (s == 0) 12.dp else 16.dp),
                    )
                }
                people.forEachIndexed { i, person ->
                    if (i > 0) HorizontalDivider()
                    ListItem(
                        headlineContent = { Text(person.name) },
                        supportingContent = person.availability?.let {
                            { Text(t("ev.calendar_says", vars = mapOf("what" to it.label.lowercase()))) }
                        },
                        trailingContent = {
                            Text(
                                person.status.label,
                                style = MaterialTheme.typography.labelLarge,
                                color = when (person.status) {
                                    RsvpStatus.Going -> MaterialTheme.colorScheme.primary
                                    RsvpStatus.NotGoing -> MaterialTheme.colorScheme.error
                                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                                },
                            )
                        },
                        modifier = Modifier.clickable(role = Role.Button) { onOpen(person) },
                    )
                }
            }
        }
    }
}

/**
 * Postpone it, call it off, or put it back on — with the reason, because
 * everybody who was asked is told and "why" is the first thing they will ask.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StatusDialog(isOff: Boolean, onDismiss: () -> Unit, onAnnounce: (EventStatus, String?) -> Unit) {
    val choices = if (isOff) listOf(EventStatus.Scheduled) else listOf(EventStatus.Postponed, EventStatus.Cancelled)
    var choice by rememberSaveable { mutableStateOf(choices.first()) }
    var note by rememberSaveable { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (isOff) t("ev.put_it_back_on") else t("ld.delay_or_call_off")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (choices.size > 1) {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        choices.forEach {
                            FilterChip(
                                selected = choice == it,
                                onClick = { choice = it },
                                label = { Text(if (it == EventStatus.Postponed) t("ev.postpone") else t("ev.cancel_it")) },
                                modifier = Modifier.heightIn(min = 48.dp),
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text(t("sc.reason")) },
                    placeholder = { Text(t("ld.ground_unplayable_example")) },
                    minLines = 2,
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    t("ld.posted_to_club_thread"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = { TextButton(onClick = { onAnnounce(choice, note) }) { Text(t("ld.announce")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(t("sc.cancel")) } },
    )
}
