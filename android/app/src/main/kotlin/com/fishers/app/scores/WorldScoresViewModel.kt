package com.fishers.app.scores

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.net.FishersApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

data class WorldScoresState(
    val scores: WorldScores? = null,
    val isLoading: Boolean = false,
    val error: String? = null,
    val isFirstLoad: Boolean = true,
)

/**
 * Scores from the wider game.
 *
 * Read from our own API, which reads the score provider on a budget of a
 * hundred requests a day for the whole deployment. Polling here therefore
 * costs a database query and never one of those requests — which is why it is
 * safe to keep the screen refreshing while somebody watches.
 */
class WorldScoresViewModel(private val api: FishersApi) : ViewModel() {

    private val _state = MutableStateFlow(WorldScoresState())
    val state: StateFlow<WorldScoresState> = _state.asStateFlow()

    private var polling: Job? = null

    fun load() {
        viewModelScope.launch { fetch() }
    }

    /**
     * Keep the screen current while it is open. The server refreshes from the
     * feed every few minutes at best, so asking more often than this would
     * only be told the same thing again.
     */
    fun startPolling() {
        if (polling?.isActive == true) return
        polling = viewModelScope.launch {
            fetch()
            while (isActive) {
                delay(120_000)
                fetch()
            }
        }
    }

    fun stopPolling() {
        polling?.cancel()
        polling = null
    }

    override fun onCleared() {
        stopPolling()
        super.onCleared()
    }

    private suspend fun fetch() {
        _state.value = _state.value.copy(isLoading = true)
        runCatching { api.worldScores() }
            .onSuccess {
                _state.value = WorldScoresState(scores = it, isLoading = false, isFirstLoad = false)
            }
            .onFailure { failure ->
                // Keep whatever is on screen: a momentary failure should not
                // blank a score somebody is reading.
                _state.value = _state.value.copy(
                    isLoading = false,
                    isFirstLoad = false,
                    error = if (_state.value.scores == null) readableError(failure) else null,
                )
            }
    }
}

data class WorldMatchState(
    val view: WorldMatchDetailView? = null,
    val isLoading: Boolean = false,
    val error: String? = null,
    val isFirstLoad: Boolean = true,
    /**
     * Which innings is open. Null until the card arrives, then the latest — what
     * is happening now is what somebody came to see, not the first day.
     */
    val tab: Int? = null,
)

/**
 * One match in full.
 *
 * Polls only while the match is actually being played: this is the one screen
 * that costs the server a request per match, and a finished card is never worth
 * asking for twice.
 */
class WorldMatchViewModel(
    private val api: FishersApi,
    private val matchId: String,
) : ViewModel() {

    private val _state = MutableStateFlow(WorldMatchState())
    val state: StateFlow<WorldMatchState> = _state.asStateFlow()

    private var polling: Job? = null

    fun openTab(index: Int) {
        _state.value = _state.value.copy(tab = index)
    }

    fun start() {
        if (polling?.isActive == true) return
        polling = viewModelScope.launch {
            fetch()
            while (isActive && _state.value.view?.summary?.isLive == true) {
                delay(120_000)
                fetch()
            }
        }
    }

    fun stop() {
        polling?.cancel()
        polling = null
    }

    override fun onCleared() {
        stop()
        super.onCleared()
    }

    private suspend fun fetch() {
        _state.value = _state.value.copy(isLoading = true)
        runCatching { api.worldMatch(matchId) }
            .onSuccess { next ->
                val count = next.detail?.innings?.size ?: 0
                val current = _state.value.tab
                // A refresh must not throw somebody back to the innings they
                // were not reading — only a first load picks for them.
                val tab = when {
                    count == 0 -> null
                    current == null || current >= count -> count - 1
                    else -> current
                }
                _state.value = WorldMatchState(
                    view = next, isLoading = false, isFirstLoad = false, tab = tab,
                )
            }
            .onFailure { failure ->
                _state.value = _state.value.copy(
                    isLoading = false,
                    isFirstLoad = false,
                    error = if (_state.value.view == null) readableError(failure) else null,
                )
            }
    }
}
