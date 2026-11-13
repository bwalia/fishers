package com.fishers.app.views.match

import androidx.compose.runtime.Composable
import com.fishers.app.views.match.scoring.ScoreMatchContent
import com.fishers.app.views.match.scoring.ScorecardRouteContent
import com.fishers.app.views.nav.Route

// Scoring a match and following one. Other areas push these.

/**
 * Ball-by-ball scoring. `LiveScorerView.swift`.
 *
 * Expects the match to exist on the fixture (`GET events/{id}/cricket-match`)
 * with its log through `innings_started` — the setup wizard's hand-over. It
 * copes with less: a match whose sheets are in but whose openers are not
 * offers the openers; one not set up at all sends the scorer to the setup.
 *
 * Or no server at all: [eventId] may be the id this phone gave a match it
 * started with no signal, and the scorer opens from the book on the phone.
 * Once the server has the match the book is filed under the server's id, and
 * this id still finds it.
 */
data class ScoreMatchRoute(val eventId: String) : Route {
    @Composable override fun Content() = ScoreMatchContent(eventId)
}

/** Following a match someone else is scoring. `CricketScorecardView.swift`. */
data class ScorecardRoute(val eventId: String) : Route {
    @Composable override fun Content() = ScorecardRouteContent(eventId)
}
