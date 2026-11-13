package com.fishers.app.views.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Buttons side by side when every label fits on one line, one under the other
 * at full width when any would not — decided for this phone's width, this
 * font size and this language, not for the screenshot it was designed on.
 *
 * A label broken over two lines inside a pill reads as a layout bug, and
 * shortening the words only moves the problem to Punjabi or to "Large text".
 * A stack of full-width buttons reads as a list of choices.
 *
 * [labels] are what the buttons say, in order; [extra] is room a button needs
 * besides its text (an icon and its gap). [button] draws button `i` with the
 * modifier it must use.
 */
@Composable
fun ButtonRow(
    labels: List<String>,
    modifier: Modifier = Modifier,
    spacing: Dp = 8.dp,
    extra: Dp = 0.dp,
    style: TextStyle = MaterialTheme.typography.labelLarge,
    contentPadding: PaddingValues = ButtonDefaults.ContentPadding,
    button: @Composable (index: Int, modifier: Modifier) -> Unit,
) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val count = labels.size.coerceAtLeast(1)
        val padding = with(density) {
            (contentPadding.calculateLeftPadding(androidx.compose.ui.unit.LayoutDirection.Ltr) +
                contentPadding.calculateRightPadding(androidx.compose.ui.unit.LayoutDirection.Ltr) + extra).toPx()
        }
        val each = with(density) { ((maxWidth - spacing * (count - 1)) / count).toPx() } - padding
        val sideBySide = remember(labels, each, style) {
            labels.all { measurer.measure(it, style, maxLines = 1, softWrap = false).size.width <= each }
        }
        if (sideBySide) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(spacing)) {
                labels.indices.forEach { button(it, Modifier.weight(1f)) }
            }
        } else {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(spacing)) {
                labels.indices.forEach { button(it, Modifier.fillMaxWidth()) }
            }
        }
    }
}

/**
 * A button's words on one line. In a [ButtonRow] they always fit; anywhere
 * else, a label too long for its button ends in "…" rather than growing the
 * button to two lines.
 */
@Composable
fun ButtonLabel(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier = modifier, maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
}
