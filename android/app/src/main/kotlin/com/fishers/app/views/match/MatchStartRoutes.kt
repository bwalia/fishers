package com.fishers.app.views.match

import androidx.compose.runtime.Composable
import com.fishers.app.views.nav.NotBuiltYet
import com.fishers.app.views.nav.Route

// Starting a match: the hub, the quick start, the setup wizard.
// Other areas push these; this area owns what they draw.

/** Every cricket fixture you can see — live, coming up, finished — and "Start a match now". `ScoreHubView.swift`. */
class ScoreHubRoute : Route {
    @Composable override fun Content() = NotBuiltYet("Score hub")
}

/** A quick match: your club (and team), the opposition, the kind — makes the fixture, then sets the match up. `ScoreHubView.swift`'s start sheet. */
data class StartMatchRoute(val clubId: String? = null) : Route {
    @Composable override fun Content() = NotBuiltYet("Start a match")
}

/** Overs, sides, toss, team sheets, openers — then the scorer. `CricketScoringFlowView.swift`. */
data class MatchSetupRoute(val eventId: String) : Route {
    @Composable override fun Content() = NotBuiltYet("Match setup")
}
