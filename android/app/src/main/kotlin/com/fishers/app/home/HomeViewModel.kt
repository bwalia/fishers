package com.fishers.app.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.fixtures.MyFixture
import com.fishers.app.net.FishersApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.IOException
import java.time.Instant

data class HomeState(
    /** The next fixture that has not been called off. */
    val next: MyFixture? = null,
    /** The fixtures could not be read — "nothing in the diary" would be a guess. */
    val fixturesFailed: Boolean = false,
    /** Null when the chats could not be read: unknown, not none. */
    val unreadChats: Long? = 0,
    /** Null when the clubs could not be read: unknown, not "you're not in a club". */
    val clubCount: Int? = 0,
    val isLoading: Boolean = false,
    val error: String? = null,
    val isFirstLoad: Boolean = true,
    /** No signal: the matches on this phone are offered, one tap from carrying on. */
    val offline: Boolean = false,
)

/**
 * The overview — a reduced `HomeFeedView.swift`.
 *
 * What is here is what somebody opening the app wants inside a second: the
 * next game, whether anybody is waiting on a reply, and how many clubs they
 * are in. The getting-started guide, the live-fixture row, notifications and
 * the profile-completeness nudge are not ported yet; each is its own screen
 * with its own rules and is better done properly than sketched.
 */
class HomeViewModel(private val api: FishersApi) : ViewModel() {

    private val _state = MutableStateFlow(HomeState())
    val state: StateFlow<HomeState> = _state.asStateFlow()

    fun load(now: Instant = Instant.now()) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)

            // Three calls at once. Serially this is three round trips on a
            // phone at a ground, which is the difference between an overview
            // and a wait.
            val fixtures = async { runCatching { api.myFixtures() } }
            val chats = async { runCatching { api.conversations() } }
            val clubs = async { runCatching { api.myClubs() } }

            val f = fixtures.await()
            val c = chats.await()
            val cl = clubs.await()

            // Each tile stands on its own. One endpoint being down should cost
            // its own tile and nothing else — an overview that goes blank
            // because the chat service is unhappy is worse than one tile short.
            // A tile that could not load says so: "you're not in a club yet"
            // to a secretary with no signal is a wrong fact, not a gap.
            _state.value = HomeState(
                next = f.getOrNull()
                    ?.filter { it.isUpcoming(now) && !it.isOff }
                    ?.minByOrNull { it.startsAt ?: Instant.MAX },
                fixturesFailed = f.isFailure,
                unreadChats = c.getOrNull()?.sumOf { it.unreadCount },
                clubCount = cl.getOrNull()?.size,
                offline = listOf(f, c, cl).any { it.exceptionOrNull() is IOException },
                isFirstLoad = false,
                // Only worth saying when everything failed: one tile missing
                // explains itself by being missing.
                error = if (f.isFailure && c.isFailure && cl.isFailure) {
                    readableError(f.exceptionOrNull()!!)
                } else {
                    null
                },
            )
        }
    }
}
