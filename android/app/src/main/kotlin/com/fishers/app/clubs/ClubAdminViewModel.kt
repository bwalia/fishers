package com.fishers.app.clubs

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.i18n.t
import com.fishers.app.net.ClubsApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * The secretary's side of the club — `ClubAdminStore.swift`: adding people,
 * appointing a captain, the policy and the fees.
 *
 * The roster itself and the club's open link are [ClubDetailViewModel]'s,
 * which had them first. A change here bumps [ClubAdminState.changed], and the
 * screen re-reads the roster from there.
 */
data class ClubAdminState(
    /** What this person may do here: only a secretary changes the roster. */
    val role: ClubRoleInfo? = null,
    val settings: ClubSettings? = null,
    /** Captains and above. Null for anyone else, and the tab says so. */
    val fees: OutstandingFees? = null,
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val isChasing: Boolean = false,
    /** A one-person invite, once made, and the link it makes. */
    val invite: ClubInvite? = null,
    val inviteUrl: String? = null,
    /** In the server's words: "this is the club's last secretary — appoint another one first". */
    val error: String? = null,
    /** "Reminders sent." */
    val note: String? = null,
    /** Bumped each time the roster changed on the server. */
    val changed: Int = 0,
) {
    /** `require_secretary` guards adding, appointing and removing. */
    val canManage: Boolean get() = role?.isSecretary == true
    /** The policy is `manage_club_ops`. */
    val canSetPolicy: Boolean get() = role?.runsClubOps == true
    /** Chasing fees is for whoever picks sides — captains and above. */
    val canChase: Boolean get() = role?.isCaptain == true
}

class ClubAdminViewModel(
    private val api: ClubsApi,
    private val clubId: String,
    /** The brand's site, which is where an invite link opens. */
    private val webBase: String,
    /** How long the policy waits for the taps to stop before it saves. */
    private val saveDelayMs: Long = 600,
) : ViewModel() {

    private val _state = MutableStateFlow(ClubAdminState())
    val state: StateFlow<ClubAdminState> = _state.asStateFlow()

    private var saving: Job? = null

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            val role = runCatching { api.myRole(clubId) }.getOrNull()
            val settings = runCatching { api.settings(clubId) }.getOrNull()
            // A 403 for a plain member: no fees to show them, and nothing wrong.
            val fees = runCatching { api.outstandingFees(clubId) }.getOrNull()
            _state.update {
                it.copy(isLoading = false, role = role ?: it.role, settings = settings ?: it.settings, fees = fees)
            }
        }
    }

    fun dismissError() = _state.update { it.copy(error = null) }
    fun dismissNote() = _state.update { it.copy(note = null) }

    // ---- the roster ----

    /**
     * By email or mobile number. Somebody who registered with a number has no
     * address to be looked up by, so either is taken.
     */
    fun addMember(identifier: String, role: UserRole) {
        val who = identifier.trim()
        if (who.isEmpty()) return
        rosterChange { api.addMember(clubId, AddMemberBody(identifier = who, role = role.wireName)) }
    }

    fun setRole(member: ClubMemberDetail, choice: RoleChoice) {
        if (choice == member.roleChoice) return
        rosterChange { api.setRole(clubId, member.userId, choice.body) }
    }

    /** Their past availability, fees and appearances stay on record. */
    fun remove(member: ClubMemberDetail) = rosterChange { api.removeMember(clubId, member.userId) }

    private fun rosterChange(call: suspend () -> Unit) {
        viewModelScope.launch {
            runCatching { call() }
                .onSuccess { _state.update { it.copy(changed = it.changed + 1, error = null) } }
                .onFailure { e -> _state.update { it.copy(error = saidWhy(e)) } }
        }
    }

    /**
     * A link for one person: they open it, sign up if they have to, and land
     * in the club. Spent by the first account through it — the club's open
     * link is the one for a WhatsApp group. An address, when given, is who
     * gets told about it if they already have an account.
     */
    fun makeInvite(email: String?) {
        viewModelScope.launch {
            val address = email?.trim()?.takeIf { it.contains('@') }
            runCatching { api.createInvite(CreateInviteBody(targetId = clubId, invitedEmail = address)) }
                .onSuccess { invite ->
                    _state.update {
                        it.copy(invite = invite, inviteUrl = "${webBase.trimEnd('/')}/invite/${invite.token}", error = null)
                    }
                }
                .onFailure { e -> _state.update { it.copy(error = saidWhy(e)) } }
        }
    }

    /** The add sheet closed: the next person gets a link of their own. */
    fun clearInvite() = _state.update { it.copy(invite = null, inviteUrl = null) }

    // ---- policy ----

    /**
     * Applied at once, saved once the taps stop: a stepper fires on every
     * press, and each press should not be a round trip. Out-of-range values
     * are pulled back to what the server accepts rather than sent to be
     * refused.
     */
    fun changeSettings(change: (ClubSettings) -> ClubSettings) {
        val current = _state.value.settings ?: return
        val next = change(current).let {
            it.copy(
                confirmLeadHours = it.confirmLeadHours.coerceIn(0, MAX_HOURS),
                dropLeadHours = it.dropLeadHours.coerceIn(0, MAX_HOURS),
                feeChaseAfterHours = it.feeChaseAfterHours.coerceIn(0, MAX_HOURS),
                feeChaseMaxReminders = it.feeChaseMaxReminders.coerceIn(0, MAX_REMINDERS),
            )
        }
        if (next == current) return
        _state.update { it.copy(settings = next) }
        saving?.cancel()
        saving = viewModelScope.launch {
            delay(saveDelayMs)
            _state.update { it.copy(isSaving = true) }
            runCatching { api.updateSettings(clubId, next) }
                .onSuccess { saved -> _state.update { it.copy(isSaving = false, settings = saved) } }
                .onFailure { e ->
                    // Put back what the server actually holds, so the screen
                    // does not show a policy that is not in force.
                    val held = runCatching { api.settings(clubId) }.getOrNull()
                    _state.update {
                        it.copy(isSaving = false, error = saidWhy(e), settings = held ?: current)
                    }
                }
        }
    }

    // ---- fees ----

    /** The scheduler does this on its own; this is the do-it-now button. */
    fun chaseFees() {
        if (_state.value.isChasing) return
        _state.update { it.copy(isChasing = true) }
        viewModelScope.launch {
            runCatching { api.chaseFees(clubId) }
                .onSuccess {
                    val fees = runCatching { api.outstandingFees(clubId) }.getOrNull()
                    _state.update {
                        it.copy(isChasing = false, fees = fees ?: it.fees, note = t("lc.reminders_sent"))
                    }
                }
                .onFailure { e -> _state.update { it.copy(isChasing = false, error = saidWhy(e)) } }
        }
    }

    private companion object {
        /** `update_settings` in clubs.rs refuses anything outside these. */
        const val MAX_HOURS = 336
        const val MAX_REMINDERS = 10
    }
}
