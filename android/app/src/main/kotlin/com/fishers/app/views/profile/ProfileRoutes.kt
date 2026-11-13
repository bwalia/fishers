package com.fishers.app.views.profile

import androidx.compose.runtime.Composable
import com.fishers.app.views.nav.NotBuiltYet
import com.fishers.app.views.nav.Route

// The profile area: your own page, editing it, and other people's.

/** Edit your profile — the same fields as first-run setup. `ProfileEditView.swift`. */
class EditProfileRoute : Route {
    @Composable override fun Content() = NotBuiltYet("Edit profile")
}

/** Somebody else's record. `PlayerProfileView.swift`. */
data class PlayerProfileRoute(val userId: String, val name: String = "") : Route {
    @Composable override fun Content() = NotBuiltYet(name.ifBlank { "Player" })
}
