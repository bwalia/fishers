package com.fishers.app.views.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.R
import com.fishers.app.i18n.t
import com.fishers.app.net.ProfileApi
import com.fishers.app.profile.EditProfileViewModel
import com.fishers.app.profile.PlayerProfileViewModel
import com.fishers.app.profile.PlayerSeasonStats
import com.fishers.app.profile.figure
import com.fishers.app.safety.ReportSubjectKind
import com.fishers.app.umpire.UmpireViewModel
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator
import com.fishers.app.views.nav.Route
import com.fishers.app.views.safety.ReportOrBlock
import com.fishers.app.views.umpire.UmpiringCard

// The profile area: your own page, editing it, and other people's.

/** Edit your profile — `ProfileEditView.swift`. Saves to `PATCH /me` and closes. */
class EditProfileRoute : Route {
    @Composable
    override fun Content() {
        val deps = LocalAppDeps.current
        val nav = LocalNavigator.current
        val model = remember {
            EditProfileViewModel(deps.service<ProfileApi>()) { deps.setUser(it.toPublicUser()) }
        }
        val state by model.state.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) { model.load() }
        LaunchedEffect(state.saved) { if (state.saved) nav.pop() }

        val pickPhoto = rememberPhotoPicker(onBytes = model::uploadPhoto, onUnreadable = model::photoUnreadable)
        EditProfileScreen(
            state = state,
            onEdit = model::edit,
            onSave = model::save,
            onBack = nav::pop,
            onRetry = model::load,
            onPickPhoto = pickPhoto,
        )
    }
}

/**
 * Somebody else's record — `PlayerProfileView.swift`. The same figures as your
 * own page, worked out the same way; what is not here is their contact details.
 * [name] is shown while the real profile loads, so tapping a name in a list
 * does not open a blank screen.
 */
data class PlayerProfileRoute(val userId: String, val name: String = "") : Route {
    @Composable
    override fun Content() {
        val deps = LocalAppDeps.current
        val nav = LocalNavigator.current
        val model = remember { PlayerProfileViewModel(deps.service<ProfileApi>(), userId) }
        val umpiring = remember { UmpireViewModel(deps.api, userId) }
        val state by model.state.collectAsStateWithLifecycle()
        val umpState by umpiring.state.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) {
            model.load()
            umpiring.load()
        }

        val player = state.player
        val shownName = player?.name ?: name.ifBlank { t("cl.player_role") }
        val firstName = shownName.trim().split(" ").firstOrNull().orEmpty()

        Column(Modifier.fillMaxSize()) {
            RouteBar(shownName, onBack = nav::pop) {
                if (userId != deps.user()?.id) {
                    ReportOrBlock(
                        api = deps.api,
                        kind = ReportSubjectKind.USER,
                        subjectId = userId,
                        personId = userId,
                        personName = shownName,
                        onBlocked = { nav.pop() },
                    )
                }
            }
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                ProfileHero(
                    name = shownName,
                    avatarUrl = player?.avatarUrl,
                    club = player?.sharedClubs?.firstOrNull(),
                    main = player?.mainSport,
                    avatarSize = 76.dp,
                )

                state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }

                when {
                    state.isLoading -> Box(Modifier.fillMaxWidth(), Alignment.Center) { CircularProgressIndicator() }
                    state.error != null -> Unit
                    state.seasons.isEmpty() -> SectionCard(t("cl.nothing_scored_yet")) {
                        Text(
                            t(
                                "pf.figures_appear_when_scored",
                                vars = mapOf("name" to firstName, "brand" to stringResource(R.string.brand_name)),
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    else -> {
                        val totals = state.totals
                        SectionCard(t("cl.career")) {
                            FigureGrid(
                                listOf(
                                    "${totals.matches}" to t("rest.matches"),
                                    "${totals.runs}" to t("rest.runs"),
                                    figure(totals.battingAverage) to t("rest.average"),
                                    "${totals.wickets}" to t("rest.wickets"),
                                ),
                            )
                            OutlinedButton(
                                onClick = { nav.push(CareerStatsRoute(state.seasons)) },
                                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                            ) { Text(t("cl.season_stats")) }
                        }
                        SectionCard(t("cl.season_by_season")) {
                            state.seasons.forEach { SeasonRow(it, batting = true) }
                        }
                    }
                }

                if (state.honours.isNotEmpty()) {
                    SectionCard(t("rest.honours")) {
                        state.honours.forEach { award ->
                            Column {
                                Text(award.title, style = MaterialTheme.typography.titleSmall)
                                award.description?.let {
                                    Text(it, style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }

                player?.let { p -> p.sportProfiles.forEach { SportCard(it, isMain = it.sport == p.primarySport) } }

                if (player != null) UmpiringCard(state = umpState, isMine = false, onWilling = {}, theirName = shownName)

                player?.sharedClubs?.takeIf { it.isNotEmpty() }?.let { clubs ->
                    SectionCard(t("cl.you_both_play_for")) {
                        clubs.forEach { Text(it, style = MaterialTheme.typography.bodyMedium) }
                    }
                }
            }
        }
    }
}

/** Every season on record, batting or bowling — `CareerStatsView.swift`. */
data class CareerStatsRoute(val seasons: List<PlayerSeasonStats>) : Route {
    @Composable
    override fun Content() {
        val nav = LocalNavigator.current
        Column(Modifier.fillMaxSize()) {
            RouteBar(t("cl.career"), onBack = nav::pop)
            CareerStats(seasons)
        }
    }
}
