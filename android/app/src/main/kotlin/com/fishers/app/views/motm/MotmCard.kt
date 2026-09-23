package com.fishers.app.views.motm

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.fishers.app.motm.MotmCandidate
import com.fishers.app.motm.MotmPollView
import com.fishers.app.motm.MotmState
import com.fishers.app.theme.FishersTheme

/**
 * The man-of-the-match vote, as it appears in a thread —
 * `ManOfTheMatchCard.swift`.
 *
 * The tally is hidden until you have voted. That is the server's rule and the
 * card repeats it in words rather than drawing a row of zeroes, because a row
 * of zeroes reads as "nobody has voted" when it means "you have not".
 */
@Composable
fun MotmCard(
    state: MotmState,
    onVote: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val poll = state.poll
    Card(modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            when {
                poll == null && state.isLoading -> CircularProgressIndicator(Modifier.padding(8.dp))
                poll == null -> Text(state.error ?: "No vote here.")
                else -> {
                    Text(poll.title, style = MaterialTheme.typography.titleMedium)
                    poll.result?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium)
                    }

                    val open = poll.isOpen()
                    Text(
                        when {
                            !open -> "Voting has closed."
                            poll.tallyVisible -> "${poll.totalVotes} voted."
                            else -> "Votes are hidden until you have cast yours."
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    )

                    HorizontalDivider()

                    listOf("Home" to poll.home, "Away" to poll.away).forEach { (label, side) ->
                        if (side.isNotEmpty()) {
                            Text(
                                label,
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.primary,
                            )
                            side.forEach { candidate ->
                                CandidateRow(
                                    candidate = candidate,
                                    selected = poll.myVote == candidate.userId,
                                    // The scorer's award is a different thing
                                    // from the players' vote and must never
                                    // look like one.
                                    scorersPick = poll.scorerAwardUserId == candidate.userId,
                                    showVotes = poll.tallyVisible,
                                    enabled = poll.votingAllowed() && !state.isVoting,
                                    onClick = { onVote(candidate.userId) },
                                )
                            }
                        }
                    }

                    state.error?.let {
                        Text(it, color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
}

@Composable
private fun CandidateRow(
    candidate: MotmCandidate,
    selected: Boolean,
    scorersPick: Boolean,
    showVotes: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .selectable(selected = selected, enabled = enabled, onClick = onClick,
                role = Role.RadioButton)
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        RadioButton(selected = selected, onClick = null, enabled = enabled)
        Column(Modifier.weight(1f)) {
            Text(
                candidate.displayName,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
            )
            if (scorersPick) {
                Text(
                    "The scorer's award",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.secondary,
                )
            }
        }
        if (showVotes) {
            Text("${candidate.votes}", style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun MotmPreview() {
    FishersTheme {
        MotmCard(
            MotmState(
                poll = MotmPollView(
                    id = "p", eventId = "e", title = "Man of the match",
                    result = "Lords won by 7 wickets",
                    status = "open", closesAt = "2099-01-01T00:00:00Z",
                    candidates = listOf(
                        MotmCandidate("1", "Ravi Patel", "home", 3),
                        MotmCandidate("2", "Tom Hardy", "away", 1),
                    ),
                    canVote = true, tallyVisible = false, totalVotes = 4,
                    scorerAwardUserId = "1",
                ),
            ),
            onVote = {},
        )
    }
}
