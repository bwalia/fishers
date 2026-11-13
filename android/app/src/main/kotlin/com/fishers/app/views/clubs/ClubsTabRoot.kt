package com.fishers.app.views.clubs

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.R
import com.fishers.app.clubs.ClubDetailViewModel
import com.fishers.app.clubs.ClubsViewModel
import com.fishers.app.clubs.saidWhy
import com.fishers.app.i18n.t
import com.fishers.app.net.ClubsApi
import com.fishers.app.season.SeasonViewModel
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator
import kotlinx.coroutines.launch

/**
 * The Clubs tab: the list. A club opens as a pushed [ClubRoute], and
 * everything below it — the roster, the club link, the season — hangs off
 * that, so the same page opens from Home, a fixture or an invite link.
 *
 * `clubDetailFor`, `season` and `onOpenFixturesTab` are what this tab was
 * handed when it drew the club inline. The club page now builds its own (a
 * pushed screen is drawn outside this tab), so they are unused here; they stay
 * in the signature because MainTabScreen passes them.
 */
@Suppress("UNUSED_PARAMETER")
@Composable
fun ClubsTabRoot(
    clubs: ClubsViewModel,
    clubDetailFor: (String) -> ClubDetailViewModel,
    season: SeasonViewModel,
    meId: String?,
    onOpenFixturesTab: () -> Unit,
) {
    val nav = LocalNavigator.current
    val deps = LocalAppDeps.current
    val context = LocalContext.current
    val brand = stringResource(R.string.brand_name)
    val scope = rememberCoroutineScope()
    val api = remember { deps.service<ClubsApi>() }
    var profileError by remember { mutableStateOf<String?>(null) }

    val state by clubs.state.collectAsStateWithLifecycle()
    // Each time the tab shows: coming back from starting a club or joining
    // one, the list has to have it.
    LaunchedEffect(Unit) { clubs.load() }

    ClubsScreen(
        state = state,
        onOpen = { nav.push(ClubRoute(it.id, it.name)) },
        onStartClub = { nav.push(CreateClubRoute()) },
        onSearch = clubs::search,
        onRetry = clubs::load,
        profileError = profileError,
        onShareProfile = {
            profileError = null
            scope.launch {
                // The same token each time until it is rotated, so asking
                // again is harmless.
                runCatching { api.profileShareLink() }
                    .onSuccess { link ->
                        val url = "${deps.webBase}/p/${link.token}"
                        shareText(context, t("fin.share_profile_message", vars = mapOf("brand" to brand, "url" to url)))
                    }
                    .onFailure { profileError = saidWhy(it) }
            }
        },
    )
}
