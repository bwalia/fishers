package com.fishers.app.views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.chat.ChatListViewModel
import com.fishers.app.chat.ChatThreadViewModel
import com.fishers.app.chat.ConversationSummary
import com.fishers.app.net.PublicUser
import com.fishers.app.views.chat.ChatListScreen
import com.fishers.app.views.chat.ChatThreadScreen

/**
 * The five top-level destinations, in the order `MainTabView.swift` has them.
 *
 * Only Profile does anything yet. The other four say which screen is missing
 * rather than rendering blank — a placeholder that names itself is a to-do
 * list; one that does not is a bug report waiting to be filed.
 */
@Composable
fun MainTabScreen(
    user: PublicUser?,
    onSignOut: () -> Unit,
    chatList: ChatListViewModel,
    threadFor: (String) -> ChatThreadViewModel,
    modifier: Modifier = Modifier,
) {
    var tab by rememberSaveable { mutableStateOf(Tab.Home) }
    // Which thread is open, if any. Saved, so rotating the phone mid-sentence
    // does not throw you back to the list.
    var openThread by rememberSaveable { mutableStateOf<String?>(null) }
    var openTitle by rememberSaveable { mutableStateOf("") }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        bottomBar = {
            NavigationBar {
                Tab.entries.forEach { entry ->
                    NavigationBarItem(
                        selected = tab == entry,
                        onClick = { tab = entry },
                        icon = { Icon(entry.icon, contentDescription = null) },
                        // Label as well as icon: an icon-only bar is a guessing
                        // game, and the Laws of this app are hard enough.
                        label = { Text(entry.title) },
                    )
                }
            }
        },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                // Chats fills the pane; the placeholders are centred in it.
                .padding(if (tab == Tab.Chats) 0.dp else 24.dp),
            verticalArrangement = if (tab == Tab.Chats) Arrangement.Top
            else Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
            horizontalAlignment = if (tab == Tab.Chats) Alignment.Start
            else Alignment.CenterHorizontally,
        ) {
            when (tab) {
                Tab.Chats -> ChatsTab(
                    chatList = chatList,
                    threadFor = threadFor,
                    openThread = openThread,
                    openTitle = openTitle,
                    onOpen = { openThread = it.id; openTitle = it.title },
                    onBack = { openThread = null },
                )

                Tab.Profile -> {
                    Text(
                        user?.name ?: "Signed in",
                        style = MaterialTheme.typography.headlineSmall,
                    )
                    user?.email?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                    TextButton(onClick = onSignOut) { Text("Sign out") }
                }

                else -> {
                    Text(tab.title, style = MaterialTheme.typography.headlineSmall)
                    Text(
                        tab.missing,
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}

/**
 * The list, or a thread from it. Back closes the thread rather than the app —
 * the commonest reason somebody presses it here is to go and read another one.
 */
@Composable
private fun ChatsTab(
    chatList: ChatListViewModel,
    threadFor: (String) -> ChatThreadViewModel,
    openThread: String?,
    openTitle: String,
    onOpen: (ConversationSummary) -> Unit,
    onBack: () -> Unit,
) {
    if (openThread == null) {
        val state by chatList.state.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) { chatList.load() }
        ChatListScreen(state = state, onOpen = onOpen)
    } else {
        val model = remember(openThread) { threadFor(openThread) }
        val state by model.state.collectAsStateWithLifecycle()
        LaunchedEffect(openThread) { model.load() }
        BackHandler(onBack = onBack)
        ChatThreadScreen(title = openTitle, state = state, onSend = model::send)
    }
}

private enum class Tab(val title: String, val icon: ImageVector, val missing: String) {
    Home("Home", Icons.Filled.Home, "The feed is not ported yet — HomeFeedView.swift."),
    Fixtures("Fixtures", Icons.Filled.DateRange, "Not ported yet — FixturesView.swift."),
    Chats("Chats", Icons.Filled.Email, ""),
    Clubs("Clubs", Icons.Filled.Person, "Not ported yet — ClubsTeamsView.swift."),
    Profile("Profile", Icons.Filled.AccountCircle, ""),
}
