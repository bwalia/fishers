package com.fishers.app.views.clubs

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.clubs.RoleChoice
import com.fishers.app.clubs.TeamRosterViewModel
import com.fishers.app.clubs.UserRole
import com.fishers.app.i18n.t
import com.fishers.app.net.ClubsApi
import com.fishers.app.season.SeasonLink
import com.fishers.app.season.SeasonTab
import com.fishers.app.season.SeasonViewModel
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator
import com.fishers.app.views.nav.Route
import com.fishers.app.views.profile.PlayerProfileRoute
import com.fishers.app.views.season.SeasonPage

// The clubs area: starting a club, a club's page, teams, members, invites.

/**
 * One club: members, teams, grounds, fixtures, and for a secretary or captain
 * the things they run. `ClubsTeamsView.swift`'s club page. `welcome` is set
 * straight after the club was made, and opens with what to do next.
 */
data class ClubRoute(val clubId: String, val name: String = "", val welcome: Boolean = false) : Route {
    @Composable override fun Content() = ClubPage(clubId, name, welcome)
}

/** Start a club, then what comes next. `ClubsTeamsView.swift` + `ClubExtras.swift`. */
class CreateClubRoute : Route {
    @Composable override fun Content() = CreateClubPage()
}

/** An invite link opened in the app (`/invite/{token}`): what it is to, and Join. */
data class JoinByLinkRoute(val token: String) : Route {
    @Composable override fun Content() = JoinByLinkPage(token)
}

/**
 * The roster, the club link, the policy and the fees — `ClubAdminView.swift`.
 * `startAdding` opens on adding somebody, from a new club's welcome.
 */
data class ManageClubRoute(val clubId: String, val name: String, val startAdding: Boolean = false) : Route {
    @Composable override fun Content() = ManageClubPage(clubId, name, startAdding)
}

/** One team, and who is in it — `TeamRosterView`. */
data class TeamRoute(val teamId: String, val name: String) : Route {
    @Composable override fun Content() = TeamRosterPage(teamId, name)
}

/**
 * The club's season: its record, its leaderboards, and for a secretary the
 * close-the-season box. The same page as the profile's, on the club tab.
 */
data class ClubSeasonRoute(val clubId: String, val name: String = "") : Route {
    @Composable override fun Content() {
        val deps = LocalAppDeps.current
        val nav = LocalNavigator.current
        // Its own model: this screen is pushed from wherever the club page
        // was, and must not move the profile's season to this club.
        val season = remember(clubId) {
            SeasonViewModel(deps.api).also { it.open(SeasonLink(tab = SeasonTab.Club, clubId = clubId)) }
        }
        ClubScreen(title = name.ifEmpty { t("ss.club_season") }) {
            SeasonPage(
                season = season,
                meId = deps.user()?.id,
                // Back to the club, whose page lists its fixtures.
                onOpenFixtures = nav::pop,
                onOpenClubs = nav::pop,
            )
        }
    }
}

@Composable
private fun TeamRosterPage(teamId: String, name: String) {
    val deps = LocalAppDeps.current
    val nav = LocalNavigator.current
    val model = remember(teamId) { TeamRosterViewModel(deps.service<ClubsApi>(), teamId) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(teamId) { model.load() }

    ClubScreen(title = name) {
        val members = state.members
        when {
            state.failed -> Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
                Hint(t("cl.could_not_load_this_team"))
            }
            members == null -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            members.isEmpty() -> Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center) {
                Text(t("cl.nobody_in_this_team_yet"), style = MaterialTheme.typography.titleMedium)
                Hint(t("cl.secretary_or_captain_adds"))
            }
            else -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 16.dp)) {
                item { SectionHeading(t("cl.n_in_the_squad", vars = mapOf("n" to members.size))) }
                items(members, key = { it.userId }) { member ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .clickable { nav.push(PlayerProfileRoute(member.userId, member.name)) }
                            .padding(vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(member.name, style = MaterialTheme.typography.bodyLarge)
                            member.positionRole?.let { Hint(it) }
                        }
                        if (member.role != UserRole.Member) {
                            Text(
                                RoleChoice(member.role).shortLabel,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                    }
                    HorizontalDivider()
                }
            }
        }
    }
}
