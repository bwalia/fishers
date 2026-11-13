package com.fishers.app.views.fixtures

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.EventRepeat
import androidx.compose.material.icons.filled.SportsCricket
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.fishers.app.fixtures.EventStatus
import com.fishers.app.fixtures.EventSubtype
import com.fishers.app.fixtures.FixturesState
import com.fishers.app.fixtures.MyFixture
import com.fishers.app.fixtures.RsvpStatus
import com.fishers.app.fixtures.formatWhen
import com.fishers.app.i18n.t
import com.fishers.app.theme.FishersTheme

/**
 * What is coming, and what has been — `FixturesView.swift`.
 *
 * Answering is the point of the screen, so the three answers are on the card
 * rather than behind a tap into it. A captain picking a side is reading this
 * list on a phone, and every extra tap is a player who never answered.
 */
@Composable
fun FixturesScreen(
    state: FixturesState,
    onAnswer: (String, RsvpStatus) -> Unit,
    onOpen: (MyFixture) -> Unit = {},
    onSchedule: () -> Unit = {},
    onScheduleNets: () -> Unit = {},
    onOpenCalendar: () -> Unit = {},
    onOpenScores: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Header(
                canSchedule = state.canSchedule,
                onSchedule = onSchedule,
                onScheduleNets = onScheduleNets,
                onOpenCalendar = onOpenCalendar,
                onOpenScores = onOpenScores,
            )
        }
        when {
            state.isFirstLoad && state.isLoading -> item { Loading(Modifier.padding(top = 48.dp)) }

            state.upcoming.isEmpty() && state.played.isEmpty() -> item {
                EmptyDiary(error = state.error, canSchedule = state.canSchedule, onSchedule = onSchedule)
            }

            else -> {
                state.error?.let { item { ErrorText(it) } }
                if (state.upcoming.isNotEmpty()) {
                    item { SectionHeading(t("rest.coming_up")) }
                    items(state.upcoming, key = { it.id }) {
                        FixtureCard(
                            it,
                            answering = state.answering == it.id,
                            onAnswer = onAnswer,
                            onOpen = onOpen,
                        )
                    }
                }
                if (state.played.isNotEmpty()) {
                    item { SectionHeading(t("cl.played")) }
                    items(state.played, key = { it.id }) {
                        FixtureCard(it, answering = false, onAnswer = onAnswer, onOpen = onOpen, past = true)
                    }
                }
            }
        }
    }
}

@Composable
private fun Header(
    canSchedule: Boolean,
    onSchedule: () -> Unit,
    onScheduleNets: () -> Unit,
    onOpenCalendar: () -> Unit,
    onOpenScores: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                t("ev.fixtures"),
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            IconButton(onClick = onOpenCalendar) {
                Icon(Icons.Filled.CalendarMonth, contentDescription = t("ev.your_calendar"))
            }
            IconButton(onClick = onOpenScores) {
                Icon(Icons.Filled.SportsCricket, contentDescription = t("nav.scores"))
            }
        }
        // Only somebody who can put a match in a club's diary is offered it.
        if (canSchedule) {
            FilledTonalButton(onClick = onSchedule, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Text(t("ev.schedule_a_match"), Modifier.padding(start = 8.dp))
            }
            OutlinedButton(onClick = onScheduleNets, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Icon(Icons.Filled.EventRepeat, contentDescription = null)
                Text(t("np.schedule_nets_or_practice"), Modifier.padding(start = 8.dp))
            }
        }
    }
}

@Composable
private fun EmptyDiary(error: String?, canSchedule: Boolean, onSchedule: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 32.dp, horizontal = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            error ?: if (canSchedule) t("ld.nothing_in_the_diary_yet_schedule_a_ma")
            else t("ld.nothing_in_the_diary_yet_when_your_clu"),
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = if (error != null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
        )
        if (canSchedule) {
            Button(onClick = onSchedule, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(t("ev.schedule_a_match"))
            }
        }
    }
}

@Composable
private fun FixtureCard(
    event: MyFixture,
    answering: Boolean,
    onAnswer: (String, RsvpStatus) -> Unit,
    onOpen: (MyFixture) -> Unit,
    past: Boolean = false,
) {
    // The card is the way into the fixture: who is playing, the side, and the
    // match on the day.
    Card(Modifier.fillMaxWidth().clickable(role = Role.Button) { onOpen(event) }) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    event.title,
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                AssistChip(onClick = { onOpen(event) }, label = { Text(event.subtype.label) })
            }

            Text(
                listOfNotNull(formatWhen(event.startAt), event.venueName, event.clubName).joinToString(" · "),
                style = MaterialTheme.typography.bodyMedium,
            )

            // Nets and training: which week of a series, and what to bring.
            event.practice?.let { practice ->
                practice.weekOf?.let { Text(it, style = MaterialTheme.typography.labelLarge) }
                practice.note?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            // Called off has to shout. A cancelled fixture that looks like any
            // other is how a side turns up to an empty ground.
            if (event.isOff) {
                Text(
                    if (event.status == EventStatus.Postponed) t("ld.postponed") else t("rest.called_off"),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            if (!past && !event.isOff) {
                AnswerChips(
                    answer = event.myRsvp,
                    enabled = !answering,
                    onAnswer = { onAnswer(event.id, it) },
                )
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun FixturesPreview() {
    FishersTheme {
        FixturesScreen(
            FixturesState(
                isFirstLoad = false,
                canSchedule = true,
                upcoming = listOf(
                    MyFixture(
                        id = "1", clubId = "c", title = "Lords CC v Hemel",
                        subtype = EventSubtype.LeagueMatch,
                        startAt = "2026-09-27T13:30:00Z", myRsvp = RsvpStatus.Going,
                    ),
                    MyFixture(
                        id = "2", clubId = "c", title = "Thursday nets",
                        subtype = EventSubtype.Nets,
                        startAt = "2026-09-25T18:00:00Z",
                        status = EventStatus.Cancelled,
                    ),
                ),
            ),
            onAnswer = { _, _ -> },
        )
    }
}
