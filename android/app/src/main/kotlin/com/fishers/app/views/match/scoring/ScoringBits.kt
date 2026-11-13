@file:OptIn(ExperimentalLayoutApi::class)

package com.fishers.app.views.match.scoring

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fishers.app.cricket.DeliveryView
import com.fishers.app.cricket.Moment
import com.fishers.app.cricket.Player
import com.fishers.app.i18n.t
import kotlinx.coroutines.delay

/**
 * Colours that mean the same thing in every brand: a four, a six, a wicket.
 * Fixed rather than brand-derived because they are read at arm's length in
 * sunlight, and white on each of them is well past contrast at that size.
 */
internal object BallColours {
    val four = Color(0xFF1E5AA8)
    val six = Color(0xFF6A1B9A)
    val wicket = Color(0xFFB3261E)
    val extra = Color(0xFF9A6700)
}

/**
 * None. A pushed screen sits inside the tab bar's Scaffold, which has already
 * padded it clear of the status and navigation bars; a top bar that added
 * them again would leave a status bar's height of empty space above it.
 */
internal val HostInsets = WindowInsets(0, 0, 0, 0)

/** One ball in the over strip: "4", "W", "wd". */
@Composable
internal fun BallChip(ball: DeliveryView, dim: Boolean = false) {
    val colour = when {
        ball.isWicket -> BallColours.wicket
        !ball.isLegal -> BallColours.extra
        ball.label == "6" -> BallColours.six
        ball.label == "4" -> BallColours.four
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    val filled = ball.isWicket || ball.label == "4" || ball.label == "6"
    Box(
        Modifier
            .sizeIn(minWidth = 34.dp, minHeight = 34.dp)
            .background(
                if (filled) colour else colour.copy(alpha = if (dim) 0.08f else 0.16f),
                CircleShape,
            )
            .padding(horizontal = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            ball.label,
            color = if (filled) Color.White else colour,
            fontWeight = FontWeight.Bold,
            fontSize = 14.sp,
        )
    }
}

/** A label above a group of choices. */
@Composable
internal fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.padding(top = 8.dp, bottom = 4.dp),
    )
}

/**
 * Pick one player, as chips that wrap — a whole side fits on one screen with
 * no list to scroll, and each is a target a thumb can hit.
 */
@Composable
internal fun PlayerChoice(
    players: List<Player>,
    selected: String?,
    onSelect: (String) -> Unit,
    notes: Map<String, String> = emptyMap(),
    disabled: Set<String> = emptySet(),
) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        players.forEach { player ->
            FilterChip(
                selected = player.id == selected,
                onClick = { onSelect(player.id) },
                enabled = player.id !in disabled,
                label = {
                    Text(listOfNotNull(player.name, notes[player.id]).joinToString(" · "))
                },
                modifier = Modifier.sizeIn(minHeight = 48.dp),
            )
        }
    }
}

/** Pick one of a few words. */
@Composable
internal fun <T> WordChoice(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        options.forEach { (value, label) ->
            FilterChip(
                selected = value == selected,
                onClick = { onSelect(value) },
                label = { Text(label) },
                modifier = Modifier.sizeIn(minHeight = 48.dp),
            )
        }
    }
}

/** − n + with big targets. */
@Composable
internal fun Stepper(label: String, value: Int, range: IntRange, onChange: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        FilledTonalIconButton(
            onClick = { onChange((value - 1).coerceIn(range)) },
            enabled = value > range.first,
            modifier = Modifier.size(48.dp),
        ) { Icon(Icons.Filled.Remove, contentDescription = t("sc.fewer")) }
        Text(
            "$value",
            style = MaterialTheme.typography.headlineSmall,
            textAlign = TextAlign.Center,
            modifier = Modifier.sizeIn(minWidth = 48.dp),
        )
        FilledTonalIconButton(
            onClick = { onChange((value + 1).coerceIn(range)) },
            enabled = value < range.last,
            modifier = Modifier.size(48.dp),
        ) { Icon(Icons.Filled.Add, contentDescription = t("sc.more")) }
    }
}

/**
 * A beat of celebration over the top of the screen — FOUR, SIX, OUT! — that
 * taps pass straight through. Said once to a screen reader.
 */
@Composable
internal fun MomentBanner(moment: Moment?, count: Int, modifier: Modifier = Modifier) {
    var showing by remember { mutableStateOf<Moment?>(null) }
    LaunchedEffect(count) {
        if (count == 0 || moment == null) return@LaunchedEffect
        showing = moment
        delay(moment.lastsMillis)
        showing = null
    }
    AnimatedVisibility(visible = showing != null, enter = fadeIn(), exit = fadeOut(), modifier = modifier) {
        val m = showing ?: return@AnimatedVisibility
        val colour = when (m.kind) {
            Moment.Kind.Four -> BallColours.four
            Moment.Kind.Six -> BallColours.six
            Moment.Kind.Wicket -> BallColours.wicket
        }
        Column(
            Modifier
                .padding(16.dp)
                .background(colour, RoundedCornerShape(20.dp))
                .padding(horizontal = 28.dp, vertical = 14.dp)
                .semantics {
                    liveRegion = LiveRegionMode.Polite
                    contentDescription = m.spoken
                },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(m.word, color = Color.White, fontSize = 40.sp, fontWeight = FontWeight.Black)
            Text(m.who, color = Color.White, style = MaterialTheme.typography.titleMedium)
            m.detail?.let { Text(it, color = Color.White.copy(alpha = 0.85f), style = MaterialTheme.typography.bodyMedium) }
        }
    }
}

/** A coloured line of warning: a free hit, a bowler to choose. */
@Composable
internal fun Banner(text: String, colour: Color, modifier: Modifier = Modifier) {
    Text(
        text,
        color = colour,
        fontWeight = FontWeight.Bold,
        style = MaterialTheme.typography.labelLarge,
        modifier = modifier
            .background(colour.copy(alpha = 0.14f), RoundedCornerShape(50))
            .padding(horizontal = 12.dp, vertical = 6.dp),
    )
}
