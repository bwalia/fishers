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
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.toRequestBody

data class ProfileState(
    val me: Me? = null,
    val stats: MeStats? = null,
    val isLoading: Boolean = false,
    val error: String? = null,
    val photoBusy: Boolean = false,
    val photoError: String? = null,
    /** `<site>/p/<token>`, once asked for. */
    val shareLink: String? = null,
    val shareBusy: Boolean = false,
    val shareError: String? = null,
) {
    val strength: ProfileStrength? get() = me?.let(::ProfileStrength)
    val seasons: List<PlayerSeasonStats> get() = stats?.seasons.orEmpty()
    val club: String? get() = mainClub(seasons, me?.primaryProfile?.teamName)
}

/**
 * Your own page — `ProfileView.swift`: the record, the photo and the link a
 * player sends a club.
 *
 * [onUser] hands a fresher copy of the person to the rest of the app after the
 * photo changes, so Home and the tab bar do not show the old one.
 */
class ProfileViewModel(
    private val api: ProfileApi,
    /** The brand's website, which is where a profile link opens. */
    private val webBase: String,
    private val onUser: (Me) -> Unit = {},
) : ViewModel() {

    private val _state = MutableStateFlow(ProfileState())
    val state: StateFlow<ProfileState> = _state.asStateFlow()

    /** Every time the page is shown: a save elsewhere, or a confirmed contact, shows at once. */
    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            runCatching { api.me() }
                .onSuccess { me -> _state.update { it.copy(me = me, isLoading = false) } }
                .onFailure { failure ->
                    // What was showing stays showing: a flat moment on a train is
                    // not a reason to blank somebody's own page.
                    _state.update { it.copy(isLoading = false, error = profileError(failure)) }
                    return@launch
                }
            // A player with no season on record is not an error; the page says so.
            runCatching { api.myStats() }.onSuccess { stats -> _state.update { it.copy(stats = stats) } }
        }
    }

    /** A new photo, already shrunk to fit. */
    fun uploadPhoto(bytes: ByteArray) {
        if (_state.value.photoBusy) return
        viewModelScope.launch {
            _state.update { it.copy(photoBusy = true, photoError = null) }
            runCatching { api.uploadAvatar(avatarPart(bytes)) }
                .onSuccess { me ->
                    _state.update { it.copy(me = me, photoBusy = false) }
                    onUser(me)
                }
                .onFailure { failure ->
                    _state.update {
                        it.copy(photoBusy = false, photoError = profileError(failure, fallbackKey = "rest.picture_would_not_upload"))
                    }
                }
        }
    }

    /** The picked photo could not be decoded at all. */
    fun photoUnreadable() {
        _state.update { it.copy(photoError = t("rest.photo_could_not_be_read")) }
    }

    fun makeShareLink() {
        if (_state.value.shareBusy) return
        viewModelScope.launch {
            _state.update { it.copy(shareBusy = true, shareError = null) }
            runCatching { api.shareLink() }
                .onSuccess { link -> _state.update { it.copy(shareBusy = false, shareLink = profileLink(webBase, link.token)) } }
                .onFailure { failure ->
                    _state.update {
                        it.copy(shareBusy = false, shareError = profileError(failure, fallbackKey = "le.could_not_make_your_link"))
                    }
                }
        }
    }
}

/** Where a player's profile link opens: the website's `/p/<token>`, as iOS builds it. */
fun profileLink(webBase: String, token: String) = "${webBase.trimEnd('/')}/p/$token"

/**
 * The multipart part `/me/avatar` reads. The type comes from the bytes, not
 * the picker: the server sniffs them too, and a mismatch there is a refusal
 * the person cannot act on.
 */
fun avatarPart(bytes: ByteArray): MultipartBody.Part {
    val png = bytes.size >= 4 && bytes[0] == 0x89.toByte() && bytes[1] == 0x50.toByte() &&
        bytes[2] == 0x4E.toByte() && bytes[3] == 0x47.toByte()
    val type = if (png) "image/png" else "image/jpeg"
    val name = if (png) "avatar.png" else "avatar.jpg"
    return MultipartBody.Part.createFormData("file", name, bytes.toRequestBody(type.toMediaType()))
}
