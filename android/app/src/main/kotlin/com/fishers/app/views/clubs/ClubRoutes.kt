package com.fishers.app.views.clubs

import androidx.compose.runtime.Composable
import com.fishers.app.views.nav.NotBuiltYet
import com.fishers.app.views.nav.Route

// The clubs area: starting a club, a club's page, teams, members, invites.

/** One club: members, teams, fixtures, and for a secretary or captain the things they run. `ClubsTeamsView.swift`'s club page. */
data class ClubRoute(val clubId: String, val name: String = "") : Route {
    @Composable override fun Content() = NotBuiltYet("Club")
}

/** Start a club, then what comes next. `ClubsTeamsView.swift` + `ClubExtras.swift`. */
class CreateClubRoute : Route {
    @Composable override fun Content() = NotBuiltYet("Start a club")
}

/** An invite link opened in the app (`/invite/{token}`): what it is to, and Join. */
data class JoinByLinkRoute(val token: String) : Route {
    @Composable override fun Content() = NotBuiltYet("Join")
}
