package com.fishers.app.views

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.chat.ChatListViewModel
import com.fishers.app.chat.ChatThreadViewModel
import com.fishers.app.chat.ConversationSummary
import com.fishers.app.clubs.ClubDetailViewModel
import com.fishers.app.clubs.ClubsViewModel
import com.fishers.app.fixtures.FixturesViewModel
import com.fishers.app.home.HomeViewModel
import com.fishers.app.i18n.t
import com.fishers.app.net.FishersApi
import com.fishers.app.net.PublicUser
import com.fishers.app.scores.WorldMatchViewModel
import com.fishers.app.scores.WorldScoresViewModel
import com.fishers.app.season.SeasonLink
import com.fishers.app.season.SeasonViewModel
import com.fishers.app.shop.ListingViewModel
import com.fishers.app.shop.MarketViewModel
import com.fishers.app.umpire.PendingUmpireReviewsViewModel
import com.fishers.app.umpire.UmpireViewModel
import com.fishers.app.views.chat.ChatListScreen
import com.fishers.app.views.chat.ChatThreadScreen
import com.fishers.app.views.clubs.ClubsTabRoot
import com.fishers.app.views.fixtures.FixturesTabRoot
import com.fishers.app.views.home.HomeActions
import com.fishers.app.views.home.HomeScreen
import com.fishers.app.views.nav.LocalNavigator
import com.fishers.app.views.nav.Navigator
import com.fishers.app.views.nav.Route
import com.fishers.app.views.profile.ProfileTabRoot
import com.fishers.app.views.scores.WorldMatchScreen
import com.fishers.app.views.scores.WorldScoresScreen
import com.fishers.app.views.shop.ListingScreen
import com.fishers.app.views.shop.MarketplaceScreen

/**
 * The five top-level destinations, in the order `MainTabView.swift` has them,
 * with a stack of pushed screens over them ([Navigator]). Each tab's content
 * lives in its own area's file; Home and the shared plumbing live here.
 */
@Composable
fun MainTabScreen(
    user: PublicUser?,
    api: FishersApi,
    onSignOut: () -> Unit,
    onDeleteAccount: (password: String, onError: (String) -> Unit) -> Unit,
    chatList: ChatListViewModel,
    threadFor: (String) -> ChatThreadViewModel,
    fixtures: FixturesViewModel,
    clubs: ClubsViewModel,
    clubDetailFor: (String) -> ClubDetailViewModel,
    home: HomeViewModel,
    umpiring: UmpireViewModel,
    pendingReviews: PendingUmpireReviewsViewModel,
    market: MarketViewModel,
    listingFor: (String) -> ListingViewModel,
    worldScores: WorldScoresViewModel,
    worldMatchFor: (String) -> WorldMatchViewModel,
    scoringFor: (String) -> com.fishers.app.cricket.ScoringViewModel,
    season: SeasonViewModel,
    /** Where a tapped `season_closed` notification wants to land, until it has. */
    seasonLink: SeasonLink? = null,
    onSeasonLinkHandled: () -> Unit = {},
    /** An invite link the app was opened with, until it has been shown. */
    pendingRoute: Route? = null,
    onPendingRouteHandled: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    var tab by rememberSaveable { mutableStateOf(Tab.Home) }
    val navigator = remember { Navigator() }
    // Which thread is open, if any. Saved, so rotating the phone mid-sentence
    // does not throw you back to the list.
    var openThread by rememberSaveable { mutableStateOf<String?>(null) }
    var openTitle by rememberSaveable { mutableStateOf("") }
    // The shop is two screens deep off Home: the marketplace, then one listing.
    var shopOpen by rememberSaveable { mutableStateOf(false) }
    var openListing by rememberSaveable { mutableStateOf<String?>(null) }
    // The world scores, one screen deep off Home.
    var scoresOpen by rememberSaveable { mutableStateOf(false) }
    // Which match's scorecard is open, if any.
    var openWorldMatch by rememberSaveable { mutableStateOf<String?>(null) }
    // My game, off Profile. Held here because a notification tap opens it.
    var myGameOpen by rememberSaveable { mutableStateOf(false) }

    // A notification tap. Lands on My game for the season it is about, as the
    // website's /stats?season=&club= does; the club tab is one tap away.
    LaunchedEffect(seasonLink) {
        val link = seasonLink ?: return@LaunchedEffect
        navigator.popToRoot()
        tab = Tab.Profile
        myGameOpen = true
        season.open(link)
        onSeasonLinkHandled()
    }
    // An invite link: shown over whatever tab is open.
    LaunchedEffect(pendingRoute) {
        val route = pendingRoute ?: return@LaunchedEffect
        navigator.push(route)
        onPendingRouteHandled()
    }

    CompositionLocalProvider(LocalNavigator provides navigator) {
        Scaffold(
            modifier = modifier.fillMaxSize(),
            bottomBar = {
                NavigationBar {
                    Tab.entries.forEach { entry ->
                        NavigationBarItem(
                            selected = tab == entry,
                            onClick = {
                                navigator.popToRoot()
                                tab = entry
                            },
                            icon = { Icon(entry.icon, contentDescription = null) },
                            // Label as well as icon: an icon-only bar is a guessing
                            // game, and the Laws of this app are hard enough.
                            label = { Text(t(entry.titleKey)) },
                        )
                    }
                }
            },
        ) { inner ->
            Box(Modifier.fillMaxSize().padding(inner)) {
                val top = navigator.top
                if (top != null) {
                    BackHandler { navigator.pop() }
                    // Keyed, so two pushes of the same kind of screen do not share state.
                    key(navigator.stack.size, top) { top.Content() }
                    return@Box
                }
                when (tab) {
                    Tab.Home -> if (scoresOpen) {
                        BackHandler {
                            if (openWorldMatch != null) openWorldMatch = null else scoresOpen = false
                        }
                        val match = openWorldMatch
                        if (match == null) {
                            val state by worldScores.state.collectAsStateWithLifecycle()
                            // Polls our own API while the screen is open, which costs
                            // a query and never one of the feed's daily allowance.
                            LaunchedEffect(Unit) { worldScores.startPolling() }
                            DisposableEffect(Unit) { onDispose { worldScores.stopPolling() } }
                            WorldScoresScreen(state = state, onOpen = { openWorldMatch = it })
                        } else {
                            val model = remember(match) { worldMatchFor(match) }
                            val state by model.state.collectAsStateWithLifecycle()
                            LaunchedEffect(match) { model.start() }
                            DisposableEffect(match) { onDispose { model.stop() } }
                            WorldMatchScreen(state = state, onOpenTab = model::openTab)
                        }
                    } else if (shopOpen) {
                        ShopTab(
                            market = market,
                            api = api,
                            listingFor = listingFor,
                            openListing = openListing,
                            onOpen = { openListing = it },
                            onBack = { if (openListing != null) openListing = null else shopOpen = false },
                            onOpenThread = { id, title ->
                                openListing = null
                                shopOpen = false
                                openThread = id
                                openTitle = title
                                tab = Tab.Chats
                            },
                        )
                    } else {
                        val state by home.state.collectAsStateWithLifecycle()
                        LaunchedEffect(Unit) { home.load() }
                        HomeScreen(
                            name = user?.name,
                            state = state,
                            onOpenShop = { shopOpen = true },
                            onOpenScores = { scoresOpen = true },
                            actions = { HomeActions() },
                        )
                    }

                    Tab.Clubs -> ClubsTabRoot(
                        clubs = clubs,
                        clubDetailFor = clubDetailFor,
                        season = season,
                        meId = user?.id,
                        onOpenFixturesTab = { tab = Tab.Fixtures },
                    )

                    Tab.Fixtures -> FixturesTabRoot(fixtures = fixtures, scoringFor = scoringFor)

                    Tab.Chats -> ChatsTab(
                        api = api,
                        chatList = chatList,
                        threadFor = threadFor,
                        openThread = openThread,
                        openTitle = openTitle,
                        onOpen = { openThread = it.id; openTitle = it.title },
                        onBack = { openThread = null },
                    )

                    Tab.Profile -> ProfileTabRoot(
                        user = user,
                        api = api,
                        season = season,
                        pendingReviews = pendingReviews,
                        umpiring = umpiring,
                        myGameOpen = myGameOpen,
                        onMyGameOpen = { myGameOpen = it },
                        onOpenFixturesTab = { tab = Tab.Fixtures },
                        onOpenClubsTab = { tab = Tab.Clubs },
                        onSignOut = onSignOut,
                        onDeleteAccount = onDeleteAccount,
                    )
                }
            }
        }
    }
}

/**
 * Kit for sale, or one listing. Back steps out one screen at a time.
 *
 * Asking the seller about something hands off to the Chats tab rather than
 * opening a thread inside the shop: the conversation carries on there, and both
 * people already know where their messages live.
 */
@Composable
private fun ShopTab(
    market: MarketViewModel,
    api: FishersApi,
    listingFor: (String) -> ListingViewModel,
    openListing: String?,
    onOpen: (String) -> Unit,
    onBack: () -> Unit,
    onOpenThread: (String, String) -> Unit,
) {
    BackHandler(onBack = onBack)
    if (openListing == null) {
        val state by market.state.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) { market.load() }
        MarketplaceScreen(
            state = state,
            onSearch = market::search,
            onFilter = market::filter,
            onOpen = { onOpen(it.id) },
        )
    } else {
        val model = remember(openListing) { listingFor(openListing) }
        val state by model.state.collectAsStateWithLifecycle()
        LaunchedEffect(openListing) { model.load() }
        // Set once the enquiry has opened a thread; navigating clears it so
        // coming back does not re-open the same conversation.
        LaunchedEffect(state.openConversation) {
            state.openConversation?.let { conversation ->
                val title = state.listing?.let { "About: ${it.name}" } ?: t("rest.about_this_listing")
                model.conversationOpened()
                onOpenThread(conversation, title)
            }
        }
        ListingScreen(
            state = state,
            api = api,
            onReserve = model::reserve,
            onAsk = model::ask,
            onBlocked = onBack,
        )
    }
}

/**
 * The list, or a thread from it. Back closes the thread rather than the app —
 * the commonest reason somebody presses it here is to go and read another one.
 */
@Composable
private fun ChatsTab(
    api: FishersApi,
    chatList: ChatListViewModel,
    threadFor: (String) -> ChatThreadViewModel,
    openThread: String?,
    openTitle: String,
    onOpen: (ConversationSummary) -> Unit,
    onBack: () -> Unit,
) {
    if (openThread == null) {
        val state by chatList.state.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) { chatList.load() }
        ChatListScreen(state = state, onOpen = onOpen)
    } else {
        val model = remember(openThread) { threadFor(openThread) }
        val state by model.state.collectAsStateWithLifecycle()
        LaunchedEffect(openThread) { model.load() }
        BackHandler(onBack = onBack)
        ChatThreadScreen(
            title = openTitle,
            state = state,
            onSend = model::send,
            api = api,
            onBlocked = { model.dropMessagesFrom(it) },
        )
    }
}

private enum class Tab(val titleKey: String, val icon: ImageVector) {
    Home("nav.home", Icons.Filled.Home),
    Fixtures("nav.fixtures", Icons.Filled.DateRange),
    Chats("nav.chats", Icons.Filled.Email),
    Clubs("nav.clubs", Icons.Filled.Person),
    Profile("nav.profile", Icons.Filled.AccountCircle),
}
