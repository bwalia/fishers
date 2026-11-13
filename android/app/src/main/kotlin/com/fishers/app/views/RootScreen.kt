package com.fishers.app.views

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import kotlinx.coroutines.launch
import com.fishers.app.session.requestGoogleIdToken
import com.fishers.app.session.GoogleResult
import com.fishers.app.i18n.t
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.session.SessionViewModel
import com.fishers.app.views.auth.AuthScreen

/**
 * Not signed in → the form; signed in → the tabs — `RootView.swift`.
 *
 * The third branch iOS has, the quick start, is not ported yet: it asks for a
 * sport and a squad number and both are skippable, so leaving it out costs
 * nothing but a screen.
 *
 * The starting state matters. A stored token is spent on a real call before the
 * app believes in it, and until that answers neither branch is right — showing
 * the sign-in form to somebody who is signed in is the worse of the two, so
 * neither is shown.
 */
@Composable
fun RootScreen(
    viewModel: SessionViewModel,
    /// Reporting and blocking are not a feature of one screen, so they take
    /// the client directly rather than a view model each.
    api: com.fishers.app.net.FishersApi,
    chatList: com.fishers.app.chat.ChatListViewModel,
    threadFor: (String) -> com.fishers.app.chat.ChatThreadViewModel,
    fixtures: com.fishers.app.fixtures.FixturesViewModel,
    clubs: com.fishers.app.clubs.ClubsViewModel,
    clubDetailFor: (String) -> com.fishers.app.clubs.ClubDetailViewModel,
    home: com.fishers.app.home.HomeViewModel,
    umpiring: com.fishers.app.umpire.UmpireViewModel,
    pendingReviews: com.fishers.app.umpire.PendingUmpireReviewsViewModel,
    market: com.fishers.app.shop.MarketViewModel,
    listingFor: (String) -> com.fishers.app.shop.ListingViewModel,
    worldScores: com.fishers.app.scores.WorldScoresViewModel,
    worldMatchFor: (String) -> com.fishers.app.scores.WorldMatchViewModel,
    scoringFor: (String) -> com.fishers.app.cricket.ScoringViewModel,
    season: com.fishers.app.season.SeasonViewModel,
    /** A tapped notification's destination; held until somebody is signed in to see it. */
    seasonLink: com.fishers.app.season.SeasonLink? = null,
    onSeasonLinkHandled: () -> Unit = {},
    /** A screen to open once signed in — an invite link the app was opened with. */
    pendingRoute: com.fishers.app.views.nav.Route? = null,
    /** The invite link the app was opened with, shown on the sign-in form. */
    inviteToken: String? = null,
    onPendingRouteHandled: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { viewModel.bootstrap() }

    AnimatedContent(
        targetState = when {
            state.isStarting -> Destination.Starting
            state.isAuthenticated -> Destination.SignedIn
            else -> Destination.Auth
        },
        transitionSpec = {
            fadeIn(tween(250)) togetherWith fadeOut(tween(250))
        },
        label = "root",
        modifier = modifier.fillMaxSize(),
    ) { destination ->
        when (destination) {
            Destination.Starting -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                CircularProgressIndicator()
            }

            Destination.Auth -> {
                val googleClientId by viewModel.googleClientId.collectAsStateWithLifecycle()
                // An Activity context: the account chooser is a sheet over it.
                val context = LocalContext.current
                val scope = rememberCoroutineScope()
                LaunchedEffect(Unit) { viewModel.loadGoogle() }
                val deps = com.fishers.app.views.nav.LocalAppDeps.current
                val invite by androidx.compose.runtime.produceState<com.fishers.app.clubs.InvitePreview?>(null, inviteToken) {
                    value = inviteToken?.let { token ->
                        runCatching { deps.service<com.fishers.app.net.ClubsApi>().invitePreview(token) }.getOrNull()
                    }
                }

                AuthScreen(
                    state = state,
                    onSignIn = viewModel::signIn,
                    onSignUp = viewModel::signUp,
                    googleEnabled = googleClientId != null,
                    invitedTo = invite?.let { it.clubName ?: it.teamName ?: it.eventTitle },
                    invitedBy = invite?.invitedByName,
                    onGoogle = {
                        googleClientId?.let { clientId ->
                            scope.launch {
                                when (val result = requestGoogleIdToken(context, clientId)) {
                                    is GoogleResult.Token -> viewModel.signInWithGoogle(result.idToken)
                                    GoogleResult.Cancelled -> Unit
                                    GoogleResult.NoAccount -> viewModel.googleFailed(t("goo.no_account"))
                                    GoogleResult.Failed -> viewModel.googleFailed(t("rest.could_not_present_google"))
                                }
                            }
                        }
                    },
                )
            }

            Destination.SignedIn -> com.fishers.app.views.onboarding.SignedInGate { MainTabScreen(
                api = api,
                user = state.user,
                onSignOut = viewModel::signOut,
                onDeleteAccount = viewModel::deleteAccount,
                chatList = chatList,
                threadFor = threadFor,
                fixtures = fixtures,
                clubs = clubs,
                clubDetailFor = clubDetailFor,
                home = home,
                umpiring = umpiring,
                pendingReviews = pendingReviews,
                market = market,
                listingFor = listingFor,
                worldScores = worldScores,
                worldMatchFor = worldMatchFor,
                scoringFor = scoringFor,
                season = season,
                seasonLink = seasonLink,
                onSeasonLinkHandled = onSeasonLinkHandled,
                pendingRoute = pendingRoute,
                onPendingRouteHandled = onPendingRouteHandled,
            ) }
        }
    }
}

private enum class Destination { Starting, Auth, SignedIn }
