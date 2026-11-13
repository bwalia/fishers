package com.fishers.app.fixtures

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.net.FishersApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

data class FixturesState(
    val upcoming: List<MyFixture> = emptyList(),
    val past: List<MyFixture> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val isFirstLoad: Boolean = true,
    /** Which fixture is mid-RSVP, so only its own buttons go quiet. */
    val answering: String? = null,
    /** Whether this person may put a match in any of their clubs' diaries. */
    val canSchedule: Boolean = false,
    /**
     * The last few months. The diary call behind [past] starts a day back, so
     * without this last Saturday's match — and the way to its scorecard — had
     * gone from the tab by Monday.
     */
    val history: List<MyFixture> = emptyList(),
) {
    /** Everything already played, most recent first, each fixture once. */
    val played: List<MyFixture>
        get() = (past + history.filterNot { old -> past.any { it.id == old.id } })
            .sortedByDescending { it.startsAt }
}

class FixturesViewModel(private val api: FishersApi) : ViewModel() {

    private val _state = MutableStateFlow(FixturesState())
    val state: StateFlow<FixturesState> = _state.asStateFlow()

    fun load(now: Instant = Instant.now()) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { api.myFixtures() }
                .onSuccess { events ->
                    val (ahead, behind) = events.partition { it.isUpcoming(now) }
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = null,
                        // Soonest first for what is coming — that is the one
                        // somebody is deciding about. Most recent first for
                        // what is done, which is what they are looking back at.
                        upcoming = ahead.sortedBy { it.startsAt },
                        past = behind.sortedByDescending { it.startsAt },
                        isFirstLoad = false,
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        isLoading = false, isFirstLoad = false, error = readableError(it),
                    )
                }
        }
    }

    /**
     * The last four months, as iOS's Past list has them. Asked through the
     * fixtures area's own client, which can say when from and to.
     */
    fun loadHistory(
        fetch: suspend (from: String, to: String) -> List<MyFixture>,
        now: Instant = Instant.now(),
    ) {
        viewModelScope.launch {
            runCatching { fetch(now.minus(HISTORY).toString(), now.toString()) }
                .onSuccess { found ->
                    _state.value = _state.value.copy(history = found.filterNot { it.isUpcoming(now) })
                }
        }
    }

    /**
     * Whether to offer "Schedule a match" — only somebody who can put one in a
     * club's diary sees it, as on iOS. Asked club by club; a club that will
     * not say is a club where you cannot.
     */
    fun loadSchedulable() {
        viewModelScope.launch {
            val clubs = runCatching { api.myClubs() }.getOrDefault(emptyList())
            val can = clubs.any { club ->
                runCatching { api.myClubRole(club.id) }.getOrNull()?.permissions?.contains("manage_events") == true
            }
            _state.value = _state.value.copy(canSchedule = can)
        }
    }

    /**
     * Answer a fixture.
     *
     * Shown straight away and reverted if the server refuses. This is the one
     * place optimism is right: the answer is this person's own, they already
     * know what they tapped, and a captain picking a side needs the list to
     * keep up. A message is different — there, what matters is whether the
     * other end got it.
     */
    fun answer(eventId: String, status: RsvpStatus) {
        val before = _state.value
        if (before.answering != null) return

        _state.value = before.copy(
            answering = eventId,
            upcoming = before.upcoming.map {
                if (it.id == eventId) it.copy(myRsvp = status) else it
            },
            error = null,
        )

        viewModelScope.launch {
            runCatching { api.rsvp(eventId, RsvpRequest(status)) }
                .onSuccess { _state.value = _state.value.copy(answering = null) }
                .onFailure {
                    // Put it back. An answer the server never took is worse
                    // than no answer: the captain counts them and is wrong.
                    _state.value = before.copy(answering = null, error = readableError(it))
                }
        }
    }

    private companion object {
        val HISTORY: Duration = Duration.ofDays(120)
    }
}
