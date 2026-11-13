package com.fishers.app.views.clubs

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fishers.app.i18n.t
import com.fishers.app.views.nav.LocalNavigator

/** A screen pushed over the tabs: a bar with the way back, then the content. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ClubScreen(
    title: String,
    actions: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    val nav = LocalNavigator.current
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        TopAppBar(
            title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            navigationIcon = {
                IconButton(onClick = nav::pop) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = t("sc.back"))
                }
            },
            actions = actions,
            // The tabs' scaffold has already stepped round the status bar.
            windowInsets = WindowInsets(0, 0, 0, 0),
        )
        content()
    }
}

/** A section's title: small, coloured, and announced as a heading. */
@Composable
internal fun SectionHeading(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = modifier.padding(top = 16.dp, bottom = 4.dp).semantics { heading() },
    )
}

/** Secondary words under a field or a section. */
@Composable
internal fun Hint(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier,
    )
}

@Composable
internal fun ErrorLine(text: String, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error, modifier = modifier)
}

/**
 * A club's initials on one of three colours, fixed per club, so a long list is
 * not a wall of identical squares. From words that start with a letter:
 * "Captain 1974 CC" is CC, not C1.
 */
@Composable
internal fun ClubCrest(name: String, id: String, size: Dp = 44.dp) {
    val initials = name.split(' ')
        .filter { it.firstOrNull()?.isLetter() == true }
        .take(2)
        .joinToString("") { it.first().uppercase() }
        .ifEmpty { "?" }
    val scheme = MaterialTheme.colorScheme
    val colour = when ((id.takeLast(2).toIntOrNull(16) ?: 0) % 3) {
        1 -> scheme.secondary
        2 -> scheme.tertiary
        else -> scheme.primary
    }
    val on = when (colour) {
        scheme.secondary -> scheme.onSecondary
        scheme.tertiary -> scheme.onTertiary
        else -> scheme.onPrimary
    }
    Box(
        Modifier
            .size(size)
            .background(colour, RoundedCornerShape(size * 0.28f))
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Text(initials, color = on, fontWeight = FontWeight.Bold, fontSize = (size.value * 0.36f).sp)
    }
}

/** The share sheet, with `text` in it — WhatsApp, Messages, whatever they use. */
internal fun shareText(context: Context, text: String) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    context.startActivity(Intent.createChooser(send, null))
}

/** Somewhere small to remember a choice on this phone — a checklist somebody hid. */
internal fun clubPrefs(context: Context) =
    context.getSharedPreferences("fishers.clubs", Context.MODE_PRIVATE)
