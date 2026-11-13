package com.fishers.app.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.i18n.t
import com.fishers.app.net.ProfileApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class PlayerProfileState(
    val player: TeammateProfile? = null,
    /** Newest first. */
    val seasons: List<PlayerSeasonStats> = emptyList(),
    val honours: List<UserAchievement> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
) {
    val totals: Totals get() = Totals(seasons)
}

/**
 * Somebody else's record — `PlayerProfileView.swift`. The same figures as your
 * own page, worked out the same way. No contact details: the API does not send
 * them.
 */
class PlayerProfileViewModel(
    private val api: ProfileApi,
    private val userId: String,
) : ViewModel() {

    private val _state = MutableStateFlow(PlayerProfileState())
    val state: StateFlow<PlayerProfileState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            val player = runCatching { api.teammate(userId) }.getOrElse { failure ->
                // The server refuses anyone you share no club with ("not in a
                // shared club"); that reads better as the plain sentence.
                val api = ApiFailure.of(failure)
                val message = if (api.status == 403 || api.status == 404) {
                    t("sp.could_not_load_this_player")
                } else {
                    profileError(failure, api)
                }
                _state.update { it.copy(isLoading = false, error = message) }
                return@launch
            }
            // Neither is an error when empty: a new player has no figures and
            // no honours yet, and the screen says so.
            val seasons = runCatching { api.playerSeasons(userId) }.getOrDefault(emptyList())
            val honours = runCatching { api.playerAchievements(userId) }.getOrDefault(emptyList())
            _state.value = PlayerProfileState(
                player = player,
                seasons = seasons.sortedByDescending { it.seasonYear },
                honours = honours,
                isLoading = false,
            )
        }
    }
}
