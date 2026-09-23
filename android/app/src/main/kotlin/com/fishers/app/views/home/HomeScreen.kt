package com.fishers.app.views.home

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
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.fishers.app.fixtures.FishersEvent
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
        Text(
            name?.let { "Afternoon, ${it.substringBefore(' ')}" } ?: "Fishers",
            style = MaterialTheme.typography.headlineSmall,
        )

        state.error?.let {
            Text(it, color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium)
        }

        Tile("Next up") {
            state.next?.let { NextFixture(it) }
                ?: Text("Nothing in the diary.", style = MaterialTheme.typography.bodyMedium)
        }

        Tile("Chats") {
            Text(
                when (state.unreadChats) {
                    0L -> "Nothing unread."
                    1L -> "One message waiting."
                    else -> "${state.unreadChats} messages waiting."
                },
                style = MaterialTheme.typography.bodyMedium,
            )
        }

        Tile("Clubs") {
            Text(
                when (state.clubCount) {
                    0 -> "You are not in a club yet."
                    1 -> "One club."
                    else -> "${state.clubCount} clubs."
                },
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
private fun Tile(title: String, content: @Composable () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
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
private fun NextFixture(event: FishersEvent) {
    Text(event.title, style = MaterialTheme.typography.titleMedium)
    Text(formatWhen(event.startAt), style = MaterialTheme.typography.bodyMedium)
}

@Preview(showBackground = true)
@Composable
private fun HomePreview() {
    FishersTheme {
        HomeScreen(
            "Ravi Patel",
            HomeState(
                isFirstLoad = false,
                next = FishersEvent(
                    id = "1", clubId = "c", title = "Lords CC v Hemel",
                    startAt = "2026-09-27T13:30:00Z",
                ),
                unreadChats = 3,
                clubCount = 2,
            ),
        )
    }
}
