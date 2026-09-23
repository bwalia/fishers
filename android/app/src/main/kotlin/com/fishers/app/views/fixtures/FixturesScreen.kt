package com.fishers.app.views.fixtures

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.fishers.app.fixtures.FishersEvent
import com.fishers.app.fixtures.FixturesState
import com.fishers.app.fixtures.RsvpStatus
import com.fishers.app.fixtures.formatWhen
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
    modifier: Modifier = Modifier,
) {
    when {
        state.isFirstLoad && state.isLoading ->
            Box(modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }

        state.upcoming.isEmpty() && state.past.isEmpty() -> Box(
            modifier.fillMaxSize().padding(32.dp),
            Alignment.Center,
        ) {
            Text(
                state.error ?: "Nothing in the diary yet.",
                style = MaterialTheme.typography.bodyMedium,
            )
        }

        else -> LazyColumn(
            modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            state.error?.let {
                item {
                    Text(it, color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall)
                }
            }
            if (state.upcoming.isNotEmpty()) {
                item { SectionHeading("Coming up") }
                items(state.upcoming, key = { it.id }) {
                    FixtureCard(it, answering = state.answering == it.id, onAnswer = onAnswer)
                }
            }
            if (state.past.isNotEmpty()) {
                item { SectionHeading("Played") }
                items(state.past, key = { it.id }) {
                    FixtureCard(it, answering = false, onAnswer = onAnswer, past = true)
                }
            }
        }
    }
}

@Composable
private fun SectionHeading(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
    )
}

@Composable
private fun FixtureCard(
    event: FishersEvent,
    answering: Boolean,
    onAnswer: (String, RsvpStatus) -> Unit,
    past: Boolean = false,
) {
    Card(Modifier.fillMaxWidth()) {
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
                AssistChip(onClick = {}, label = { Text(event.subtype.label) })
            }

            Text(formatWhen(event.startAt), style = MaterialTheme.typography.bodyMedium)

            // Called off has to shout. A cancelled fixture that looks like any
            // other is how a side turns up to an empty ground.
            if (event.isOff) {
                Text(
                    buildString {
                        append(if (event.status.name == "Postponed") "Postponed" else "Called off")
                        event.statusNote?.let { append(" — "); append(it) }
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            if (!past && !event.isOff) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(RsvpStatus.Going, RsvpStatus.Maybe, RsvpStatus.NotGoing).forEach {
                        FilterChip(
                            selected = event.myRsvp == it,
                            onClick = { onAnswer(event.id, it) },
                            enabled = !answering,
                            label = { Text(it.label) },
                        )
                    }
                }
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
                upcoming = listOf(
                    FishersEvent(
                        id = "1", clubId = "c", title = "Lords CC v Hemel",
                        subtype = com.fishers.app.fixtures.EventSubtype.LeagueMatch,
                        startAt = "2026-09-27T13:30:00Z", myRsvp = RsvpStatus.Going,
                    ),
                    FishersEvent(
                        id = "2", clubId = "c", title = "Thursday nets",
                        subtype = com.fishers.app.fixtures.EventSubtype.Nets,
                        startAt = "2026-09-25T18:00:00Z",
                        status = com.fishers.app.fixtures.EventStatus.Cancelled,
                        statusNote = "ground unplayable",
                    ),
                ),
            ),
            onAnswer = { _, _ -> },
        )
    }
}
