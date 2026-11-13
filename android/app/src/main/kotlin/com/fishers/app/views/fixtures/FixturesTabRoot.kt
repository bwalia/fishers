package com.fishers.app.views.fixtures

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.cricket.ScoringViewModel
import com.fishers.app.fixtures.FixturesViewModel
import com.fishers.app.net.FixturesApi
import com.fishers.app.views.match.ScoreHubRoute
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator

/**
 * The Fixtures tab. Owned by the fixtures area.
 *
 * A fixture opens its own page, which is where the match is set up, scored
 * and followed from — the list no longer drops straight into a scorer.
 */
@Composable
fun FixturesTabRoot(
    fixtures: FixturesViewModel,
    // ponytail: unused since the fixture page took over scoring; drop it here
    // and in MainTabScreen together.
    @Suppress("UNUSED_PARAMETER") scoringFor: (String) -> ScoringViewModel,
) {
    val nav = LocalNavigator.current
    val deps = LocalAppDeps.current
    val api = remember { deps.service<FixturesApi>() }
    val state by fixtures.state.collectAsStateWithLifecycle()
    // Every time the tab shows — coming back from scheduling or answering on a
    // fixture's own page included — so the list is never a step behind.
    LaunchedEffect(Unit) {
        fixtures.load()
        fixtures.loadHistory({ from, to -> api.myFixtures(from, to) })
        fixtures.loadSchedulable()
    }
    FixturesScreen(
        state = state,
        onAnswer = fixtures::answer,
        onOpen = { nav.push(FixtureRoute(it.id)) },
        onSchedule = { nav.push(CreateFixtureRoute()) },
        onScheduleNets = { nav.push(CreateFixtureRoute(nets = true)) },
        onOpenCalendar = { nav.push(AvailabilityCalendarRoute()) },
        onOpenScores = { nav.push(ScoreHubRoute()) },
    )
}
