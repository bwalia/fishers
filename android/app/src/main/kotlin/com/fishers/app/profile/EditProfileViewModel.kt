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

data class EditProfileState(
    /** Null until the profile has loaded: a form filled from nothing would save blanks. */
    val me: Me? = null,
    val form: ProfileForm = ProfileForm(),
    /** What the pickers offer; the server narrows it per brand. */
    val offered: List<Sport> = Sport.entries,
    val isLoading: Boolean = true,
    val loadError: String? = null,
    val isSaving: Boolean = false,
    val error: String? = null,
    val photoBusy: Boolean = false,
    val photoError: String? = null,
    /** Set once a save has gone through; the screen closes on it. */
    val saved: Boolean = false,
) {
    val canSave: Boolean get() = me != null && form.isNameValid && !isSaving

    /** Offered, plus anything the profile already names — this narrows what can be added, never what has been. */
    val sportsShown: List<Sport> get() = (offered + form.selectedSports).distinct()
}

/**
 * Edit your profile — `ProfileEditView.swift`.
 *
 * Whatever is filled in saves; a profile is finished a bit at a time. [onSaved]
 * gets the person the server handed back, so the rest of the app shows it
 * without asking again.
 */
class EditProfileViewModel(
    private val api: ProfileApi,
    private val onSaved: (Me) -> Unit = {},
) : ViewModel() {

    private val _state = MutableStateFlow(EditProfileState())
    val state: StateFlow<EditProfileState> = _state.asStateFlow()

    fun load() {
        if (_state.value.me != null) return
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, loadError = null) }
            runCatching { api.me() }
                .onSuccess { me -> _state.update { it.copy(me = me, form = ProfileForm.from(me), isLoading = false) } }
                .onFailure { failure -> _state.update { it.copy(isLoading = false, loadError = profileError(failure)) } }
            runCatching { api.offeredSports() }.onSuccess { answer ->
                // An answer nobody can read is worse than none: an empty grid
                // is the one outcome with no way forward.
                val offered = answer.offered.mapNotNull(Sport::named).distinct()
                if (offered.isNotEmpty()) _state.update { it.copy(offered = offered) }
            }
        }
    }

    fun edit(change: (ProfileForm) -> ProfileForm) {
        _state.update { it.copy(form = change(it.form), error = null) }
    }

    fun save() {
        val current = _state.value
        if (!current.canSave) return
        viewModelScope.launch {
            _state.update { it.copy(isSaving = true, error = null) }
            runCatching { api.updateProfile(current.form.toUpdate()) }
                .onSuccess { me ->
                    _state.update { it.copy(me = me, isSaving = false, saved = true) }
                    onSaved(me)
                }
                .onFailure { failure -> _state.update { it.copy(isSaving = false, error = profileError(failure)) } }
        }
    }

    /**
     * A new photo goes up at once rather than with Save: it is its own call,
     * and somebody who picks one and then backs out still meant to change it.
     */
    fun uploadPhoto(bytes: ByteArray) {
        if (_state.value.photoBusy) return
        viewModelScope.launch {
            _state.update { it.copy(photoBusy = true, photoError = null) }
            runCatching { api.uploadAvatar(avatarPart(bytes)) }
                .onSuccess { me ->
                    _state.update { it.copy(me = it.me?.copy(avatarUrl = me.avatarUrl) ?: me, photoBusy = false) }
                    onSaved(me)
                }
                .onFailure { failure ->
                    _state.update {
                        it.copy(photoBusy = false, photoError = profileError(failure, fallbackKey = "rest.picture_would_not_upload"))
                    }
                }
        }
    }

    fun photoUnreadable() {
        _state.update { it.copy(photoError = t("rest.photo_could_not_be_read")) }
    }
}
