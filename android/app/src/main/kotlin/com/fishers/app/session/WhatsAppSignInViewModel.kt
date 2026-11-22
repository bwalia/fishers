package com.fishers.app.session

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.clubs.refusalOf
import com.fishers.app.i18n.t
import com.fishers.app.net.AuthTokens
import com.fishers.app.net.WhatsAppCode
import com.fishers.app.net.WhatsAppPhone
import com.fishers.app.net.WhatsAppSignInApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class WhatsAppSignInState(
    /** The server offers it. False until it has said so, and after `whatsapp_off`. */
    val enabled: Boolean = false,
    /** The WhatsApp form is showing in place of email and password. */
    val open: Boolean = false,
    /** The number a code was sent to; null while it is still being typed. */
    val sentTo: String? = null,
    val isBusy: Boolean = false,
    /** When another code may be asked for, on [WhatsAppSignInViewModel]'s clock. */
    val resendAtMs: Long = 0,
    /** The server's own sentence, or the app's for no signal. */
    val error: String? = null,
)

/**
 * Sign in with a mobile number and a six-digit code sent by WhatsApp. Offered
 * only when `GET /auth/whatsapp` says it is on; a failure to ask leaves it
 * off, quietly — email still works.
 *
 * Every refusal shows the server's sentence, whatever its status: a 502
 * `not_sent` or 503 `whatsapp_off` here is something the person can act on
 * ("try again in a minute", "use your email"), not "the server is having
 * trouble".
 */
class WhatsAppSignInViewModel(
    private val api: WhatsAppSignInApi,
    /** The tokens, to [SessionViewModel.signedIn]. */
    private val onSignedIn: (AuthTokens) -> Unit,
    private val clock: () -> Long = System::currentTimeMillis,
) : ViewModel() {

    private val _state = MutableStateFlow(WhatsAppSignInState())
    val state: StateFlow<WhatsAppSignInState> = _state.asStateFlow()

    fun loadConfig() {
        viewModelScope.launch {
            runCatching { api.config() }.onSuccess { c -> _state.update { it.copy(enabled = c.enabled) } }
        }
    }

    fun open() = _state.update { it.copy(open = true, error = null) }

    /** Back to email and password. */
    fun close() = _state.update { WhatsAppSignInState(enabled = it.enabled) }

    /** Back to the number, to fix a typo. */
    fun changeNumber() = _state.update { it.copy(sentTo = null, error = null) }

    fun sendCode(phone: String) {
        val number = phone.trim()
        if (number.isEmpty() || _state.value.isBusy) return
        _state.update { it.copy(isBusy = true, error = null) }
        viewModelScope.launch {
            runCatching { api.start(WhatsAppPhone(number)) }
                .onSuccess { sent ->
                    _state.update {
                        it.copy(isBusy = false, sentTo = number, resendAtMs = clock() + sent.resendAfter.coerceAtLeast(0) * 1000L)
                    }
                }
                .onFailure { e -> failed(e) }
        }
    }

    /** Another code, once the wait the server asked for is over. */
    fun resend() {
        val number = _state.value.sentTo ?: return
        if (clock() < _state.value.resendAtMs) return
        sendCode(number)
    }

    /** Seconds until another code may be asked for; 0 when it may. */
    fun secondsUntilResend(): Int = ((_state.value.resendAtMs - clock() + 999) / 1000).toInt().coerceAtLeast(0)

    fun verify(code: String) {
        val number = _state.value.sentTo ?: return
        val digits = code.filter(Char::isDigit)
        if (_state.value.isBusy) return
        if (digits.length != CODE_LENGTH) {
            _state.update { it.copy(error = t("pa2.wa_code_six_digits")) }
            return
        }
        _state.update { it.copy(isBusy = true, error = null) }
        viewModelScope.launch {
            runCatching { api.verify(WhatsAppCode(number, digits)) }
                .onSuccess { tokens ->
                    _state.update { WhatsAppSignInState(enabled = it.enabled) }
                    onSignedIn(tokens)
                }
                .onFailure { e -> failed(e) }
        }
    }

    fun dismissError() = _state.update { it.copy(error = null) }

    private fun failed(e: Throwable) {
        val refusal = refusalOf(e)
        val said = refusal?.message ?: readableError(e)
        _state.update {
            if (refusal?.code == "whatsapp_off") {
                // Switched off since the form opened: back to email, saying why.
                WhatsAppSignInState(enabled = false, error = said)
            } else {
                it.copy(isBusy = false, error = said)
            }
        }
    }

    companion object {
        const val CODE_LENGTH = 6
    }
}
