package com.fishers.app.views.home

import com.fishers.app.i18n.t

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.fishers.app.R
import com.fishers.app.fixtures.MyFixture
import com.fishers.app.fixtures.formatWhen
import com.fishers.app.home.HomeState
import com.fishers.app.theme.FishersTheme

/**
 * What matters inside a second of opening the app: the next game, and whether
 * anybody is waiting on a reply.
 */
@Composable
fun HomeScreen(
    name: String?,
    state: HomeState,
    /// Kit for sale. Reached from here rather than from a sixth tab — a
    /// bottom bar stops being scannable past five.
    onOpenShop: () -> Unit = {},
    /// Scores from the wider game. Same reasoning as the shop: reached from
    /// here rather than from a tab, because a bottom bar stops being
    /// scannable past five.
    onOpenScores: () -> Unit = {},
    /** Drawn under the greeting: what to do next. */
    actions: @Composable () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    if (state.isFirstLoad && state.isLoading) {
        Box(modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        return
    }

    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            name?.let { t("rest.afternoon_name", vars = mapOf("name" to it.substringBefore(' '))) }
                ?: stringResource(R.string.brand_name),
            style = MaterialTheme.typography.headlineSmall,
        )

        actions()

        state.error?.let {
            Text(it, color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium)
        }

        // A tile that could not load says so, rather than "none" — which, for
        // somebody in a club with no signal, would be a wrong fact.
        Tile(t("rest.next_up")) {
            when {
                state.next != null -> NextFixture(state.next)
                state.fixturesFailed -> CouldNotLoad(t("ld.could_not_load_your_fixtures"))
                else -> Text(t("ev.nothing_in_the_diary"), style = MaterialTheme.typography.bodyMedium)
            }
        }

        Tile(t("nav.chats")) {
            Text(
                when (state.unreadChats) {
                    null -> t("le.could_not_load_your_chats")
                    0L -> t("rest.nothing_unread")
                    1L -> t("rest.one_message_waiting")
                    else -> "${state.unreadChats} messages waiting."
                },
                style = MaterialTheme.typography.bodyMedium,
                color = if (state.unreadChats == null) MaterialTheme.colorScheme.onSurfaceVariant else Color.Unspecified,
            )
        }

        Tile(t("nav.clubs")) {
            Text(
                when (state.clubCount) {
                    null -> t("lc.could_not_load_your_clubs")
                    0 -> t("cl.not_in_a_club_yet")
                    1 -> t("rest.one_club")
                    else -> "${state.clubCount} clubs."
                },
                style = MaterialTheme.typography.bodyMedium,
                color = if (state.clubCount == null) MaterialTheme.colorScheme.onSurfaceVariant else Color.Unspecified,
            )
        }

        Tile(t("sh.kit_for_sale"), onClick = onOpenShop) {
            Text(t("sh.bats_pads_club_kit"),
                style = MaterialTheme.typography.bodyMedium,
            )
        }

        // Worded so it cannot be read as your own club's match: the fixtures
        // above are yours, this is everybody else's.
        Tile(t("sr.cricket_scores"), onClick = onOpenScores) {
            Text(t("rest.live_scores_around_the_world"),
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
private fun Tile(
    title: String,
    onClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    Card(
        Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            content()
        }
    }
}

@Composable
private fun CouldNotLoad(text: String) {
    Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun NextFixture(event: MyFixture) {
    Text(event.title, style = MaterialTheme.typography.titleMedium)
    val practice = event.practice
    if (practice == null) {
        Text(formatWhen(event.startAt), style = MaterialTheme.typography.bodyMedium)
    } else {
        // Nets or training says so: its name alone could be anything.
        Text(
            // …unless the name already is the kind: "Nets" over "Nets · Fri…" says it twice.
            listOfNotNull(
                event.subtype.label.takeUnless { it.equals(event.title.trim(), ignoreCase = true) },
                formatWhen(event.startAt),
                practice.weekOf,
            ).joinToString(" · "),
            style = MaterialTheme.typography.bodyMedium,
        )
        practice.note?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun HomePreview() {
    FishersTheme {
        HomeScreen(
            "Ravi Patel",
            HomeState(
                isFirstLoad = false,
                next = MyFixture(
                    id = "1", clubId = "c", title = "Lords CC v Hemel",
                    startAt = "2026-09-27T13:30:00Z",
                ),
                unreadChats = 3,
                clubCount = 2,
            ),
        )
    }
}
