package com.fishers.app.match.start

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.i18n.t
import com.fishers.app.net.MatchStartApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException

data class OppositionState(
    val query: String = "",
    val results: List<ClubIdentity> = emptyList(),
    val isSearching: Boolean = false,
    /** Searched, and nothing came back. */
    val searched: Boolean = false,
    /** The search could not be made — no signal, say. Not the same as nobody by that name. */
    val searchError: String? = null,
    val code: String = "",
    val isLookingUp: Boolean = false,
    val message: String? = null,
    /** A code that resolved — the picker hands it back and closes. */
    val found: ClubIdentity? = null,
)

/**
 * Who you are playing — `OppositionPickerView.swift`. Find them on the platform
 * by their club code or their name, or just type who turned up.
 *
 * iOS scans the code with the camera; here it is typed or pasted (the code, or
 * the link it is in), which needs no camera permission and no new library.
 */
class OppositionViewModel(
    private val api: MatchStartApi,
    private val pause: Long = 250,
) : ViewModel() {

    private val _state = MutableStateFlow(OppositionState())
    val state: StateFlow<OppositionState> = _state.asStateFlow()

    private var searchJob: Job? = null

    /** Debounced, so a fast typist does not fire a request per keystroke. */
    fun setQuery(text: String) {
        _state.value = _state.value.copy(query = text)
        searchJob?.cancel()
        val term = text.trim()
        if (term.length < 2) {
            _state.value = _state.value.copy(results = emptyList(), isSearching = false, searched = false, searchError = null)
            return
        }
        searchJob = viewModelScope.launch {
            _state.value = _state.value.copy(isSearching = true)
            delay(pause)
            runCatching { api.searchOpponents(term) }
                .onSuccess {
                    _state.value = _state.value.copy(results = it, isSearching = false, searched = true, searchError = null)
                }
                .onFailure {
                    if (it is CancellationException) throw it
                    // "Nothing found" would be a wrong fact: nothing was asked.
                    _state.value = _state.value.copy(
                        results = emptyList(), isSearching = false, searched = false, searchError = readableError(it),
                    )
                }
        }
    }

    fun setCode(text: String) {
        _state.value = _state.value.copy(code = text, message = null)
    }

    fun lookUp() {
        val code = _state.value.code.trim()
        if (code.isEmpty() || _state.value.isLookingUp) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isLookingUp = true, message = null)
            runCatching { api.lookupOpponent(LookupOpponent(code)) }
                .onSuccess { _state.value = _state.value.copy(isLookingUp = false, found = it) }
                .onFailure {
                    _state.value = _state.value.copy(
                        isLookingUp = false,
                        // Only the server saying no means the code is not one of ours.
                        message = if (it is HttpException && it.code() in 400..499 && it.code() != 401) {
                            t("cl.code_isnt_one_of_ours")
                        } else {
                            readableError(it)
                        },
                    )
                }
        }
    }
}
