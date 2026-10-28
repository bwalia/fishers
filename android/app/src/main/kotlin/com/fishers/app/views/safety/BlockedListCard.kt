package com.fishers.app.views.safety

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.fishers.app.i18n.t
import com.fishers.app.net.FishersApi
import com.fishers.app.safety.BlockedUser
import kotlinx.coroutines.launch

/**
 * Who you have blocked, and the way back. A block you cannot undo is a
 * setting you are stuck with.
 *
 * Only your own blocks. The symmetric half — people who blocked you — is
 * deliberately absent: telling you would tell you they had.
 *
 * Renders nothing at all when the list is empty. An empty "people you have
 * blocked" is a question nobody asked.
 */
@Composable
fun BlockedListCard(api: FishersApi) {
    val scope = rememberCoroutineScope()
    var blocked by remember { mutableStateOf<List<BlockedUser>>(emptyList()) }

    suspend fun load() {
        blocked = runCatching { api.blockedUsers() }.getOrDefault(emptyList())
    }

    LaunchedEffect(Unit) { load() }

    if (blocked.isEmpty()) return

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(t("mod.blocked_people"), style = MaterialTheme.typography.titleMedium)
            blocked.forEach { user ->
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(user.name, style = MaterialTheme.typography.bodyMedium)
                    TextButton(onClick = {
                        // Off the list first: the row goes either way, and
                        // leaving it there while the request flies looks like
                        // nothing happened. Put back if the request fails.
                        val previous = blocked
                        blocked = blocked.filterNot { it.id == user.id }
                        scope.launch {
                            if (runCatching { api.unblock(user.id) }.isFailure) {
                                blocked = previous
                            }
                        }
                    }) { Text(t("mod.unblock")) }
                }
            }
        }
    }
}
