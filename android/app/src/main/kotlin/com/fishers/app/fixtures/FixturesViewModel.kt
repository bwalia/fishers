package com.fishers.app.fixtures

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.net.FishersApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant

data class FixturesState(
    val upcoming: List<FishersEvent> = emptyList(),
    val past: List<FishersEvent> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val isFirstLoad: Boolean = true,
    /** Which fixture is mid-RSVP, so only its own buttons go quiet. */
    val answering: String? = null,
)

class FixturesViewModel(private val api: FishersApi) : ViewModel() {

    private val _state = MutableStateFlow(FixturesState())
    val state: StateFlow<FixturesState> = _state.asStateFlow()

    fun load(now: Instant = Instant.now()) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { api.myFixtures() }
                .onSuccess { events ->
                    val (ahead, behind) = events.partition { it.isUpcoming(now) }
                    _state.value = FixturesState(
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
}
