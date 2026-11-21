package com.fishers.app.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.clubs.refusalOf
import com.fishers.app.i18n.t
import com.fishers.app.net.PaymentsApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Where the bank details form has got to. Closed is null in [ClubMoneyState.form]. */
data class BankForm(
    val isSaving: Boolean = false,
    /** The server asked for the password (428), or the one typed was wrong (403). */
    val needsPassword: Boolean = false,
    val error: String? = null,
)

data class ClubMoneyState(
    val overview: MoneyOverview? = null,
    val isLoading: Boolean = true,
    /** 403: not the owner, a secretary or a treasurer. The server's sentence. */
    val notAllowed: String? = null,
    /** It could not be read for any other reason. */
    val loadError: String? = null,
    /** Payments being confirmed or turned down, by id: each row waits on its own. */
    val deciding: Set<String> = emptySet(),
    val isBusy: Boolean = false,
    val form: BankForm? = null,
    val error: String? = null,
    val message: String? = null,
) {
    val account: PayoutAccounts? get() = overview?.account
    val currency: String get() = overview?.currency ?: "GBP"
}

/**
 * Club → Manage → Payments: the bank details, the payments to check, who owes
 * what, recent bills and the settings — the treasurer's whole job on one page.
 *
 * Whether somebody sees it at all is the server's 403 on `/money`, not the
 * app's reading of their role.
 */
class ClubMoneyViewModel(
    private val api: PaymentsApi,
    private val clubId: String,
    private val keys: AttemptKeys = AttemptKeys(),
    /** How long the settings wait for the taps to stop before they save. */
    private val saveDelayMs: Long = 600,
) : ViewModel() {

    private val _state = MutableStateFlow(ClubMoneyState())
    val state: StateFlow<ClubMoneyState> = _state.asStateFlow()

    private var savingSettings: Job? = null

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            runCatching { api.money(clubId) }
                .onSuccess { o -> _state.update { it.copy(overview = o, isLoading = false, notAllowed = null, loadError = null) } }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    _state.update {
                        if (refusal?.status == 403) {
                            it.copy(isLoading = false, notAllowed = refusal.message ?: t("pay.money_admins_only"))
                        } else {
                            it.copy(isLoading = false, loadError = failureText(e, refusal))
                        }
                    }
                }
        }
    }

    fun dismissMessage() = _state.update { it.copy(message = null, error = null) }

    // ---- payments to check ----

    /** "Received": it is in the club's account. */
    fun confirm(payment: Payment) = decide(payment) { api.confirmPayment(payment.id) }

    /** "Not received", with why: the player is told, and reminders start again. */
    fun reject(payment: Payment, reason: String) = decide(payment) { api.rejectPayment(payment.id, ReasonBody(reason.trim())) }

    private fun decide(payment: Payment, call: suspend () -> Payment) {
        if (payment.id in _state.value.deciding) return
        _state.update { it.copy(deciding = it.deciding + payment.id, error = null, message = null) }
        viewModelScope.launch {
            runCatching { call() }
                .onSuccess { decided ->
                    _state.update {
                        it.copy(
                            deciding = it.deciding - payment.id,
                            message = if (decided.status == "confirmed") {
                                t("pay.marked_received", vars = mapOf("name" to payment.name))
                            } else {
                                t("pay.marked_not_received", vars = mapOf("name" to payment.name))
                            },
                        )
                    }
                }
                // `already_decided` included: somebody else got there first,
                // and the reload shows what they did.
                .onFailure { e -> _state.update { it.copy(deciding = it.deciding - payment.id, error = failureText(e)) } }
            load()
        }
    }

    // ---- who owes what ----

    /** Cash at the ground, or a transfer that came with no claim. Confirmed at once. */
    fun record(who: MemberBalance, cents: Long, method: PaymentMethod, note: String?) {
        val body = RecordBody(
            userId = who.userId,
            guestName = who.guestName.takeIf { who.userId == null },
            amountCents = cents,
            method = method.wire,
            note = note?.trim()?.takeIf { it.isNotEmpty() },
        )
        pay("record", body, t("pay.recorded", vars = mapOf("name" to who.name))) { key -> api.recordPayment(clubId, key, body) }
    }

    /** Hand back credit somebody has with the club: at most what they have. */
    fun refund(who: MemberBalance, cents: Long, note: String?) {
        val body = RecordBody(
            userId = who.userId,
            guestName = who.guestName.takeIf { who.userId == null },
            amountCents = cents,
            note = note?.trim()?.takeIf { it.isNotEmpty() },
        )
        pay("refund", body, t("pay.refunded", vars = mapOf("name" to who.name))) { key -> api.refund(clubId, key, body) }
    }

    /** The same body retried is the same attempt, and so the same key. */
    private fun pay(kind: String, body: RecordBody, done: String, call: suspend (String) -> Payment) {
        if (_state.value.isBusy) return
        val attempt = kind to body
        val key = keys.keyFor(attempt)
        _state.update { it.copy(isBusy = true, error = null, message = null) }
        viewModelScope.launch {
            runCatching { call(key) }
                .onSuccess {
                    keys.settled(attempt)
                    _state.update { it.copy(isBusy = false, message = done) }
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    keys.failed(attempt, refusal)
                    _state.update { it.copy(isBusy = false, error = failureText(e, refusal)) }
                }
            load()
        }
    }

    // ---- settings ----

    /**
     * Applied at once, saved once the taps stop — as the club policy is. Only
     * the changed fields are sent; the server leaves the rest alone.
     */
    fun changeSettings(change: (MoneySettings) -> MoneySettings) {
        val overview = _state.value.overview ?: return
        val before = overview.settings
        val next = change(before).let { it.copy(autoBillAfterHours = it.autoBillAfterHours.coerceIn(1, MAX_HOURS)) }
        if (next == before) return
        _state.update { it.copy(overview = overview.copy(settings = next)) }
        savingSettings?.cancel()
        savingSettings = viewModelScope.launch {
            delay(saveDelayMs)
            val body = MoneySettingsBody(next.autoBill, next.autoBillAfterHours, next.roundSharesUp)
            runCatching { api.updateMoneySettings(clubId, body) }
                .onSuccess { saved -> _state.update { s -> s.copy(overview = s.overview?.copy(settings = saved)) } }
                .onFailure { e ->
                    _state.update { it.copy(error = failureText(e)) }
                    // Show what is actually in force, not what failed to save.
                    load()
                }
        }
    }

    // ---- bank details ----

    fun openForm() = _state.update { it.copy(form = BankForm()) }

    fun closeForm() = _state.update { it.copy(form = null) }

    /**
     * Add or change the bank details. A missing or wrong password is the form
     * asking again — never a reason to sign anybody out, which is why the
     * server answers 428 and 403 here rather than 401.
     */
    fun saveBankDetails(holder: String, sortCode: String, number: String, again: String, isPersonal: Boolean, password: String) {
        val form = _state.value.form ?: return
        if (form.isSaving) return
        bankDetailsProblem(holder, sortCode, number, again)?.let { problem ->
            _state.update { it.copy(form = form.copy(error = problem)) }
            return
        }
        val body = AddBankDetailsBody(
            holderName = holder.trim(),
            sortCode = sortCode.filter(Char::isDigit),
            accountNumber = number.filter(Char::isDigit),
            isPersonal = isPersonal,
            password = password.takeIf { it.isNotEmpty() },
        )
        _state.update { it.copy(form = form.copy(isSaving = true, error = null)) }
        viewModelScope.launch {
            runCatching { api.addPayoutAccount(clubId, body) }
                .onSuccess { accounts ->
                    _state.update { s ->
                        s.copy(
                            form = null,
                            overview = s.overview?.copy(account = accounts),
                            message = if (accounts.pending != null) t("pay.details_waiting_to_go_live") else t("pay.details_saved"),
                        )
                    }
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    val password = refusal?.code == "reauth_required" || refusal?.code == "wrong_password"
                    val said = failureText(e, refusal)
                    _state.update { s ->
                        val open = s.form ?: return@update s
                        s.copy(form = open.copy(isSaving = false, needsPassword = open.needsPassword || password, error = said))
                    }
                }
        }
    }

    /** "Not right?" — players are told not to pay until the owner has looked. */
    fun freeze(account: PayoutAccount, reason: String?) =
        accountChange(t("pay.details_frozen")) { api.freezePayoutAccount(clubId, account.id, ReasonBody(reason?.trim()?.takeIf { it.isNotEmpty() })) }

    /** The owner only; the button is shown from `is_owner`. */
    fun unfreeze(account: PayoutAccount) =
        accountChange(t("pay.details_unfrozen")) { api.unfreezePayoutAccount(clubId, account.id) }

    /** Remove the details, or cancel a change that has not gone live. */
    fun retire(account: PayoutAccount) =
        accountChange(t("pay.details_removed")) { api.retirePayoutAccount(clubId, account.id) }

    private fun accountChange(done: String, call: suspend () -> PayoutAccounts) {
        if (_state.value.isBusy) return
        _state.update { it.copy(isBusy = true, error = null, message = null) }
        viewModelScope.launch {
            runCatching { call() }
                .onSuccess { accounts ->
                    _state.update { s -> s.copy(isBusy = false, overview = s.overview?.copy(account = accounts), message = done) }
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    _state.update { it.copy(isBusy = false, error = failureText(e, refusal)) }
                    if (refusal?.meansReload == true) load()
                }
        }
    }

    private companion object {
        /** `update_settings` refuses anything outside 1–336 hours. */
        const val MAX_HOURS = 336
    }
}
