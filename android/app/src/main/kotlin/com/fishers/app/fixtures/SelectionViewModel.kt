package com.fishers.app.fixtures

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.i18n.t
import com.fishers.app.net.FixturesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SelectionUiState(
    val board: SelectionBoard? = null,
    val proposal: SquadProposal? = null,
    /** The side as the captain has it now, in the order they were picked. */
    val selected: List<String> = emptyList(),
    val reserves: List<String> = emptyList(),
    val isLoading: Boolean = true,
    /** The ranking or the assistant is working out a side. */
    val isThinking: Boolean = false,
    val isSaving: Boolean = false,
    val isPublishing: Boolean = false,
    val error: String? = null,
    val message: String? = null,
) {
    val squadSize: Int get() = board?.requirements?.size ?: 11
    val isFull: Boolean get() = selected.size >= squadSize

    /** Everyone still to choose from, best first by the ranking. Not anybody who said no. */
    val pool: List<SelectionCandidate>
        get() {
            val board = board ?: return emptyList()
            val order = board.ranked.withIndex().associate { (i, r) -> r.userId to i }
            return board.candidates
                .filter { it.userId !in selected && it.userId !in reserves && !it.ruledOut }
                .sortedBy { order[it.userId] ?: Int.MAX_VALUE }
        }

    val saidNo: List<SelectionCandidate>
        get() = board?.candidates.orEmpty()
            .filter { it.ruledOut && it.userId !in selected && it.userId !in reserves }

    fun role(userId: String): SelectionState? = when (userId) {
        in selected -> SelectionState.Selected
        in reserves -> SelectionState.Reserve
        else -> null
    }
}

/**
 * The captain's screen — `SelectionStore.swift`: who is available, what the
 * ranking (or the assistant) would pick and why, then save or publish.
 *
 * Nothing goes out until the captain says so. A suggestion fills the list for
 * them to change; only Publish tells the players.
 */
class SelectionViewModel(
    private val api: FixturesApi,
    private val eventId: String,
) : ViewModel() {

    private val _state = MutableStateFlow(SelectionUiState())
    val state: StateFlow<SelectionUiState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { api.selectionBoard(eventId) }
                .onSuccess { show(it) }
                .onFailure {
                    _state.value = _state.value.copy(isLoading = false, error = fixtureError(it))
                }
        }
    }

    /** Start from whatever is already decided. */
    private fun show(board: SelectionBoard, message: String? = null) {
        _state.value = _state.value.copy(
            board = board,
            selected = board.candidates.filter { it.state.isInSquad }.map { it.userId },
            reserves = board.candidates.filter { it.state == SelectionState.Reserve }.map { it.userId },
            isLoading = false,
            message = message,
        )
    }

    /** The deterministic ranking — always there, needs nothing configured. */
    fun suggest() = propose { api.suggestSquad(eventId) }

    /** The assistant. The server falls back to the ranking when it has no key. */
    fun askAssistant() = propose { api.assistantSquad(eventId) }

    private fun propose(work: suspend () -> SquadProposal) {
        if (_state.value.isThinking) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isThinking = true, error = null, message = null)
            runCatching { work() }
                .onSuccess { proposal ->
                    _state.value = _state.value.copy(
                        proposal = proposal,
                        selected = proposal.selected.map { it.userId },
                        reserves = proposal.reserves.map { it.userId },
                        isThinking = false,
                    )
                    // The assistant may publish on its own when the club allows it.
                    if (proposal.published) load()
                }
                .onFailure {
                    _state.value = _state.value.copy(isThinking = false, error = fixtureError(it))
                }
        }
    }

    /**
     * Tap to pick. In the side → out. A reserve → out. From the pool: into the
     * side, or onto the reserves once the side is full.
     */
    fun toggle(userId: String) {
        val s = _state.value
        _state.value = when (userId) {
            in s.selected -> s.copy(selected = s.selected - userId)
            in s.reserves -> s.copy(reserves = s.reserves - userId)
            else -> if (s.isFull) s.copy(reserves = s.reserves + userId) else s.copy(selected = s.selected + userId)
        }
    }

    /** Keep it, without telling anybody yet. */
    fun saveDraft() = commit(publish = false)

    /** Tell the squad. The server posts to the club thread and pushes each player. */
    fun publish() = commit(publish = true)

    private fun commit(publish: Boolean) {
        val s = _state.value
        if (s.isSaving || s.isPublishing) return
        if (publish && s.selected.isEmpty()) return
        val body = SetSquadBody(
            selected = s.selected,
            reserves = s.reserves,
            announcement = if (publish) s.proposal?.announcement else null,
            publish = publish,
        )
        viewModelScope.launch {
            _state.value = _state.value.copy(
                isSaving = !publish, isPublishing = publish, error = null, message = null,
            )
            runCatching { api.setSquad(eventId, body) }
                .onSuccess { board ->
                    _state.value = _state.value.copy(
                        isSaving = false, isPublishing = false,
                        proposal = if (publish) null else _state.value.proposal,
                    )
                    show(
                        board,
                        if (publish) t("ld.squad_announced_everybody_picked_has_b") else t("ld.saved_as_a_draft"),
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        isSaving = false, isPublishing = false, error = fixtureError(it),
                    )
                }
        }
    }

    /** Somebody dropped out: fill the gap from the reserves, in the order they were picked. */
    fun promoteReserves() {
        viewModelScope.launch {
            _state.value = _state.value.copy(error = null, message = null)
            runCatching { api.promoteReserves(eventId) }
                .onSuccess {
                    runCatching { api.selectionBoard(eventId) }
                        .onSuccess { show(it, t("ld.reserves_moved_up")) }
                }
                .onFailure { _state.value = _state.value.copy(error = fixtureError(it)) }
        }
    }
}
