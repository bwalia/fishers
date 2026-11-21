package com.fishers.app.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.clubs.refusalOf
import com.fishers.app.i18n.t
import com.fishers.app.net.PaymentsApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class PayState(
    val pay: PayScreen? = null,
    val isLoading: Boolean = true,
    /** A claim is on its way: the buttons wait, so a second tap is not a second claim. */
    val isClaiming: Boolean = false,
    /** Which claim is being undone. */
    val undoing: String? = null,
    /** In red. */
    val error: String? = null,
    /** Said quietly: "Thanks — the club will confirm it." */
    val message: String? = null,
)

/**
 * The pay screen: what you owe one club, the bank details and your reference
 * to copy into your banking app, and "I've paid".
 *
 * A claim makes the share "waiting", never "paid": only the club confirming
 * that the money arrived does that.
 */
class PayViewModel(
    private val api: PaymentsApi,
    private val clubId: String,
    private val keys: AttemptKeys = AttemptKeys(),
) : ViewModel() {

    private val _state = MutableStateFlow(PayState())
    val state: StateFlow<PayState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            runCatching { api.payScreen(clubId) }
                .onSuccess { pay -> _state.update { it.copy(pay = pay, isLoading = false) } }
                .onFailure { e -> _state.update { it.copy(isLoading = false, error = failureText(e)) } }
        }
    }

    /**
     * "I've paid" (a transfer) or "I paid cash". The amount is left to the
     * server, which takes everything owed; the key is the same on every retry
     * of this tap until the server answers.
     */
    fun claim(method: PaymentMethod) {
        if (_state.value.isClaiming) return
        val attempt = "claim:$clubId:${method.wire}"
        val key = keys.keyFor(attempt)
        _state.update { it.copy(isClaiming = true, error = null, message = null) }
        viewModelScope.launch {
            runCatching { api.claimPayment(clubId, key, ClaimBody(method = method.wire)) }
                .onSuccess {
                    keys.settled(attempt)
                    _state.update { it.copy(isClaiming = false, message = t("pay.thanks_club_will_confirm")) }
                    load()
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    keys.failed(attempt, refusal)
                    // Nothing owed is not a failure: somebody (perhaps this
                    // phone, a moment ago) already said so. Show where it is.
                    val quiet = refusal?.code == "nothing_owed"
                    _state.update {
                        it.copy(
                            isClaiming = false,
                            error = if (quiet) null else failureText(e, refusal),
                            message = if (quiet) refusal.message else null,
                        )
                    }
                    if (quiet) load()
                }
        }
    }

    /** Take back a claim nobody has confirmed — tapped by mistake, or not paid after all. */
    fun undo(claim: Payment) {
        if (_state.value.undoing != null) return
        _state.update { it.copy(undoing = claim.id, error = null, message = null) }
        viewModelScope.launch {
            runCatching { api.cancelClaim(claim.id) }
                .onSuccess { _state.update { it.copy(undoing = null, message = t("pay.claim_undone")) } }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    _state.update { it.copy(undoing = null, error = failureText(e, refusal)) }
                }
            // Either way the list is out of date: it went, or the club decided it.
            load()
        }
    }

    fun dismissMessage() = _state.update { it.copy(message = null, error = null) }
}

data class DuesState(
    val dues: Dues? = null,
    val isLoading: Boolean = false,
    val error: String? = null,
)

/**
 * What you owe, across every club: the "you owe" card on Home and Profile,
 * and the list it opens. A failure leaves the last answer in place — a card
 * that vanishes on one bad bar of signal is a card nobody trusts.
 */
class DuesViewModel(private val api: PaymentsApi) : ViewModel() {

    private val _state = MutableStateFlow(DuesState())
    val state: StateFlow<DuesState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            runCatching { api.myDues() }
                .onSuccess { dues -> _state.update { DuesState(dues = dues) } }
                .onFailure { e -> _state.update { it.copy(isLoading = false, error = failureText(e)) } }
        }
    }
}
