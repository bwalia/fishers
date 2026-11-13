package com.fishers.app.views.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.fishers.app.i18n.t
import com.fishers.app.views.clubs.CreateClubRoute
import com.fishers.app.views.fixtures.CreateFixtureRoute
import com.fishers.app.views.match.ScoreHubRoute
import com.fishers.app.views.match.StartMatchRoute
import com.fishers.app.views.nav.LocalNavigator
import com.fishers.app.views.onboarding.PendingInvitesSection

/**
 * The things somebody opens the app to do, first on Home: score a match,
 * start a club, put a fixture in. Invitations waiting for them sit above,
 * because answering one is what gets a new player into a club at all.
 */
@Composable
fun HomeActions() {
    val nav = LocalNavigator.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
