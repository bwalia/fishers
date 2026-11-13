package com.fishers.app.views.fixtures

import androidx.compose.runtime.Composable
import com.fishers.app.views.nav.Route

// The fixtures area: making a fixture, its page, availability and selection.

/**
 * One fixture: when and where, who is available, the squad, and the match on it. `EventDetailView.swift`.
 * [notice] is said quietly at the top — "8 sessions scheduled", after a weekly series.
 */
data class FixtureRoute(val eventId: String, val notice: String? = null) : Route {
    @Composable override fun Content() = FixtureScreen(eventId, notice)
}

/**
 * A new fixture for one of your clubs. Becomes the fixture once it is saved.
 * [nets] opens it on nets rather than a match — "Schedule nets or practice".
 */
data class CreateFixtureRoute(val clubId: String? = null, val nets: Boolean = false) : Route {
    @Composable override fun Content() = CreateFixtureScreen(clubId, nets)
}

/** When you can play, and what you said to each fixture, a month at a time. `AvailabilityCalendarView.swift`. */
class AvailabilityCalendarRoute : Route {
    @Composable override fun Content() = AvailabilityCalendarScreen()
}
