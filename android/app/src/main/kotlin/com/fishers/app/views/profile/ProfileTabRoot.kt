package com.fishers.app.views.profile

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.i18n.Language
import com.fishers.app.i18n.Strings
import com.fishers.app.i18n.t
import com.fishers.app.net.FishersApi
import com.fishers.app.net.PublicUser
import com.fishers.app.season.SeasonLink
import com.fishers.app.season.SeasonTab
import com.fishers.app.season.SeasonViewModel
import com.fishers.app.umpire.PendingUmpireReviewsViewModel
import com.fishers.app.umpire.UmpireViewModel
import com.fishers.app.views.safety.BlockedListCard
import com.fishers.app.views.season.SeasonPage
import com.fishers.app.views.umpire.PendingUmpireReviewsCard
import com.fishers.app.views.umpire.UmpiringCard

/** The Profile tab. Owned by the profile area. */
@Composable
fun ProfileTabRoot(
    user: PublicUser?,
    api: FishersApi,
    season: SeasonViewModel,
    pendingReviews: PendingUmpireReviewsViewModel,
    umpiring: UmpireViewModel,
    /** Held by the tab screen, because a notification tap opens it from outside. */
    myGameOpen: Boolean,
    onMyGameOpen: (Boolean) -> Unit,
    onOpenFixturesTab: () -> Unit,
    onOpenClubsTab: () -> Unit,
    onSignOut: () -> Unit,
    onDeleteAccount: (password: String, onError: (String) -> Unit) -> Unit,
) {
    if (myGameOpen) {
        BackHandler { onMyGameOpen(false) }
        SeasonPage(
            season = season,
            meId = user?.id,
            onOpenFixtures = { onMyGameOpen(false); onOpenFixturesTab() },
            onOpenClubs = { onMyGameOpen(false); onOpenClubsTab() },
        )
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(user?.name ?: t("rest.signed_in"), style = MaterialTheme.typography.headlineSmall)
        user?.email?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }

        // The player's own season, first after their name: it is the part of
        // a profile somebody opens it to see.
        OutlinedButton(onClick = {
            season.open(SeasonLink(tab = SeasonTab.Mine))
            onMyGameOpen(true)
        }) { Text(t("ss.my_game")) }

        val pendingState by pendingReviews.state.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) { pendingReviews.load() }
        PendingUmpireReviewsCard(
            state = pendingState,
            onReview = { matchId, umpireId, rating, comment ->
                pendingReviews.review(matchId, umpireId, rating, comment)
                umpiring.load()
            },
        )

        val umpState by umpiring.state.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) { umpiring.load() }
        UmpiringCard(state = umpState, isMine = true, onWilling = umpiring::setWilling)

        BlockedListCard(api = api)

        LanguagePicker()

        TextButton(onClick = onSignOut) { Text(t("nav.sign_out")) }

        DeleteAccountCard(onDelete = onDeleteAccount)
    }
}

/**
 * Which language the app speaks.
 *
 * Each listed in its own script and never translated — a picker offering
 * "Punjabi" in English is no use to the person who needs it. Choosing one
 * redraws every screen: `t()` reads `Strings.language`, which is Compose
 * state, so the subscription is automatic.
 */
@Composable
fun LanguagePicker() {
    val context = LocalContext.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(t("lang.label"), style = MaterialTheme.typography.labelLarge)
        Language.entries.forEach { language ->
            FilterChip(
                selected = Strings.language == language,
                onClick = { Strings.set(context, language) },
                label = { Text(language.native) },
            )
        }
    }
}
