package com.fishers.app.views.umpire

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fishers.app.umpire.UmpireProfile
import com.fishers.app.umpire.UmpiringState

/**
 * Somebody's umpiring record — `UmpiringView.swift`, `Umpiring.tsx`.
 *
 * Club cricket umpires itself, and the person who does it every week has had
 * nothing to show for it. Figures first, because "eleven matches" is the fact
 * somebody came for; then how the ratings fall, because a 4.0 from ten fours
 * is a different umpire from a 4.0 from five fives and five threes.
 */
@Composable
fun UmpiringCard(
    state: UmpiringState,
    isMine: Boolean,
    onWilling: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    theirName: String? = null,
) {
    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Umpiring", style = MaterialTheme.typography.titleMedium)

            when {
                state.isLoading && state.profile == null ->
                    CircularProgressIndicator(Modifier.size(24.dp))

                state.error != null && state.profile == null ->
                    Text(state.error, color = MaterialTheme.colorScheme.error)

                state.profile != null -> Body(state.profile, isMine, state.isSaving, onWilling, theirName)
            }
        }
    }
}

@Composable
private fun Body(
    profile: UmpireProfile,
    isMine: Boolean,
    isSaving: Boolean,
    onWilling: (Boolean) -> Unit,
    theirName: String?,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Figure(
            profile.matches.toString(),
            if (profile.matches == 1) "match umpired" else "matches umpired",
        )
        Figure(
            profile.ratingAverage?.let { "%.1f".format(it) } ?: "—",
            profile.ratingLine,
        )
    }

    if (isMine) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("I umpire", style = MaterialTheme.typography.bodyLarge)
            Switch(
                checked = profile.umpires,
                onCheckedChange = onWilling,
                enabled = !isSaving,
            )
        }
    } else if (profile.umpires) {
        Text("Will stand", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelLarge)
    }

    profile.note?.let {
        Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
    }

    if (profile.ratingCount > 0) {
        HorizontalDivider()
        for (n in 5 downTo 1) {
            val count = profile.ratingBreakdown.getOrElse(n - 1) { 0L }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clearAndSetSemantics {
                        contentDescription = "$n stars, $count of ${profile.ratingCount}"
                    },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("$n", style = MaterialTheme.typography.labelMedium)
                LinearProgressIndicator(
                    progress = { count.toFloat() / profile.ratingCount.coerceAtLeast(1) },
                    modifier = Modifier.weight(1f),
                )
                Text("$count", style = MaterialTheme.typography.labelMedium, modifier = Modifier.width(28.dp))
            }
        }
    }

    if (profile.reviews.isNotEmpty()) {
        HorizontalDivider()
        profile.reviews.forEach { review ->
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    StarRow(review.rating)
                    Text(review.reviewerName, style = MaterialTheme.typography.labelMedium)
                }
                review.comment?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                Text(review.matchTitle, style = MaterialTheme.typography.labelSmall)
            }
        }
    } else if (profile.matches == 0) {
        Text(
            if (isMine) {
                "You have not umpired a match here yet. Ask your captain to name you as umpire and it starts counting."
            } else {
                "${theirName ?: "They"} have not umpired a match here yet."
            },
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}

@Composable
private fun Figure(value: String, label: String) {
    Column {
        Text(value, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Text(label, style = MaterialTheme.typography.labelMedium)
    }
}

/**
 * One to five, drawn. Never the only signal — the label carries the number,
 * because five shapes in a row is hard to count at a glance and impossible to
 * hear.
 */
@Composable
fun StarRow(value: Int, size: Int = 16) {
    Row(
        modifier = Modifier.clearAndSetSemantics { contentDescription = "$value out of 5" },
    ) {
        for (n in 1..5) {
            Icon(
                imageVector = if (n <= value) Icons.Filled.Star else Icons.Outlined.StarBorder,
                contentDescription = null,
                tint = if (n <= value) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.outline,
                modifier = Modifier.size(size.dp),
            )
        }
    }
}
