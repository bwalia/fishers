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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.fishers.app.net.PublicUser

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
    modifier: Modifier = Modifier,
) {
    var tab by rememberSaveable { mutableStateOf(Tab.Home) }

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
            modifier = Modifier.fillMaxSize().padding(inner).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            when (tab) {
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

private enum class Tab(val title: String, val icon: ImageVector, val missing: String) {
    Home("Home", Icons.Filled.Home, "The feed is not ported yet — HomeFeedView.swift."),
    Fixtures("Fixtures", Icons.Filled.DateRange, "Not ported yet — FixturesView.swift."),
    Chats("Chats", Icons.Filled.Email, "Not ported yet — ChatListView.swift."),
    Clubs("Clubs", Icons.Filled.Person, "Not ported yet — ClubsTeamsView.swift."),
    Profile("Profile", Icons.Filled.AccountCircle, ""),
}
