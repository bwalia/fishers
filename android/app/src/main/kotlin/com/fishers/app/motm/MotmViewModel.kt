package com.fishers.app.motm

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.net.FishersApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class MotmState(
    val poll: MotmPollView? = null,
    val isLoading: Boolean = false,
    val isVoting: Boolean = false,
    val error: String? = null,
)

class MotmViewModel(
    private val api: FishersApi,
    private val pollId: String,
) : ViewModel() {

    private val _state = MutableStateFlow(MotmState())
    val state: StateFlow<MotmState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { api.motmPoll(pollId) }
                .onSuccess { _state.value = MotmState(poll = it) }
                .onFailure {
                    _state.value = _state.value.copy(isLoading = false, error = readableError(it))
                }
        }
    }

    /**
     * Vote, or take it back by voting the same way twice.
     *
     * The server answers with the whole poll, including whether the tally is
     * now visible — so the screen is redrawn from what it said rather than
     * from a guess about what a vote should have done. Guessing is how a
     * client ends up showing a tally the server is still hiding.
     */
    fun vote(candidateUserId: String) {
        val poll = _state.value.poll ?: return
        if (!poll.votingAllowed() || _state.value.isVoting) return

        viewModelScope.launch {
            _state.value = _state.value.copy(isVoting = true, error = null)
            val withdrawing = poll.myVote == candidateUserId
            runCatching {
                if (withdrawing) api.withdrawMotmVote(pollId)
                else api.castMotmVote(pollId, CastMotmVoteRequest(candidateUserId))
            }
                .onSuccess { _state.value = MotmState(poll = it) }
                .onFailure {
                    _state.value = _state.value.copy(isVoting = false, error = readableError(it))
                }
        }
    }
}
