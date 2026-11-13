package com.fishers.app.views.match

import androidx.compose.runtime.Composable
import com.fishers.app.views.nav.NotBuiltYet
import com.fishers.app.views.nav.Route

// Scoring a match and following one. Other areas push these.

/** Ball-by-ball scoring. `LiveScorerView.swift`. */
data class ScoreMatchRoute(val eventId: String) : Route {
    @Composable override fun Content() = NotBuiltYet("Scorer")
}

/** Following a match someone else is scoring. `CricketScorecardView.swift`. */
data class ScorecardRoute(val eventId: String) : Route {
    @Composable override fun Content() = NotBuiltYet("Scorecard")
}
