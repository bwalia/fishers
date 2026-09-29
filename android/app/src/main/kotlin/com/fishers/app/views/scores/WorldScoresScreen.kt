package com.fishers.app.views.scores

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.fishers.app.scores.WorldMatch
import com.fishers.app.scores.WorldScoresState

/**
 * Scores from the wider game — internationals and domestic competitions.
 *
 * Always says how old the scores are rather than pretending to be a broadcast:
 * they come from a free feed on a small daily allowance and run a few minutes
 * behind live play, and a stale score that does not admit it is worse than one
 * that does.
 */
@Composable
fun WorldScoresScreen(
    state: WorldScoresState,
    onOpen: (String) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val scores = state.scores

    if (state.isFirstLoad && scores == null) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        return
    }

    if (state.error != null && scores == null) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                state.error,
                color = MaterialTheme.colorScheme.error,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(24.dp),
            )
        }
        return
    }

    if (scores == null || !scores.enabled) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("World scores aren't switched on here.", style = MaterialTheme.typography.titleSmall)
                Text(
                    "They run only where a score feed is configured.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 4.dp, start = 24.dp, end = 24.dp),
                )
            }
        }
        return
    }

    LazyColumn(
        modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text(
                "Scores updated ${scores.freshness()}. They come from a free feed and run a " +
                    "few minutes behind live play.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // Cricket's words do not mean quite what they do in other sports — a
        // Test at stumps is still being played — so each group says what it
        // holds.
        group(
            "Being played now",
            "Matches in progress, including the intervals.",
            scores.live,
            "Nothing is being played at the moment.",
            onOpen,
        )
        group("Coming up", "Due to start soon.", scores.upcoming, "No fixtures listed for the next few days.", onOpen)
        group("Recent results", "Matches that have finished.", scores.recent, "No results yet.", onOpen)
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.group(
    title: String,
    note: String,
    matches: List<WorldMatch>,
    empty: String,
    onOpen: (String) -> Unit,
) {
    item {
        Column {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(
                note,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    if (matches.isEmpty()) {
        item {
            Text(
                empty,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    } else {
        items(matches, key = { it.id }) { ScoreCard(it, onOpen) }
    }
}

/**
 * One match, in the shape a scorecard is normally read in: who, what they made,
 * and then the sentence saying where the game stands.
 */
@Composable
private fun ScoreCard(match: WorldMatch, onOpen: (String) -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            // The whole card is the target: on a phone it is what a thumb is
            // already aiming at.
            .clickable { onOpen(match.id) }
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                match.leagueName,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            StateBadge(match)
        }

        Side(
            name = match.homeTeamName,
            initials = match.homeInitials,
            logo = match.homeTeamLogo,
            score = match.homeScore,
            info = match.homeInfo,
            batting = match.homeBatting,
        )
        Side(
            name = match.awayTeamName,
            initials = match.awayInitials,
            logo = match.awayTeamLogo,
            score = match.awayScore,
            info = match.awayInfo,
            batting = match.awayBatting,
        )

        match.report?.let {
            HorizontalDivider()
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            match.formatLabel?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(MaterialTheme.colorScheme.surface)
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
            if (match.phase == "pending") {
                match.startLabel?.let {
                    Text(
                        "Starts $it",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            match.countryName?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * The word is always there — "In play", "Tea", "Stumps". The colour and the dot
 * sit on top of the text, never instead of it.
 */
@Composable
private fun StateBadge(match: WorldMatch) {
    val tint =
        if (match.isLive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        if (match.isLive) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(tint))
        }
        Text(match.state.uppercase(), style = MaterialTheme.typography.labelSmall, color = tint)
    }
}

@Composable
private fun Side(
    name: String,
    initials: String,
    logo: String?,
    score: String?,
    info: String?,
    batting: Boolean,
) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Badge(logo, initials)
        Column(Modifier.weight(1f)) {
            Text(
                name,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = if (batting) FontWeight.Bold else FontWeight.Normal,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (batting) {
                // In words, so it survives a screen reader and a colour-blind
                // reader alike.
                Text(
                    "batting",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                score ?: "—",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
            )
            info?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun Badge(logo: String?, initials: String) {
    val shape = RoundedCornerShape(5.dp)
    if (logo != null) {
        AsyncImage(
            model = logo,
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.size(26.dp).clip(shape),
        )
    } else {
        Box(
            Modifier
                .size(26.dp)
                .clip(shape)
                .background(MaterialTheme.colorScheme.surface)
                .border(1.dp, MaterialTheme.colorScheme.outlineVariant, shape),
            contentAlignment = Alignment.Center,
        ) {
            Text(initials, fontSize = 9.sp, fontWeight = FontWeight.Bold)
        }
    }
}
