package com.fishers.app.cricket

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.net.FishersApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import java.util.UUID

data class ScoringState(
    val match: CricketMatch? = null,
    val score: Scoreline? = null,
    val isLoading: Boolean = false,
    val isSending: Boolean = false,
    val error: String? = null,
    val isFirstLoad: Boolean = true,
) {
    val canScore: Boolean get() = match?.canScore == true && score?.isComplete == false
}

/**
 * Scoring a match.
 *
 * The log is the record; the state is a fold over it, done by the engine in
 * `backend/ffi` — the same Rust the server scores with. So a ball is checked
 * against the Laws *before* it is sent, and the screen updates from what the
 * engine said rather than from what the app assumed.
 *
 * That ordering is the whole design. It means a scorer at a ground with no
 * signal still gets told "nobody bowls two in a row" at the moment they tap,
 * rather than four overs later when the phone finds a bar.
 */
class ScoringViewModel(
    private val api: FishersApi,
    private val eventId: String,
    private val engine: Engine = Engine(),
    private val newId: () -> String = { UUID.randomUUID().toString() },
) : ViewModel() {

    private val _state = MutableStateFlow(ScoringState())
    val state: StateFlow<ScoringState> = _state.asStateFlow()

    /** The engine's own JSON, kept as it handed it back. */
    private var engineState: String? = null
    private var matchId: String? = null

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching {
                val match = api.cricketMatch(eventId)
                val log = api.scoringEvents(match.id)
                match to log
            }
                .onSuccess { (match, log) ->
                    matchId = match.id
                    engine.replay(log)
                        .onSuccess { state ->
                            engineState = state
                            _state.value = ScoringState(
                                match = match,
                                score = engine.scoreline(state),
                                isFirstLoad = false,
                            )
                        }
                        .onFailure {
                            // The log is the record. If it will not replay, the
                            // app must say so rather than draw a score it made
                            // up from the last event it happened to understand.
                            _state.value = ScoringState(
                                match = match,
                                isFirstLoad = false,
                                error = "This match's book would not replay: ${engine.reason(it)}",
                            )
                        }
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        isLoading = false, isFirstLoad = false, error = readableError(it),
                    )
                }
        }
    }

    fun runs(n: Int) = record(Events.delivery(n))
    fun extra(kind: String, runs: Int = 0) = record(Events.extra(kind, runs))
    fun undo() = record(Events.undo())

    /**
     * Apply locally first, and only send what the engine accepted.
     *
     * A ball the Laws refuse never reaches the server, so the scorer is told
     * at the moment they tap. And because the local fold is the server's own
     * code, an accepted ball is one the server will accept too — the two
     * cannot disagree about whether that was a wicket.
     */
    internal fun record(kind: JsonObject) {
        val current = engineState ?: return
        val id = matchId ?: return
        if (_state.value.isSending) return

        // Numbered from the engine's own state, not from the scoreline: a
        // match with no innings yet has no scoreline, and an event carrying a
        // sequence the log already holds is treated as a duplicate and skipped
        // — which would swallow every ball, silently.
        val event = ScoringEvent(
            clientEventId = newId(),
            seq = engine.lastSeq(current) + 1,
            kind = kind,
        )

        engine.apply(current, event)
            .onFailure {
                _state.value = _state.value.copy(error = engine.reason(it))
            }
            .onSuccess { next ->
                engineState = next
                _state.value = _state.value.copy(
                    score = engine.scoreline(next),
                    isSending = true,
                    error = null,
                )
                viewModelScope.launch {
                    runCatching { api.postScoringEvents(id, EventsBatch(events = listOf(event))) }
                        .onSuccess {
                            _state.value = _state.value.copy(match = it, isSending = false)
                        }
                        .onFailure {
                            // The ball stays on screen. It was legal — the
                            // engine said so — and the scorer is mid-over. What
                            // they need to know is that it has not gone up yet.
                            _state.value = _state.value.copy(
                                isSending = false,
                                error = "Not sent yet: ${readableError(it)}",
                            )
                        }
                }
            }
    }

    fun dismissError() {
        _state.value = _state.value.copy(error = null)
    }
}
