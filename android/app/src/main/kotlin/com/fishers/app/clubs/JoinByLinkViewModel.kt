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

/**
 * An invite link opened in the app — the website's `/invite/[token]` page.
 *
 * The preview is read first, so the screen can say "Join Southall Strikers"
 * and say a dead link is dead before anybody taps anything. Joining is a tap,
 * not automatic: somebody who followed a link should see what it is to.
 */
data class JoinByLinkState(
    val stage: Stage = Stage.Checking,
    val preview: InvitePreview? = null,
    /** Why it did not work, worded as the website words it. */
    val error: String? = null,
    /** The account has to be confirmed before it can join anything. */
    val needsVerifying: Boolean = false,
    /** Where to go once in. */
    val joined: Joined? = null,
) {
    enum class Stage { Checking, Ready, Joining, Joined, Failed }

    /** A club, by id and name — or a fixture, for an invite to one. */
    data class Joined(val clubId: String?, val clubName: String?, val eventId: String?)

    /** What to try next, under the error: a dead club link and a spent invite need different things. */
    val advice: String
        get() = if (preview?.open == true) t("jl.ask_for_the_current_link")
        else t("rest.an_invite_can_only_be_used_once_ask_wh")
}

class JoinByLinkViewModel(private val api: ClubsApi, private val token: String) : ViewModel() {

    private val _state = MutableStateFlow(JoinByLinkState())
    val state: StateFlow<JoinByLinkState> = _state.asStateFlow()

    fun load() {
        _state.value = JoinByLinkState()
        viewModelScope.launch {
            runCatching { api.invitePreview(token) }
                .onSuccess { preview ->
                    _state.value = if (preview.usable) {
                        JoinByLinkState(stage = JoinByLinkState.Stage.Ready, preview = preview)
                    } else {
                        JoinByLinkState(
                            stage = JoinByLinkState.Stage.Failed,
                            preview = preview,
                            error = if (preview.open) t("jl.link_turned_off") else t("jl.link_already_used"),
                        )
                    }
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    _state.value = JoinByLinkState(
                        stage = JoinByLinkState.Stage.Failed,
                        // No such invite: the website's words for a link
                        // that leads nowhere. Anything else — no signal — is
                        // worth saying as it is, with a way to try again.
                        error = if (refusal?.status == 404) t("le.that_invite_could_not_be_used")
                        else saidWhy(e, refusal),
                    )
                }
        }
    }

    fun join() {
        val current = _state.value
        if (current.stage != JoinByLinkState.Stage.Ready) return
        _state.update { it.copy(stage = JoinByLinkState.Stage.Joining, error = null) }
        viewModelScope.launch {
            runCatching { api.acceptInvite(token) }
                .onSuccess { invite ->
                    val preview = current.preview
                    _state.update {
                        it.copy(
                            stage = JoinByLinkState.Stage.Joined,
                            joined = JoinByLinkState.Joined(
                                clubId = if (invite.targetType == "club") invite.targetId else preview?.clubId,
                                clubName = preview?.clubName,
                                eventId = invite.targetId.takeIf { invite.targetType == "event" },
                            ),
                        )
                    }
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    when {
                        // Not a dead link: confirm, then the same link works.
                        // Left on the Join button rather than failed.
                        refusal?.isUnverified == true -> _state.update {
                            it.copy(stage = JoinByLinkState.Stage.Ready, needsVerifying = true, error = saidWhy(e, refusal))
                        }
                        refusal?.code == "removed_from_club" -> _state.update {
                            it.copy(stage = JoinByLinkState.Stage.Failed, error = t("jl.removed_from_club"))
                        }
                        // Used, turned off, gone: the server says which.
                        refusal != null && refusal.status in 400..499 -> _state.update {
                            it.copy(
                                stage = JoinByLinkState.Stage.Failed,
                                error = refusal.message ?: t("le.that_invite_could_not_be_used"),
                            )
                        }
                        // No signal, or a server in trouble: nothing is wrong
                        // with the link, so it can be tried again.
                        else -> _state.update {
                            it.copy(stage = JoinByLinkState.Stage.Ready, error = saidWhy(e, refusal))
                        }
                    }
                }
        }
    }
}
