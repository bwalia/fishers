@file:OptIn(ExperimentalMaterial3Api::class)

package com.fishers.app.views.match.scoring

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.fishers.app.cricket.ScorecardViewModel
import com.fishers.app.i18n.t
import com.fishers.app.net.ScoringApi
import com.fishers.app.views.match.ScoreMatchRoute
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator

/**
 * Following a match somebody else is scoring. `CricketScorecardView.swift`.
 *
 * The card is read again every ten seconds while this screen is open and the
 * app is in front — and not otherwise: leaving the screen, or putting the
 * phone away, cancels the loop.
 */
@Composable
internal fun ScorecardRouteContent(eventId: String) {
    val deps = LocalAppDeps.current
    val navigator = LocalNavigator.current
    val model = remember(eventId) { ScorecardViewModel(deps.service<ScoringApi>(), eventId) }
    val state by model.state.collectAsStateWithLifecycle()

    val lifecycle = LocalLifecycleOwner.current
    LaunchedEffect(model, lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { model.follow() }
    }

    val view = state.view
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        view?.let { "${it.homeName} v ${it.awayName}" } ?: t("ld.scorecard"),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = navigator::pop) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = t("sc.back"))
                    }
                },
            )
        },
    ) { inner ->
        Box(Modifier.padding(inner).fillMaxSize()) {
            when {
                view == null && state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
                view == null -> Text(
                    state.error ?: t("sc.no_scorecard_loaded"),
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(24.dp),
                )
                else -> ScorecardContent(view, dls = state.dls) {
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (view.status == "live") Banner(t("sc.live_caps"), BallColours.wicket)
                            if (state.stale) {
                                Text(
                                    t("rest.no_connection_check_signal"),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.error,
                                )
                            }
                            // The person holding the book may open this too —
                            // or anybody who may score, when nobody holds it.
                            val match = state.match
                            val me = deps.user()?.id
                            val theirs = match?.activeScorerUserId
                            if (match?.canScore == true && !view.isFinished && (theirs == null || theirs == me)) {
                                BigButton(t("sc.continue_scoring")) { navigator.replace(ScoreMatchRoute(eventId)) }
                            }
                        }
                    }
                }
            }
            MomentBanner(state.moment, state.momentCount, Modifier.align(Alignment.TopCenter))
        }
    }
}
