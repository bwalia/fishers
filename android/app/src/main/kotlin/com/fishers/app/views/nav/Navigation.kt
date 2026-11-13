package com.fishers.app.views.nav

import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.staticCompositionLocalOf
import com.fishers.app.config.AppConfig
import com.fishers.app.net.FishersApi
import com.fishers.app.net.Network
import com.fishers.app.net.PublicUser

/**
 * A screen pushed over the tabs. It draws itself, so a new screen is a new
 * class in its own area's file and touches no shared `when`.
 *
 * The tab bar stays underneath, as it does on iOS, where each tab owns a
 * navigation stack. Switching tab clears the stack.
 */
interface Route {
    @Composable
    fun Content()
}

/**
 * The stack of pushed screens. Back pops one; a tab tap clears it.
 *
 * ponytail: not saved across process death — a phone that kills the app while
 * a form is open reopens on the tab. Save the stack when somebody loses work
 * to it.
 */
class Navigator {
    val stack = mutableStateListOf<Route>()
    val top: Route? get() = stack.lastOrNull()

    fun push(route: Route) {
        stack.add(route)
    }

    fun pop() {
        stack.removeLastOrNull()
    }

    /** Swap the screen on top — a form that, once saved, becomes the thing it made. */
    fun replace(route: Route) {
        stack.removeLastOrNull()
        stack.add(route)
    }

    fun popToRoot() = stack.clear()
}

/**
 * What any screen may need, without threading it through every signature:
 * the client, the server address, and the signed-in person.
 *
 * Each area keeps its own Retrofit interface (`network.service(...)`) rather
 * than adding to [FishersApi], so areas built side by side do not collide in
 * one file.
 */
class AppDeps(
    val network: Network,
    val config: AppConfig,
    /** The signed-in person as last loaded. */
    val user: () -> PublicUser?,
    /** Re-read `/me` — after the profile, the photo or the role changed. */
    val reloadUser: () -> Unit,
    /** Hand back a user the server already returned, saving a round trip. */
    val setUser: (PublicUser) -> Unit,
) {
    val api: FishersApi get() = network.api

    /** The brand's website, which is where shared links open. */
    val webBase: String get() = config.apiBaseUrl.trimEnd('/')

    inline fun <reified T> service(): T = network.service(T::class.java)
}

val LocalNavigator = staticCompositionLocalOf<Navigator> { error("no Navigator provided") }
val LocalAppDeps = staticCompositionLocalOf<AppDeps> { error("no AppDeps provided") }
