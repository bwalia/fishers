package com.fishers.app.views.home

import androidx.compose.foundation.layout.Arrangement
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
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { nav.push(StartMatchRoute()) }, modifier = Modifier.weight(1f)) {
                Text(t("cl.start_a_match"), textAlign = TextAlign.Center)
            }
            OutlinedButton(onClick = { nav.push(ScoreHubRoute()) }, modifier = Modifier.weight(1f)) {
                Text(t("cl.matches"), textAlign = TextAlign.Center)
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { nav.push(CreateFixtureRoute()) }, modifier = Modifier.weight(1f)) {
                Text(t("ev.schedule_a_match"), textAlign = TextAlign.Center)
            }
            OutlinedButton(onClick = { nav.push(CreateClubRoute()) }, modifier = Modifier.weight(1f)) {
                Text(t("cl.start_a_club"), textAlign = TextAlign.Center)
            }
        }
    }
}

/** Whether this launch has saved the clubs for a day with no signal yet. */
private val warmed = AtomicBoolean(false)
