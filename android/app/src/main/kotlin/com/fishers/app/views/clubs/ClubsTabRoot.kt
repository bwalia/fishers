package com.fishers.app.views.clubs

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.clubs.ClubDetailViewModel
import com.fishers.app.clubs.ClubsViewModel
import com.fishers.app.season.SeasonLink
import com.fishers.app.season.SeasonTab
import com.fishers.app.season.SeasonViewModel
import com.fishers.app.views.season.SeasonPage

/** The Clubs tab: the list, one club's roster, or a club's season. Owned by the clubs area. */
@Composable
fun ClubsTabRoot(
    clubs: ClubsViewModel,
    clubDetailFor: (String) -> ClubDetailViewModel,
    season: SeasonViewModel,
    meId: String?,
    onOpenFixturesTab: () -> Unit,
) {
    var openClub by rememberSaveable { mutableStateOf<String?>(null) }
    var openClubName by rememberSaveable { mutableStateOf("") }
    var clubSeasonOpen by rememberSaveable { mutableStateOf(false) }

    when {
        clubSeasonOpen -> {
            BackHandler { clubSeasonOpen = false }
            SeasonPage(
                season = season,
                meId = meId,
                onOpenFixtures = { clubSeasonOpen = false; onOpenFixturesTab() },
                onOpenClubs = { clubSeasonOpen = false; openClub = null },
            )
        }
        openClub == null -> {
            val state by clubs.state.collectAsStateWithLifecycle()
            LaunchedEffect(Unit) { clubs.load() }
            ClubsScreen(state = state, onOpen = { openClub = it.id; openClubName = it.name })
        }
        else -> {
            val clubId = openClub!!
            val model = remember(clubId) { clubDetailFor(clubId) }
            val state by model.state.collectAsStateWithLifecycle()
            LaunchedEffect(clubId) { model.load() }
            BackHandler { openClub = null }
            ClubDetailScreen(
                clubName = openClubName,
                state = state,
                onOpenSeason = {
                    season.open(SeasonLink(tab = SeasonTab.Club, clubId = clubId))
                    clubSeasonOpen = true
                },
                onMakeLink = model::makeJoinLink,
                onStopLink = model::stopJoinLink,
            )
        }
    }
}
