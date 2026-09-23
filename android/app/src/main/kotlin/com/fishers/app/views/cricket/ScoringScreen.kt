package com.fishers.app.views.cricket

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.fishers.app.cricket.Scoreline
import com.fishers.app.cricket.ScoringState
import com.fishers.app.theme.FishersTheme

/**
 * The book — a first cut of `LiveScorerView.swift`.
 *
 * Runs, the four extras and undo. The shot picker, the wagon wheel, the wicket
 * sheet and the rest of what iOS offers are not here yet; what is here goes
 * through the same engine the server scores with, so anything it accepts the
 * server will accept too.
 */
@Composable
fun ScoringScreen(
    state: ScoringState,
    onRuns: (Int) -> Unit,
    onExtra: (String) -> Unit,
    onUndo: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (state.isFirstLoad && state.isLoading) {
        Box(modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        return
    }

    Column(
        modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        state.score?.let { Scoreboard(it, state.match?.oversLimit ?: 0) }
            ?: Text(
                state.error ?: "No match here yet.",
                style = MaterialTheme.typography.bodyMedium,
            )

        state.error?.takeIf { state.score != null }?.let {
            Text(it, color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium)
        }

        if (state.canScore) {
            HorizontalDivider()
            Text("Runs", style = MaterialTheme.typography.labelLarge)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(0, 1, 2, 3, 4, 6).forEach { n ->
                    Button(onClick = { onRuns(n) }, modifier = Modifier.weight(1f)) {
                        Text("$n")
                    }
                }
            }

            Text("Extras", style = MaterialTheme.typography.labelLarge)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("wide" to "Wide", "no_ball" to "No ball",
                    "bye" to "Bye", "leg_bye" to "Leg bye").forEach { (wire, label) ->
                    OutlinedButton(onClick = { onExtra(wire) }, modifier = Modifier.weight(1f)) {
                        Text(label, style = MaterialTheme.typography.labelMedium)
                    }
                }
            }

            TextButton(onClick = onUndo) { Text("Undo the last ball") }
        } else if (state.match?.canScore == false) {
            Text(
                "Somebody else has the book.",
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun Scoreboard(score: Scoreline, oversLimit: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(score.battingName, style = MaterialTheme.typography.titleMedium)
        Text(
            "${score.runs}-${score.wickets}   (${score.overs})",
            style = MaterialTheme.typography.headlineMedium,
        )
        score.margin?.let {
            Text(it, style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary)
        }
        score.chase(oversLimit)?.let {
            Text(it, style = MaterialTheme.typography.bodyLarge)
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun ScoringPreview() {
    FishersTheme {
        ScoringScreen(
            ScoringState(
                isFirstLoad = false,
                match = com.fishers.app.cricket.CricketMatch(
                    id = "m", eventId = "e", status = "live",
                    oversLimit = 20, homeName = "Lords", awayName = "Hemel",
                    canScore = true,
                ),
                score = Scoreline(
                    battingIsHome = false, runs = 142, wickets = 4, legalBalls = 96,
                    complete = false, homeName = "Lords", awayName = "Hemel",
                    target = 176, margin = null, status = "live", lastSeq = 120,
                ),
            ),
            onRuns = {}, onExtra = {}, onUndo = {},
        )
    }
}
