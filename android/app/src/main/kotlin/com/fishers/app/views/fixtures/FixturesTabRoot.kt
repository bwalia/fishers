package com.fishers.app.views.fixtures

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.cricket.ScoringViewModel
import com.fishers.app.fixtures.FixturesViewModel
import com.fishers.app.views.cricket.ScoringScreen

/** The Fixtures tab. Owned by the fixtures area. */
@Composable
fun FixturesTabRoot(
    fixtures: FixturesViewModel,
    scoringFor: (String) -> ScoringViewModel,
) {
    var openFixture by rememberSaveable { mutableStateOf<String?>(null) }
    val fixtureId = openFixture
    if (fixtureId == null) {
        val state by fixtures.state.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) { fixtures.load() }
        FixturesScreen(
            state = state,
            onAnswer = fixtures::answer,
            onOpen = { openFixture = it.id },
        )
    } else {
        BackHandler { openFixture = null }
        val model = remember(fixtureId) { scoringFor(fixtureId) }
        val state by model.state.collectAsStateWithLifecycle()
        LaunchedEffect(fixtureId) { model.load() }
        ScoringScreen(
            state = state,
            onRuns = model::runs,
            onExtra = { model.extra(it) },
            onUndo = model::undo,
        )
    }
}
