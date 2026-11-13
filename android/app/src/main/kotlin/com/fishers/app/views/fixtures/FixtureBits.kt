package com.fishers.app.views.fixtures

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.Color
import com.fishers.app.fixtures.AvailabilityStatus
import com.fishers.app.fixtures.RsvpStatus
import com.fishers.app.i18n.t
import com.fishers.app.views.nav.LocalNavigator

/**
 * A pushed screen in this area: a title, a way back, and the content.
 *
 * No window insets of its own — the tab scaffold underneath has already
 * padded for the status bar and the tab bar, and padding twice leaves a band
 * of nothing above the title.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PushedScreen(
    title: String,
    actions: @Composable RowScope.() -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    content: @Composable (PaddingValues) -> Unit,
) {
    val nav = LocalNavigator.current
    Scaffold(
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = t("sc.back"))
                    }
                },
                actions = actions,
                windowInsets = WindowInsets(0),
            )
        },
        bottomBar = bottomBar,
        content = content,
    )
}

@Composable
internal fun Loading(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
}

@Composable
internal fun SectionHeading(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = modifier.semantics { heading() },
    )
}

/**
 * Green, amber, red. Dark enough to carry white text; the red is the theme's,
 * since a red that varies by brand is a red somebody misses.
 */
@Composable
internal fun availabilityColour(status: AvailabilityStatus): Color = when (status) {
    AvailabilityStatus.Available -> Color(0xFF2E7D32)
    AvailabilityStatus.Maybe -> Color(0xFF9A5B00)
    AvailabilityStatus.Unavailable -> MaterialTheme.colorScheme.error
}

@Composable
internal fun ErrorText(text: String) {
    Text(text, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
}

/**
 * Can you play? The three answers, side by side, the one you gave lit. Each
 * a full 48dp target: this is tapped one-handed at the bus stop.
 */
@Composable
internal fun AnswerChips(
    answer: RsvpStatus?,
    enabled: Boolean,
    onAnswer: (RsvpStatus) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf(RsvpStatus.Going, RsvpStatus.Maybe, RsvpStatus.NotGoing).forEach {
            FilterChip(
                selected = answer == it,
                onClick = { onAnswer(it) },
                enabled = enabled,
                label = { Text(it.label) },
                modifier = Modifier.heightIn(min = 48.dp),
            )
        }
    }
}
