package com.fishers.app.clubs

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.i18n.t
import com.fishers.app.net.ClubsApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Starting a club — `NewClubSheet` in `ClubsTeamsView.swift`. */
data class CreateClubState(
    val name: String = "",
    val sports: Set<String> = setOf("cricket"),
    /** What this deployment lets a club be started in; the whole list until it says. */
    val offered: List<String> = ALL_SPORTS,
    val isPublic: Boolean = false,
    val description: String = "",
    val isInformal: Boolean = false,
    val isSaving: Boolean = false,
    val error: String? = null,
    /** Refused because the account is not confirmed yet. */
    val needsVerifying: Boolean = false,
    /** Set once the server has made it: the screen becomes the club. */
    val created: Club? = null,
) {
    /** What is stopping the form, in words, or null when it can go. */
    val missing: String?
        get() = when {
            name.trim().length < 2 -> t("lc.give_the_club_a_name_to_continue")
            sports.isEmpty() -> t("lc.pick_at_least_one_sport")
            else -> null
        }

    val canSave: Boolean get() = missing == null && !isSaving
}

class CreateClubViewModel(private val api: ClubsApi) : ViewModel() {

    private val _state = MutableStateFlow(CreateClubState())
    val state: StateFlow<CreateClubState> = _state.asStateFlow()

    /**
     * Offer only what the server will accept. A cricket-only deployment that
     * offered football would let somebody fill the form in and then refuse it.
     * Failing to ask leaves the whole list, as the website does: the server
     * refuses a sport it does not offer either way, and says which.
     */
    fun loadSports() {
        viewModelScope.launch {
            val offered = runCatching { api.sports().offered }.getOrNull()
                ?.filter { it in ALL_SPORTS }
                ?.takeIf { it.isNotEmpty() }
                ?: return@launch
            _state.update { s ->
                val kept = s.sports.filter { it in offered }.toSet()
                s.copy(offered = offered, sports = kept.ifEmpty { setOf(offered.first()) })
            }
        }
    }

    fun setName(value: String) = _state.update { it.copy(name = value, error = null) }
    fun setDescription(value: String) = _state.update { it.copy(description = value) }
    fun setPublic(value: Boolean) = _state.update { it.copy(isPublic = value) }
    fun setInformal(value: Boolean) = _state.update { it.copy(isInformal = value) }

    fun toggleSport(sport: String) = _state.update {
        it.copy(sports = if (sport in it.sports) it.sports - sport else it.sports + sport, error = null)
    }

    fun create() {
        val form = _state.value
        if (!form.canSave) return
        _state.update { it.copy(isSaving = true, error = null) }
        viewModelScope.launch {
            val body = CreateClubBody(
                name = form.name.trim(),
                // In the picker's order, not the order they were tapped.
                sportTypes = form.offered.filter { it in form.sports },
                visibility = if (form.isPublic) "public" else "invite_only",
                description = form.description.trim().ifEmpty { null },
                isInformalGroup = form.isInformal,
            )
            runCatching { api.createClub(body) }
                .onSuccess { club -> _state.update { it.copy(isSaving = false, created = club) } }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    _state.update {
                        it.copy(
                            isSaving = false,
                            needsVerifying = refusal?.isUnverified == true,
                            error = saidWhy(e, refusal),
                        )
                    }
                }
        }
    }
}
