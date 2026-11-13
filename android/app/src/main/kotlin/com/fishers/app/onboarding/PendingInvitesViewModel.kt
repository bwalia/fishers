package com.fishers.app.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.i18n.t
import com.fishers.app.net.ProfileApi
import com.fishers.app.profile.ApiFailure
import com.fishers.app.profile.profileError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class PendingInvitesState(
    val invites: List<PendingInvite> = emptyList(),
    /** The invite being accepted; one at a time. */
    val busy: String? = null,
    val error: String? = null,
    /** The last refusal was "confirm a contact first": offer the way to. */
    val needsVerification: Boolean = false,
)

/**
 * Invitations waiting for this account — `PendingInvitesSection.swift`.
 *
 * An invite usually arrives as a link, and a link lost in a group chat is the
 * most common reason somebody never joins their club. It is already addressed
 * to this account, so it can simply be listed and accepted here.
 */
class PendingInvitesViewModel(
    private val api: ProfileApi,
    /** After an accept: the person now belongs to something new. */
    private val onAccepted: () -> Unit = {},
) : ViewModel() {

    private val _state = MutableStateFlow(PendingInvitesState())
    val state: StateFlow<PendingInvitesState> = _state.asStateFlow()

    /** Quiet on failure: this section draws nothing rather than an error on Home. */
    fun load() {
        viewModelScope.launch {
            runCatching { api.myInvites() }.onSuccess { all ->
                _state.update { it.copy(invites = all.filter(PendingInvite::isPending)) }
            }
        }
    }

    fun accept(invite: PendingInvite) {
        if (_state.value.busy != null) return
        viewModelScope.launch {
            _state.update { it.copy(busy = invite.id, error = null, needsVerification = false) }
            runCatching { api.acceptInvite(invite.token) }
                .onSuccess {
                    _state.update { s -> s.copy(busy = null, invites = s.invites.filterNot { it.id == invite.id }) }
                    onAccepted()
                }
                .onFailure { failure ->
                    val refusal = ApiFailure.of(failure)
                    _state.update {
                        it.copy(
                            busy = null,
                            needsVerification = refusal.isUnverified,
                            error = if (refusal.isUnverified) {
                                t("rest.starting_club_needs_confirmed")
                            } else {
                                profileError(failure, refusal)
                            },
                        )
                    }
                }
        }
    }
}
