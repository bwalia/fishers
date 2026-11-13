package com.fishers.app.onboarding

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.net.ProfileApi
import com.fishers.app.net.RoleIntentPatch
import com.fishers.app.profile.Me
import com.fishers.app.profile.ProfileUpdate
import com.fishers.app.profile.Sport
import com.fishers.app.profile.SportProfile
import com.fishers.app.profile.nonEmpty
import com.fishers.app.profile.profileError
import com.fishers.app.session.RoleIntent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Whether somebody is past the quick start on this phone.
 *
 * Anyone who has told us a sport is past it on every device, because that is
 * on the server; somebody who skipped is past it on this one — the same rule
 * as `SessionStore.needsQuickStart`.
 */
interface QuickStartMemory {
    fun isPast(userId: String): Boolean
    fun markPast(userId: String)
}

class PrefsQuickStartMemory(context: Context) : QuickStartMemory {
    private val prefs = context.applicationContext.getSharedPreferences("fishers.onboarding", Context.MODE_PRIVATE)
    override fun isPast(userId: String) = prefs.getBoolean(key(userId), false)
    override fun markPast(userId: String) = prefs.edit().putBoolean(key(userId), true).apply()
    private fun key(userId: String) = "quick-start:$userId"
}

enum class Gate { Checking, Ask, Done }

data class QuickStartState(
    val gate: Gate = Gate.Checking,
    val firstName: String = "",
    /** Asked here only if signing up did not ask it. */
    val asksRole: Boolean = false,
    val asksPhone: Boolean = false,
    val role: RoleIntent? = null,
    /** Ordered: the first is the main sport. */
    val sports: List<Sport> = emptyList(),
    val offered: List<Sport> = Sport.entries,
    val phone: String = "",
    val saving: Boolean = false,
    val error: String? = null,
) {
    val canContinue: Boolean get() = sports.isNotEmpty() && !saving
}

/**
 * The one screen between signing up and the app — `QuickStartView.swift`:
 * what you play and a number your captain can reach you on, both skippable.
 * Everything else a profile holds waits for a quiet moment.
 */
class QuickStartViewModel(
    private val api: ProfileApi,
    private val memory: QuickStartMemory,
    private val userId: String,
    /** A fresher copy of the person, for the rest of the app. */
    private val onUser: (Me) -> Unit = {},
) : ViewModel() {

    private val _state = MutableStateFlow(
        // Decided before the first frame where it can be, so somebody past it
        // never sees a spinner on the way to their tabs.
        QuickStartState(gate = if (memory.isPast(userId)) Gate.Done else Gate.Checking),
    )
    val state: StateFlow<QuickStartState> = _state.asStateFlow()

    private var me: Me? = null

    fun check() {
        if (_state.value.gate != Gate.Checking) return
        viewModelScope.launch {
            val fresh = runCatching { api.me() }.getOrElse {
                // Not knowing is not a reason to stand between somebody and
                // their app; the profile page asks for a sport later.
                _state.update { it.copy(gate = Gate.Done) }
                return@launch
            }
            me = fresh
            if (fresh.sportProfiles.isNotEmpty()) {
                memory.markPast(userId)
                _state.update { it.copy(gate = Gate.Done) }
                return@launch
            }
            val role = RoleIntent.entries.firstOrNull { it.wire == fresh.roleIntent }
            _state.update {
                it.copy(
                    gate = Gate.Ask,
                    firstName = fresh.name.trim().split(" ").firstOrNull().orEmpty(),
                    asksRole = role == null,
                    asksPhone = fresh.phone.nonEmpty() == null,
                    role = role,
                    phone = fresh.phone.orEmpty(),
                )
            }
            // The first screen of the app, so the one that most needs to offer
            // only what is finished.
            runCatching { api.offeredSports() }.onSuccess { answer ->
                val offered = answer.offered.mapNotNull(Sport::named).distinct()
                if (offered.isNotEmpty()) _state.update { it.copy(offered = offered) }
            }
        }
    }

    fun pickRole(role: RoleIntent) = _state.update { it.copy(role = role) }

    fun toggleSport(sport: Sport) = _state.update {
        it.copy(sports = if (sport in it.sports) it.sports - sport else it.sports + sport)
    }

    fun setPhone(phone: String) = _state.update { it.copy(phone = phone, error = null) }

    fun finish() {
        val current = _state.value
        val who = me ?: return
        if (!current.canContinue) return
        viewModelScope.launch {
            _state.update { it.copy(saving = true, error = null) }
            runCatching {
                val role = current.role
                if (role != null && role.wire != who.roleIntent) api.setRoleIntent(RoleIntentPatch(role.wire))
                api.updateProfile(
                    ProfileUpdate.of(
                        name = who.name,
                        sportProfiles = current.sports.map { SportProfile(sport = it.wire) },
                        primarySport = current.sports.first().wire,
                        phone = current.phone.nonEmpty(),
                    ),
                )
            }
                .onSuccess { updated ->
                    onUser(updated)
                    memory.markPast(userId)
                    _state.update { it.copy(saving = false, gate = Gate.Done) }
                }
                .onFailure { failure -> _state.update { it.copy(saving = false, error = profileError(failure)) } }
        }
    }

    /** Straight in. The role still counts if they picked one. */
    fun skip() {
        val current = _state.value
        if (current.saving) return
        viewModelScope.launch {
            _state.update { it.copy(saving = true, error = null) }
            val role = current.role
            if (role != null && role.wire != me?.roleIntent) {
                runCatching { api.setRoleIntent(RoleIntentPatch(role.wire)) }.onSuccess(onUser)
            }
            memory.markPast(userId)
            _state.update { it.copy(saving = false, gate = Gate.Done) }
        }
    }
}
