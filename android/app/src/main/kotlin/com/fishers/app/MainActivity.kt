package com.fishers.app

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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        linkFrom(intent)?.let { seasonLink = it }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Not on a recreation: the tap was handled the first time round, and
        // rotating the phone should not throw somebody back to the stats.
        if (savedInstanceState == null) seasonLink = linkFrom(intent)
        val app = application as FishersApp

        setContent {
            FishersTheme {
                val model: SessionViewModel = viewModel(
                    factory = object : ViewModelProvider.Factory {
                        @Suppress("UNCHECKED_CAST")
                        override fun <T : ViewModel> create(modelClass: Class<T>): T =
                            SessionViewModel(app.network.api, app.session) as T
                    },
                )
                Scaffold(modifier = Modifier.fillMaxSize()) { inner ->
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
                        modifier = Modifier.padding(inner),
                    )
                }
            }
        }
    }
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
