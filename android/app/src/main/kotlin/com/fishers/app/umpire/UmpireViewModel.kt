package com.fishers.app.umpire

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.net.FishersApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class UmpiringState(
    val profile: UmpireProfile? = null,
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val error: String? = null,
)

/**
 * Somebody's umpiring record.
 *
 * `userId` null means "mine", which is the only version that can change
 * anything — the willingness switch and the note are the player's own.
 */
class UmpireViewModel(
    private val api: FishersApi,
    private val userId: String? = null,
) : ViewModel() {

    private val _state = MutableStateFlow(UmpiringState())
    val state: StateFlow<UmpiringState> = _state.asStateFlow()

    val isMine: Boolean get() = userId == null

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { if (isMine) api.myUmpiring() else api.umpiringOf(userId!!) }
                .onSuccess { _state.value = UmpiringState(profile = it) }
                .onFailure {
                    _state.value = _state.value.copy(isLoading = false, error = readableError(it))
                }
        }
    }

    fun setWilling(umpires: Boolean) = patch(UmpiringPatch(umpires = umpires))

    fun setNote(note: String) = patch(UmpiringPatch(note = note.trim().ifEmpty { null }))

    private fun patch(body: UmpiringPatch) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true, error = null)
            runCatching { api.setUmpiring(body) }
                .onSuccess { _state.value = UmpiringState(profile = it) }
                .onFailure {
                    _state.value = _state.value.copy(isSaving = false, error = readableError(it))
                }
        }
    }
}

data class PendingReviewsState(
    val matches: List<PendingUmpireReview> = emptyList(),
    val savingFor: String? = null,
    val error: String? = null,
)

/**
 * The matches waiting on this player's say.
 *
 * Android has no match screen in its navigation yet, so this is how a review
 * is reached at all here — and it is the better way on every platform: the app
 * asks, rather than the player going to find three Sundays' worth of matches.
 */
class PendingUmpireReviewsViewModel(
    private val api: FishersApi,
) : ViewModel() {

    private val _state = MutableStateFlow(PendingReviewsState())
    val state: StateFlow<PendingReviewsState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            // A profile that cannot load this is a profile, not an error screen.
            runCatching { api.pendingUmpireReviews() }
                .onSuccess { _state.value = PendingReviewsState(matches = it) }
                .onFailure { _state.value = PendingReviewsState() }
        }
    }

    fun review(matchId: String, umpireId: String, rating: Int, comment: String?) {
        viewModelScope.launch {
            _state.value = _state.value.copy(savingFor = umpireId, error = null)
            runCatching {
                api.reviewUmpire(matchId, umpireId, UmpireReviewBody(rating, comment?.trim()?.ifEmpty { null }))
            }
                .onSuccess { load() }
                .onFailure {
                    _state.value = _state.value.copy(savingFor = null, error = readableError(it))
                }
        }
    }
}

data class RateUmpiresState(
    val umpires: List<MatchUmpire> = emptyList(),
    val isLoading: Boolean = false,
    val savingFor: String? = null,
    val error: String? = null,
)

/** After the match: what the players thought of the umpiring. */
class RateUmpiresViewModel(
    private val api: FishersApi,
    private val matchId: String,
) : ViewModel() {

    private val _state = MutableStateFlow(RateUmpiresState())
    val state: StateFlow<RateUmpiresState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { api.matchUmpires(matchId) }
                .onSuccess { _state.value = RateUmpiresState(umpires = it) }
                .onFailure {
                    _state.value = _state.value.copy(isLoading = false, error = readableError(it))
                }
        }
    }

    fun review(umpireId: String, rating: Int, comment: String?) {
        viewModelScope.launch {
            _state.value = _state.value.copy(savingFor = umpireId, error = null)
            runCatching {
                api.reviewUmpire(matchId, umpireId, UmpireReviewBody(rating, comment?.trim()?.ifEmpty { null }))
            }
                .onSuccess { load() }
                .onFailure {
                    _state.value = _state.value.copy(savingFor = null, error = readableError(it))
                }
        }
    }

    fun withdraw(umpireId: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(savingFor = umpireId, error = null)
            runCatching { api.withdrawUmpireReview(matchId, umpireId) }
                .onSuccess { load() }
                .onFailure {
                    _state.value = _state.value.copy(savingFor = null, error = readableError(it))
                }
        }
    }
}
