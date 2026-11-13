package com.fishers.app

import android.net.ConnectivityManager
import android.net.Network
import androidx.lifecycle.lifecycleScope
import com.fishers.app.cricket.BookSweeper
import com.fishers.app.cricket.DeviceId
import com.fishers.app.cricket.FileBallStore
import com.fishers.app.match.start.MatchRegistrar
import com.fishers.app.net.MatchStartApi
import com.fishers.app.net.ScoringApi
import com.fishers.app.session.UserCache
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

import androidx.compose.runtime.CompositionLocalProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.views.clubs.JoinByLinkRoute
import com.fishers.app.views.nav.AppDeps
import com.fishers.app.views.nav.LocalAppDeps

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.ui.Modifier
import androidx.compose.runtime.remember
import com.fishers.app.chat.ChatListViewModel
import com.fishers.app.chat.ChatThreadViewModel
import com.fishers.app.clubs.ClubDetailViewModel
import com.fishers.app.clubs.ClubsViewModel
import com.fishers.app.fixtures.FixturesViewModel
import com.fishers.app.umpire.PendingUmpireReviewsViewModel
import com.fishers.app.umpire.UmpireViewModel
import com.fishers.app.home.HomeViewModel
import com.fishers.app.session.SessionViewModel
import com.fishers.app.shop.ListingViewModel
import com.fishers.app.scores.WorldMatchViewModel
import com.fishers.app.scores.WorldScoresViewModel
import com.fishers.app.shop.MarketViewModel
import com.fishers.app.theme.FishersTheme
import com.fishers.app.views.RootScreen
import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.fishers.app.season.SeasonLink
import com.fishers.app.season.SeasonViewModel

class MainActivity : ComponentActivity() {
    /**
     * Where a tapped notification wants to go. When the app is not in the
     * foreground, FCM shows the notification itself and a tap launches this
     * activity with the message's `data` as string extras — so routing is
     * reading those, whichever component ends up receiving the push.
     */
    private var seasonLink by mutableStateOf<SeasonLink?>(null)

    /** An invite link the app was opened with (`/invite/{token}`), until it has been shown. */
    private var inviteToken by mutableStateOf<String?>(null)

    /**
     * Balls scored with no signal, from a match nobody has reopened, go up
     * whenever the app comes back to the front — `CricketSyncService.swift`'s
     * sweep. The scorer sends its own match's balls; this is everything else.
     * A match started with no signal is made on the server first.
     */
    override fun onResume() {
        super.onResume()
        sweep()
    }

    /** One sweep at a time: the resume and the network coming back often arrive together. */
    private val sweeping = AtomicBoolean(false)

    private fun sweep() {
        val app = application as FishersApp
        if (!app.session.isSignedIn || !sweeping.compareAndSet(false, true)) return
        lifecycleScope.launch {
            try {
                runCatching {
                    val store = FileBallStore.forApp(this@MainActivity)
                    val deviceId = DeviceId.get(this@MainActivity)
                    BookSweeper(
                        api = app.network.service(ScoringApi::class.java),
                        store = store,
                        deviceId = deviceId,
                        registrar = MatchRegistrar(app.network.service(MatchStartApi::class.java), store, deviceId),
                    ).sendLeftovers()
                }
            } finally {
                sweeping.set(false)
            }
        }
    }

    /**
     * The signal coming back at the ground, while the app is open on some
     * other screen: what is waiting goes up then, not at the next resume.
     */
    private val networkBack = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = sweep()
    }

    override fun onStart() {
        super.onStart()
        runCatching { getSystemService(ConnectivityManager::class.java)?.registerDefaultNetworkCallback(networkBack) }
    }

    override fun onStop() {
        runCatching { getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(networkBack) }
        super.onStop()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        linkFrom(intent)?.let { seasonLink = it }
        inviteTokenFrom(intent)?.let { inviteToken = it }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Not on a recreation: the tap was handled the first time round, and
        // rotating the phone should not throw somebody back to the stats.
        if (savedInstanceState == null) {
            seasonLink = linkFrom(intent)
            inviteToken = inviteTokenFrom(intent)
        }
        val app = application as FishersApp

        setContent {
            FishersTheme {
                val model: SessionViewModel = viewModel(
                    factory = object : ViewModelProvider.Factory {
                        @Suppress("UNCHECKED_CAST")
                        override fun <T : ViewModel> create(modelClass: Class<T>): T =
                            SessionViewModel(app.network.api, app.session, UserCache.prefs(app)) as T
                    },
                )
                val session by model.state.collectAsStateWithLifecycle()
                val deps = remember {
                    AppDeps(
                        network = app.network,
                        config = app.config,
                        user = { model.state.value.user },
                        reloadUser = model::reloadUser,
                        setUser = model::setUser,
                    )
                }
                Scaffold(modifier = Modifier.fillMaxSize()) { inner ->
                  CompositionLocalProvider(LocalAppDeps provides deps) {
                    RootScreen(
                        viewModel = model,
                        api = app.network.api,
                        chatList = remember { ChatListViewModel(app.network.api) },
                        threadFor = { id -> ChatThreadViewModel(app.network.api, id) },
                        fixtures = remember { FixturesViewModel(app.network.api) },
                        clubs = remember { ClubsViewModel(app.network.api) },
                        clubDetailFor = { id -> ClubDetailViewModel(app.network.api, id, app.config.apiBaseUrl) },
                        home = remember { HomeViewModel(app.network.api) },
                        umpiring = remember { UmpireViewModel(app.network.api) },
                        pendingReviews = remember {
                            PendingUmpireReviewsViewModel(app.network.api)
                        },
                        market = remember { MarketViewModel(app.network.api) },
                        worldScores = remember { WorldScoresViewModel(app.network.api) },
                        worldMatchFor = { id -> WorldMatchViewModel(app.network.api, id) },
                        scoringFor = { eventId ->
                            com.fishers.app.cricket.ScoringViewModel(app.network.api, eventId)
                        },
                        listingFor = { id -> ListingViewModel(app.network.api, id) },
                        season = remember { SeasonViewModel(app.network.api) },
                        seasonLink = seasonLink,
                        onSeasonLinkHandled = { seasonLink = null },
                        // Only once somebody is signed in to join with.
                        pendingRoute = inviteToken
                            ?.takeIf { session.isAuthenticated }
                            ?.let { JoinByLinkRoute(it) },
                        onPendingRouteHandled = { inviteToken = null },
                        modifier = Modifier.padding(inner),
                    )
                  }
                }
            }
        }
    }
}

/** `https://<site>/invite/<token>`, from an App Link; null for anything else. */
internal fun inviteTokenFrom(intent: Intent?): String? {
    val uri = intent?.data ?: return null
    val segments = uri.pathSegments
    return if (segments.size == 2 && segments[0] == "invite" && segments[1].isNotBlank()) segments[1] else null
}

/** `season_closed`, from a notification's extras; null for anything else. */
private fun linkFrom(intent: Intent?): SeasonLink? {
    val extras = intent?.extras ?: return null
    return SeasonLink.fromPush(
        url = extras.getString("url"),
        season = extras.getString("season"),
        clubId = extras.getString("club_id"),
    )
}
