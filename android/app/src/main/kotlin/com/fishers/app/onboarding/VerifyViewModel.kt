package com.fishers.app.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.i18n.t
import com.fishers.app.net.ProfileApi
import com.fishers.app.profile.ApiFailure
import com.fishers.app.profile.Me
import com.fishers.app.profile.profileError
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class VerifyState(
    val status: VerificationStatus? = null,
    /** The status could not be read at all. */
    val failed: Boolean = false,
    val channel: VerificationChannel = VerificationChannel.Email,
    val code: String = "",
    val busy: Boolean = false,
    val note: String? = null,
    val error: String? = null,
    /** Seconds before another code may be asked for. */
    val wait: Int = 0,
    val verified: Boolean = false,
) {
    val address: String get() = status?.get(channel)?.address.orEmpty()
    val canConfirm: Boolean get() = code.length == 6 && !busy
}

/**
 * Confirm an email address or a mobile number with a six-digit code —
 * `VerifyContactView.swift`.
 *
 * The field is there from the start rather than behind a "send code" button:
 * signing up already sent the first code, so most people only need to type it.
 * "Send a new code" covers the rest, and counts down when the server says it is
 * too soon to ask again.
 */
class VerifyViewModel(
    private val api: ProfileApi,
    private val onVerified: (Me) -> Unit = {},
) : ViewModel() {

    private val _state = MutableStateFlow(VerifyState())
    val state: StateFlow<VerifyState> = _state.asStateFlow()

    private var countdown: Job? = null

    fun load() {
        viewModelScope.launch {
            runCatching { api.verificationStatus() }
                .onSuccess { status ->
                    _state.update {
                        it.copy(status = status, failed = false, channel = status.channels.firstOrNull() ?: VerificationChannel.Email)
                    }
                }
                .onFailure { _state.update { it.copy(failed = true) } }
        }
    }

    fun selectChannel(channel: VerificationChannel) = _state.update {
        it.copy(channel = channel, code = "", note = null, error = null)
    }

    /** Digits only, six at most — and a full code submits itself, the way a one-time-code autofill does. */
    fun typeCode(typed: String) {
        val digits = typed.filter(Char::isDigit).take(6)
        _state.update { it.copy(code = digits, error = null) }
        if (digits.length == 6) confirm()
    }

    fun send() {
        if (_state.value.wait > 0) return
        val channel = _state.value.channel
        viewModelScope.launch {
            _state.update { it.copy(error = null, note = null) }
            runCatching { api.sendVerificationCode(channel.wire) }
                .onSuccess { sent ->
                    _state.update {
                        it.copy(
                            note = t("pf.new_code_sent", vars = mapOf("verb" to channel.sentVerb, "address" to sent.sentTo)),
                            code = "",
                        )
                    }
                    startCountdown(sent.resendAfter)
                }
                .onFailure { failure ->
                    val refusal = ApiFailure.of(failure)
                    // "you can ask for another in 42s" reads better as a countdown.
                    val seconds = refusal.message?.let(::secondsToWait)
                    if (seconds != null) {
                        startCountdown(seconds)
                    } else {
                        _state.update { it.copy(error = profileError(failure, refusal)) }
                    }
                }
        }
    }

    fun confirm() {
        val current = _state.value
        if (!current.canConfirm) return
        viewModelScope.launch {
            _state.update { it.copy(busy = true, error = null) }
            runCatching { api.confirmVerification(current.channel.wire, VerificationCode(current.code)) }
                .onSuccess { me ->
                    _state.update { it.copy(busy = false, verified = true) }
                    onVerified(me)
                }
                .onFailure { failure ->
                    _state.update {
                        it.copy(busy = false, code = "", error = profileError(failure, fallbackKey = "le.that_code_did_not_work"))
                    }
                }
        }
    }

    private fun startCountdown(seconds: Int) {
        countdown?.cancel()
        _state.update { it.copy(wait = seconds) }
        countdown = viewModelScope.launch {
            while (_state.value.wait > 0) {
                delay(1_000)
                _state.update { it.copy(wait = (it.wait - 1).coerceAtLeast(0)) }
            }
        }
    }

    companion object {
        /** The seconds in the server's "… you can ask for another in 42s". */
        fun secondsToWait(message: String): Int? =
            Regex("""in (\d+)s""").find(message)?.groupValues?.get(1)?.toIntOrNull()
    }
}
