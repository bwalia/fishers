package com.fishers.app.views.match

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.cricket.DeviceId
import com.fishers.app.match.start.HubDestination
import com.fishers.app.match.start.MatchSetupViewModel
import com.fishers.app.match.start.ScoreHubViewModel
import com.fishers.app.match.start.SetupStep
import com.fishers.app.match.start.StartMatchViewModel
import com.fishers.app.net.MatchStartApi
import com.fishers.app.views.clubs.CreateClubRoute
import com.fishers.app.views.match.start.MatchSetupScreen
import com.fishers.app.views.match.start.OppositionPicker
import com.fishers.app.views.match.start.ScoreHubScreen
import com.fishers.app.views.match.start.StartMatchScreen
import com.fishers.app.views.match.start.routeViewModel
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator
import com.fishers.app.views.nav.Route
import com.fishers.app.views.profile.EditProfileRoute

// Starting a match: the hub, the quick start, the setup wizard.
// Other areas push these; this area owns what they draw.

/** Every cricket fixture you can see — live, coming up, finished — and "Start a match now". `ScoreHubView.swift`. */
class ScoreHubRoute : Route {
    @Composable override fun Content() {
        val nav = LocalNavigator.current
        val api = LocalAppDeps.current.service<MatchStartApi>()
        val model = routeViewModel { ScoreHubViewModel(api) }
        val state by model.state.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) { model.load() }
        ScoreHubScreen(
            state = state,
            onBack = nav::pop,
            onStartMatch = { nav.push(StartMatchRoute()) },
            onFilter = model::setFilter,
            onSearch = model::setSearch,
            onNewestFirst = model::setNewestFirst,
            onRefresh = model::reload,
            onLoadMore = model::loadMore,
            onOpen = { row ->
                when (val to = model.destination(row)) {
                    is HubDestination.Scorecard -> nav.push(ScorecardRoute(to.eventId))
                    is HubDestination.Score -> nav.push(ScoreMatchRoute(to.eventId))
                    is HubDestination.Setup -> nav.push(MatchSetupRoute(to.eventId))
                }
            },
        )
    }
}

/** A quick match: your club (and team), the opposition, the kind — makes the fixture, then sets the match up. `ScoreHubView.swift`'s start sheet. */
data class StartMatchRoute(val clubId: String? = null) : Route {
    @Composable override fun Content() {
        val nav = LocalNavigator.current
        val deps = LocalAppDeps.current
        val api = deps.service<MatchStartApi>()
        val user = deps.user()
        val channel = when {
            !user?.email.isNullOrBlank() -> "email"
            !user?.phone.isNullOrBlank() -> "phone"
            else -> null
        }
        val model = routeViewModel {
            StartMatchViewModel(api, preferredClubId = clubId, verifyChannel = channel, onVerified = deps.setUser)
        }
        val state by model.state.collectAsStateWithLifecycle()
        var picking by rememberSaveable { mutableStateOf(false) }
        LaunchedEffect(Unit) { model.load() }
        LaunchedEffect(state.startedEventId) {
            val id = state.startedEventId ?: return@LaunchedEffect
            model.started()
            nav.replace(MatchSetupRoute(id))
        }
        if (picking) {
            OppositionPicker(
                api = api,
                onPick = { name, identity -> model.setOpposition(name, identity); picking = false },
                onCancel = { picking = false },
            )
            return
        }
        StartMatchScreen(
            state = state,
            onBack = nav::pop,
            onRetry = model::load,
            onClub = model::selectClub,
            onTeam = model::selectTeam,
            onTeamName = model::setNewTeamName,
            onPickOpposition = { picking = true },
            onKind = model::setKind,
            onStart = model::start,
            onStartAClub = { nav.push(CreateClubRoute()) },
            onSendCode = model::sendCode,
            onCode = model::setCode,
            onConfirmCode = model::confirmCode,
            onEditProfile = { nav.push(EditProfileRoute()) },
        )
    }
}

/** Overs, sides, toss, team sheets, openers — then the scorer. `CricketScoringFlowView.swift`. */
data class MatchSetupRoute(val eventId: String) : Route {
    @Composable override fun Content() {
        val nav = LocalNavigator.current
        val deps = LocalAppDeps.current
        val api = deps.service<MatchStartApi>()
        val context = LocalContext.current
        val deviceId = remember { DeviceId.get(context) }
        val userName = deps.user()?.name
        val model = routeViewModel { MatchSetupViewModel(api, eventId, deviceId, userName) }
        val state by model.state.collectAsStateWithLifecycle()
        var picking by rememberSaveable { mutableStateOf(false) }
        LaunchedEffect(Unit) { model.load() }
        // The first ball is the scorer's: hand over, and take this screen off
        // the stack so back from the scorer does not land in a finished wizard.
        LaunchedEffect(state.step) {
            if (state.step == SetupStep.Scoring) nav.replace(ScoreMatchRoute(eventId))
        }
        if (picking) {
            OppositionPicker(
                api = api,
                onPick = { name, identity -> model.setOpposition(name, identity); picking = false },
                onCancel = { picking = false },
            )
            return
        }
        MatchSetupScreen(
            state = state,
            model = model,
            onBack = nav::pop,
            onPickOpposition = { picking = true },
            onFollow = { nav.replace(ScorecardRoute(eventId)) },
        )
    }
}
