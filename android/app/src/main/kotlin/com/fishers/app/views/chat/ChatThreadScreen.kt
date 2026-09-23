package com.fishers.app.views.chat

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.fishers.app.chat.ChatMessage
import com.fishers.app.chat.ChatThreadState
import com.fishers.app.theme.FishersTheme

/**
 * One thread — `ChatThreadView.swift`.
 *
 * Three kinds of message, and they do not look alike: what somebody typed,
 * what the app did, and what the agent suggested. A system line that reads like
 * a person is how a captain ends up arguing with a robot.
 */
@Composable
fun ChatThreadScreen(
    title: String,
    state: ChatThreadState,
    onSend: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var draft by rememberSaveable { mutableStateOf("") }
    val listState = rememberLazyListState()

    // Follow the conversation down as it grows, the way a thread should.
    LaunchedEffect(state.messages.size) {
        if (state.messages.isNotEmpty()) listState.animateScrollToItem(state.messages.lastIndex)
    }

    Column(modifier.fillMaxSize().imePadding()) {
        Box(Modifier.weight(1f)) {
            when {
                state.isFirstLoad && state.isLoading ->
                    Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }

                state.messages.isEmpty() -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                    Text(
                        state.error ?: "Nothing said yet.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }

                else -> LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(state.messages, key = { it.id }) { MessageRow(it) }
                }
            }
        }

        state.error?.takeIf { state.messages.isNotEmpty() }?.let {
            Text(
                it,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }

        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Message $title") },
                maxLines = 4,
            )
            IconButton(
                onClick = { onSend(draft); draft = "" },
                enabled = draft.isNotBlank() && !state.isSending,
            ) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send")
            }
        }
    }
}

@Composable
private fun MessageRow(message: ChatMessage) {
    when {
        // Not a person talking, and it must not look like one.
        message.isSystem -> Text(
            message.body,
            style = MaterialTheme.typography.bodySmall,
            fontStyle = FontStyle.Italic,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
            modifier = Modifier.fillMaxWidth(),
        )

        else -> Surface(
            color = if (message.isAgent) MaterialTheme.colorScheme.secondaryContainer
            else MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(12.dp),
            modifier = Modifier.widthIn(max = 560.dp),
        ) {
            Column(Modifier.padding(12.dp)) {
                Text(
                    message.senderName ?: if (message.isAgent) "Fishers" else "Someone",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(message.body, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun ThreadPreview() {
    FishersTheme {
        ChatThreadScreen(
            title = "Lords CC",
            state = ChatThreadState(
                isFirstLoad = false,
                messages = listOf(
                    ChatMessage("1", "c", "u1", "Ravi Patel", "text", "Nets Thursday?", "t"),
                    ChatMessage("2", "c", null, null, "system", "Fixture moved to Saturday", "t"),
                    ChatMessage("3", "c", null, null, "agent", "Nine have said yes.", "t"),
                ),
            ),
            onSend = {},
        )
    }
}
