package com.fishers.app.views.fixtures

import androidx.compose.runtime.Composable
import com.fishers.app.views.nav.Route

// The fixtures area: making a fixture, its page, availability and selection.

/** One fixture: when and where, who is available, the squad, and the match on it. `EventDetailView.swift`. */
data class FixtureRoute(val eventId: String) : Route {
    @Composable override fun Content() = FixtureScreen(eventId)
}

/** A new fixture for one of your clubs. Becomes the fixture once it is saved. */
data class CreateFixtureRoute(val clubId: String? = null) : Route {
    @Composable override fun Content() = CreateFixtureScreen(clubId)
}

/** When you can play, and what you said to each fixture, a month at a time. `AvailabilityCalendarView.swift`. */
class AvailabilityCalendarRoute : Route {
    @Composable override fun Content() = AvailabilityCalendarScreen()
}
