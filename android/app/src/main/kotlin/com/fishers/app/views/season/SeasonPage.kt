package com.fishers.app.views.season

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.season.SeasonViewModel

/** Both tabs of the season page, wired to the one model they share. */
@Composable
fun SeasonPage(
    season: SeasonViewModel,
    meId: String?,
    onOpenFixtures: () -> Unit,
    onOpenClubs: () -> Unit,
) {
    val state by season.state.collectAsStateWithLifecycle()
    SeasonScreen(
        state = state,
        meId = meId,
        onTab = season::selectTab,
        onSeason = season::selectSeason,
        onClub = season::selectClub,
        onClose = season::close,
        onOpenFixtures = onOpenFixtures,
        onOpenClubs = onOpenClubs,
    )
}
