package com.fishers.app.views.umpire

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fishers.app.umpire.MatchUmpire
import com.fishers.app.umpire.PendingReviewsState
import com.fishers.app.umpire.RateUmpiresState

/**
 * After the match: say how the umpiring went — `RateUmpiresView.swift`,
 * `RateUmpires.tsx`.
 *
 * Nothing is drawn when no umpire was named. "No umpires to rate" on every
 * match a club scores without naming one is noise.
 */
@Composable
fun RateUmpiresCard(
    state: RateUmpiresState,
    onReview: (umpireId: String, rating: Int, comment: String?) -> Unit,
    onWithdraw: (umpireId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (state.umpires.isEmpty()) return

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("How was the umpiring?", style = MaterialTheme.typography.titleMedium)
            Text(
                "It goes on their profile, with your name on it. One review each — you can change it later.",
                style = MaterialTheme.typography.bodyMedium,
            )
            state.umpires.forEachIndexed { index, umpire ->
                if (index > 0) HorizontalDivider()
                RateOne(
                    umpire = umpire,
                    busy = state.savingFor == umpire.userId,
                    onReview = { rating, comment -> onReview(umpire.userId, rating, comment) },
                    onWithdraw = { onWithdraw(umpire.userId) },
                )
            }
            state.error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun RateOne(
    umpire: MatchUmpire,
    busy: Boolean,
    onReview: (Int, String?) -> Unit,
    onWithdraw: () -> Unit,
) {
    // Keyed on the umpire so a reload that reorders the list does not leave one
    // person's draft sitting under somebody else's name.
    var rating by rememberSaveable(umpire.userId) { mutableIntStateOf(umpire.myRating ?: 0) }
    var comment by rememberSaveable(umpire.userId) { mutableStateOf(umpire.myComment.orEmpty()) }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(umpire.name, fontWeight = FontWeight.SemiBold)
            if (umpire.myRating != null) {
                Text("Your review", style = MaterialTheme.typography.labelMedium)
            }
        }

        StarPicker(rating) { rating = it }

        OutlinedTextField(
            value = comment,
            onValueChange = { comment = it },
            label = { Text("Anything to add?") },
            placeholder = { Text("Gave everything, explained the wides…") },
            minLines = 2,
            enabled = !busy,
            modifier = Modifier.fillMaxWidth(),
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = { onReview(rating, comment.ifBlank { null }) },
                enabled = !busy && rating >= 1,
            ) {
                Text(if (umpire.myRating == null) "Submit" else "Update")
            }
            if (umpire.myRating != null) {
                TextButton(onClick = onWithdraw, enabled = !busy) { Text("Remove") }
            }
        }
    }
}

/**
 * Five taps, each its own 48dp target — this is used at the boundary, on a
 * phone, one-handed.
 */
@Composable
private fun StarPicker(value: Int, onPick: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        for (n in 1..5) {
            IconButton(
                onClick = { onPick(n) },
                modifier = Modifier
                    .size(48.dp)
                    .semantics { contentDescription = "$n out of 5" },
            ) {
                Icon(
                    imageVector = if (n <= value) Icons.Filled.Star else Icons.Outlined.StarBorder,
                    contentDescription = null,
                    tint = if (n <= value) {
                        MaterialTheme.colorScheme.secondary
                    } else {
                        MaterialTheme.colorScheme.outline
                    },
                    modifier = Modifier.size(28.dp),
                )
            }
        }
        Text(
            if (value > 0) "$value / 5" else "Not rated",
            style = MaterialTheme.typography.labelMedium,
            modifier = Modifier.padding(start = 8.dp),
        )
    }
}

/**
 * The matches waiting on this player's say — `PendingUmpireReviewsView.swift`,
 * `PendingUmpireReviews` in `RateUmpires.tsx`.
 *
 * On the profile, where three Sundays in a row can be cleared in one go. It is
 * also the only way to reach a review on Android, which has no match screen in
 * its navigation yet.
 */
@Composable
fun PendingUmpireReviewsCard(
    state: PendingReviewsState,
    onReview: (matchId: String, umpireId: String, rating: Int, comment: String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (state.matches.isEmpty()) return

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Waiting on you", style = MaterialTheme.typography.titleMedium)
            Text(
                "You played in these. Say how the umpiring went — it goes on their profile, with your name on it.",
                style = MaterialTheme.typography.bodyMedium,
            )
            state.matches.forEachIndexed { index, match ->
                if (index > 0) HorizontalDivider()
                Text(match.matchTitle, fontWeight = FontWeight.SemiBold)
                match.umpires.forEach { umpire ->
                    RateOne(
                        umpire = umpire,
                        busy = state.savingFor == umpire.userId,
                        onReview = { rating, comment ->
                            onReview(match.matchId, umpire.userId, rating, comment)
                        },
                        onWithdraw = {},
                    )
                }
            }
            state.error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}
