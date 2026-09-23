package com.fishers.app.views.chat

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Badge
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.fishers.app.chat.ChatListState
import com.fishers.app.chat.ConversationSummary
import com.fishers.app.theme.FishersTheme

/**
 * Every thread this person is in — `ChatListView.swift`.
 *
 * Ordered by the last thing said, which is what somebody scans for. An unread
 * count is a badge rather than bold text alone, because bold is hard to see on
 * a phone held at arm's length on a boundary.
 */
@Composable
fun ChatListScreen(
    state: ChatListState,
    onOpen: (ConversationSummary) -> Unit,
    modifier: Modifier = Modifier,
) {
    when {
        state.isFirstLoad && state.isLoading ->
            Box(modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }

        state.error != null && state.conversations.isEmpty() ->
            Message(modifier, state.error, "Pull down once there is signal.")

        state.conversations.isEmpty() ->
            Message(
                modifier,
                "No chats yet.",
                "A club or a fixture starts one, and it appears here.",
            )

        else -> LazyColumn(modifier.fillMaxSize()) {
            items(state.conversations, key = { it.id }) { conversation ->
                ConversationRow(conversation, onClick = { onOpen(conversation) })
                HorizontalDivider()
            }
        }
    }
}

@Composable
private fun ConversationRow(conversation: ConversationSummary, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                conversation.title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = if (conversation.hasUnread) FontWeight.Bold else FontWeight.Normal,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            conversation.lastMessageBody?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (conversation.hasUnread) {
            // The number is already in the row's description below, so the
            // badge itself says nothing — otherwise a screen reader reads the
            // count twice.
            Badge(modifier = Modifier.clearAndSetSemantics {}) {
                Text(conversation.unreadCount.coerceAtMost(99).toString())
            }
        }
    }
}

@Composable
private fun Message(modifier: Modifier, title: String, detail: String) {
    Column(
        modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Text(
            detail,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun ChatListPreview() {
    FishersTheme {
        ChatListScreen(
            ChatListState(
                isFirstLoad = false,
                conversations = listOf(
                    ConversationSummary(
                        id = "1", kind = "club", title = "Lords CC",
                        updatedAt = "2026-09-23T10:00:00Z",
                        lastMessageBody = "Nets moved to Thursday",
                        unreadCount = 3,
                    ),
                    ConversationSummary(
                        id = "2", kind = "event", title = "v Hemel, Saturday",
                        updatedAt = "2026-09-22T18:00:00Z",
                        lastMessageBody = "I can do umpire for the first innings",
                    ),
                ),
            ),
            onOpen = {},
        )
    }
}
