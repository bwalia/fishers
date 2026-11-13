package com.fishers.app.views.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.EventRepeat
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.SportsCricket
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import com.fishers.app.views.components.ButtonLabel
import com.fishers.app.views.components.ButtonRow
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.fishers.app.cricket.FileBallStore
import com.fishers.app.i18n.t
import com.fishers.app.match.start.OfflineCache
import com.fishers.app.match.start.phoneMatches
import com.fishers.app.match.start.refresh
import com.fishers.app.net.MatchStartApi
import com.fishers.app.views.clubs.CreateClubRoute
import com.fishers.app.views.fixtures.CreateFixtureRoute
import com.fishers.app.views.match.ScoreHubRoute
import com.fishers.app.views.match.StartMatchRoute
import com.fishers.app.views.match.start.OnThisPhone
import com.fishers.app.views.match.start.open
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator
import com.fishers.app.views.onboarding.PendingInvitesSection
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The things somebody opens the app to do, first on Home: score a match,
 * start a club, put a fixture in. Invitations waiting for them sit above,
 * because answering one is what gets a new player into a club at all.
 *
 * With no signal, the matches on this phone come first: a scorer who opens
 * the app at the ground is one tap from the match they were scoring.
 */
@Composable
fun HomeActions(offline: Boolean = false) {
    val nav = LocalNavigator.current
    val deps = LocalAppDeps.current
    val context = LocalContext.current
    // Once a launch, while there is signal: the clubs and players a match
    // started with none will need. Home is the screen everyone opens.
    LaunchedEffect(Unit) {
        if (warmed.compareAndSet(false, true)) {
            runCatching { OfflineCache.forApp(context).refresh(deps.service<MatchStartApi>()) }
                .onFailure { warmed.set(false) }
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (offline) {
            val matches = remember(offline) {
                runCatching { phoneMatches(FileBallStore.forApp(context).all()) }.getOrDefault(emptyList())
            }
            OnThisPhone(matches, onOpen = nav::open, note = t("ms.no_signal_carry_on"))
        }
        PendingInvitesSection()
        // The two things people open the app to do, side by side when both
        // labels fit on one line and stacked when they would not.
        ButtonRow(
            labels = listOf(t("cl.start_a_match"), t("cl.matches")),
            extra = 26.dp,
        ) { i, m ->
            if (i == 0) {
                Button(onClick = { nav.push(StartMatchRoute()) }, modifier = m.heightIn(min = 52.dp)) {
                    Icon(Icons.Filled.SportsCricket, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    ButtonLabel(t("cl.start_a_match"))
                }
            } else {
                OutlinedButton(onClick = { nav.push(ScoreHubRoute()) }, modifier = m.heightIn(min = 52.dp)) {
                    ButtonLabel(t("cl.matches"))
                }
            }
        }
        // The rest as a list, which never squeezes a long label into a pill.
        Card(Modifier.fillMaxWidth()) {
            ActionRow(Icons.Filled.DateRange, t("ev.schedule_a_match")) { nav.push(CreateFixtureRoute()) }
            HorizontalDivider()
            ActionRow(Icons.Filled.EventRepeat, t("np.schedule_nets_or_practice")) {
                nav.push(CreateFixtureRoute(nets = true))
            }
            HorizontalDivider()
            ActionRow(Icons.Filled.Groups, t("cl.start_a_club")) { nav.push(CreateClubRoute()) }
        }
    }
}

/** One thing to do: an icon, what it is, and a chevron that says it goes somewhere. */
@Composable
private fun ActionRow(icon: ImageVector, label: String, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onClick)
            .heightIn(min = 56.dp)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** Whether this launch has saved the clubs for a day with no signal yet. */
private val warmed = AtomicBoolean(false)
