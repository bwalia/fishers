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
import java.time.Instant

data class EventMoneyState(
    val money: EventMoney? = null,
    val isLoading: Boolean = true,
    /** The ticks on "who came?", while it is open. User ids. */
    val ticked: Set<String> = emptySet(),
    /** Guests typed in by name: nobody on the app, but they came and they pay. */
    val guests: List<String> = emptyList(),
    /** "Who came?" is open: for the first bill, or to re-split one. */
    val choosing: Boolean = false,
    /** What the ticks come to, from the server — the app never splits money itself. */
    val preview: BillPreview? = null,
    /** Why there is no preview: nobody ticked, or the server's sentence. */
    val previewProblem: String? = null,
    val isPreviewing: Boolean = false,
    val isBusy: Boolean = false,
    val error: String? = null,
    val message: String? = null,
    /** Something for the screen to hand to the phone — the share sheet, the clipboard — once. */
    val outgoing: Outgoing? = null,
    /** "Who paid cash?" is open. */
    val cashOpen: Boolean = false,
    /** Shares ticked as paid in cash. */
    val cashTicked: Set<String> = emptySet(),
) {
    val bill: Bill? get() = money?.bill

    /** Nobody ticked is a bill nobody pays: the server refuses it, so the button waits. */
    val canSend: Boolean get() = !isBusy && (ticked.isNotEmpty() || guests.isNotEmpty())

    /** Somebody still owes on this bill: worth reminding, and worth asking who paid cash. */
    val anyoneOwes: Boolean get() = cashCandidates.isNotEmpty()

    /** Who could have handed over cash: still owing, not already said to have paid. */
    val cashCandidates: List<Share>
        get() = money?.shares.orEmpty().filter { it.leftCents > 0 && (it.state == ShareState.Owed || it.state == ShareState.PartPaid) }
}

/** What the money section asks the phone to do with the pay link. */
sealed interface Outgoing {
    /** Post these words: to WhatsApp if it is there, else whatever the share sheet offers. */
    data class Share(val text: String) : Outgoing
    /** Put the link on the clipboard. */
    data class Copy(val url: String) : Outgoing
}

/** Which of the server's words to share. */
enum class LinkUse { Bill, Reminder, CopyLink }

/**
 * An event's money: its cost, who came, the bill and everybody's share — and,
 * for a player, their own share and the way to pay it.
 *
 * Who may do what comes from the server's `can_bill` and `can_manage_money`,
 * never from the app's idea of somebody's role.
 */
class EventMoneyViewModel(
    private val api: PaymentsApi,
    private val eventId: String,
    private val now: () -> Instant = Instant::now,
    /** How long the ticks have to stop changing before the total is asked for. */
    private val previewDelayMs: Long = 300,
    private val keys: AttemptKeys = AttemptKeys(),
) : ViewModel() {

    private val _state = MutableStateFlow(EventMoneyState())
    val state: StateFlow<EventMoneyState> = _state.asStateFlow()

    private var previewing: Job? = null

    /**
     * Read it again. The ticks start from the server's suggestion — who came,
     * or with nothing recorded who said they were going — unless somebody is
     * part way through changing them.
     */
    fun load(keepTicks: Boolean = false) {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            runCatching { api.bill(eventId) }
                .onSuccess { money -> opened(money, keepTicks) }
                // Somebody from the visiting club gets a 403: there is nothing
                // here for them, and nothing has gone wrong.
                .onFailure { _state.update { it.copy(isLoading = false) } }
        }
    }

    private fun opened(money: EventMoney, keepTicks: Boolean) {
        val s = _state.value
        val keep = keepTicks && s.choosing
        // Over, costed and unbilled: "who came?" is the next thing to do.
        val choose = keep || (money.canBill && money.cost != null && money.bill == null && money.hasEnded(now()))
        _state.value = s.copy(
            money = money,
            isLoading = false,
            choosing = choose,
            ticked = if (keep) s.ticked else money.candidates.filter { it.suggested }.map { it.userId }.toSet(),
            guests = if (keep) s.guests else money.guests,
            preview = if (keep) s.preview else null,
            previewProblem = null,
        )
        if (choose) refreshPreview(immediately = true)
    }

    // ---- who came ----

    /** Open "who came?" — before the session is over, or to change a bill already sent. */
    fun startChoosing() {
        val money = _state.value.money ?: return
        if (!money.canBill || money.cost == null) return
        _state.update {
            it.copy(
                choosing = true,
                ticked = money.candidates.filter { c -> c.suggested }.map { c -> c.userId }.toSet(),
                guests = money.guests,
                error = null,
                message = null,
            )
        }
        refreshPreview(immediately = true)
    }

    fun stopChoosing() {
        previewing?.cancel()
        _state.update { it.copy(choosing = false, preview = null, previewProblem = null, isPreviewing = false) }
    }

    fun toggle(userId: String) {
        _state.update { it.copy(ticked = if (userId in it.ticked) it.ticked - userId else it.ticked + userId) }
        refreshPreview()
    }

    /** A guest by name, once: "Gary" twice is the same Gary, as the server agrees. */
    fun addGuest(name: String) {
        val clean = name.trim().split(Regex("\\s+")).joinToString(" ")
        if (clean.isEmpty() || clean.length > 60) return
        if (_state.value.guests.any { it.equals(clean, ignoreCase = true) }) return
        _state.update { it.copy(guests = it.guests + clean) }
        refreshPreview()
    }

    fun removeGuest(name: String) {
        _state.update { it.copy(guests = it.guests - name) }
        refreshPreview()
    }

    /**
     * Ask the server what the ticks come to, a beat after the last tap: the
     * split (and its odd pennies) is the server's, so the total on screen is
     * the total that will be sent.
     */
    private fun refreshPreview(immediately: Boolean = false) {
        previewing?.cancel()
        val s = _state.value
        if (s.ticked.isEmpty() && s.guests.isEmpty()) {
            _state.update { it.copy(preview = null, previewProblem = t("pay.nobody_ticked"), isPreviewing = false) }
            return
        }
        previewing = viewModelScope.launch {
            if (!immediately) delay(previewDelayMs)
            val body = BillBody(attendees = _state.value.ticked.sorted(), guests = _state.value.guests)
            _state.update { it.copy(isPreviewing = true) }
            runCatching { api.previewBill(eventId, body) }
                .onSuccess { p -> _state.update { it.copy(preview = p, previewProblem = null, isPreviewing = false) } }
                .onFailure { e ->
                    _state.update { it.copy(preview = null, previewProblem = failureText(e), isPreviewing = false) }
                }
        }
    }

    /** Send the bill — or, with one already out, re-split it, sending the version it was read at. */
    fun send() {
        val s = _state.value
        if (!s.canSend) return
        val resplit = s.bill != null
        val body = BillBody(attendees = s.ticked.sorted(), guests = s.guests, version = s.bill?.version)
        busy({ api.sendBill(eventId, body) }) { money ->
            previewing?.cancel()
            _state.update {
                it.copy(
                    money = money,
                    choosing = false,
                    preview = null,
                    message = if (resplit) t("pay.bill_resplit") else t("pay.bill_sent"),
                )
            }
        }
    }

    /** Called off after billing, or billed by mistake. What was paid becomes credit. */
    fun cancelBill(reason: String) {
        busy({ api.voidBill(eventId, ReasonBody(reason.trim())) }) { money ->
            _state.update { it.copy(money = money, message = t("pay.bill_cancelled")) }
        }
    }

    /** A junior, the coach, hardship: their share is let off, with the reason on record. */
    fun letOff(share: Share, reason: String) {
        busy({ api.waiveShare(share.id, ReasonBody(reason.trim())) }) {
            _state.update { it.copy(message = t("pay.let_off_done", vars = mapOf("name" to share.name))) }
            load()
        }
    }

    // ---- the cost ----

    fun saveCost(mode: CostMode, cents: Long, note: String?, applyToSeries: Boolean) {
        val body = CostBody(mode.wire, cents, note?.trim()?.takeIf { it.isNotEmpty() }, applyToSeries)
        busy({ api.setCost(eventId, body) }) { saved ->
            val n = saved.seriesUpdated
            _state.update {
                it.copy(message = if (n > 0) t("pay.cost_saved_weeks", count = n, vars = mapOf("n" to n)) else t("pay.cost_saved"))
            }
            load()
        }
    }

    fun removeCost() {
        busy({ api.removeCost(eventId) }) {
            _state.update { it.copy(message = t("pay.cost_removed"), choosing = false) }
            load()
        }
    }

    // ---- sharing to WhatsApp ----

    /**
     * Share the bill, remind who hasn't paid, or copy the link. The link is
     * asked for each time: it is the same link while one is open, but the
     * reminder names whoever still owes now, not when the page was opened.
     */
    fun share(use: LinkUse) {
        busy({ api.billLink(eventId) }) { link ->
            _state.update {
                it.copy(
                    outgoing = when (use) {
                        LinkUse.Bill -> Outgoing.Share(link.billMessage)
                        LinkUse.Reminder -> Outgoing.Share(link.reminderMessage)
                        LinkUse.CopyLink -> Outgoing.Copy(link.url)
                    },
                    message = if (use == LinkUse.CopyLink) t("pa2.link_copied") else null,
                )
            }
        }
    }

    /** The screen has handed [Outgoing] to the phone. */
    fun handled() = _state.update { it.copy(outgoing = null) }

    /** Close every link to this bill: forwarded too far, or posted in the wrong group. */
    fun switchLinkOff() {
        busy({ api.disableBillLink(eventId) }) {
            _state.update { it.copy(message = t("pa2.link_switched_off")) }
        }
    }

    // ---- cash at the ground ----

    fun startCash() = _state.update { it.copy(cashOpen = true, cashTicked = emptySet(), error = null, message = null) }

    fun stopCash() = _state.update { it.copy(cashOpen = false, cashTicked = emptySet()) }

    fun toggleCash(shareId: String) =
        _state.update { it.copy(cashTicked = if (shareId in it.cashTicked) it.cashTicked - shareId else it.cashTicked + shareId) }

    /**
     * Save who paid cash. A money admin's ticks count as received; a
     * captain's wait for the treasurer to have the cash in hand — the server
     * says which, and the sentence follows it.
     */
    fun saveCash() {
        val ids = _state.value.cashTicked.sorted()
        if (ids.isEmpty()) return
        val attempt = "cash:$eventId:$ids"
        val key = keys.keyFor(attempt)
        busy(
            call = { api.cashAtGround(eventId, key, CashBody(ids)) },
            failed = { refusal -> keys.failed(attempt, refusal) },
        ) { done ->
            keys.settled(attempt)
            val amount = money?.let { com.fishers.app.clubs.money(done.totalCents, it.currency) } ?: ""
            val n = done.recorded
            _state.update {
                it.copy(
                    cashOpen = false,
                    cashTicked = emptySet(),
                    message = when {
                        n == 0 -> t("pa2.cash_nothing_new")
                        done.received -> t("pa2.cash_received", count = n, vars = mapOf("n" to n, "amount" to amount))
                        else -> t("pa2.cash_waiting", count = n, vars = mapOf("n" to n, "amount" to amount))
                    },
                )
            }
            load()
        }
    }

    private val money: EventMoney? get() = _state.value.money

    fun dismissMessage() = _state.update { it.copy(message = null, error = null) }

    /**
     * One change at a time. A refusal that means the page is stale — somebody
     * else billed it, re-split it, or decided it — reloads it and says the
     * server's sentence: "Aman changed this a moment ago. Reload."
     */
    private fun <T> busy(
        call: suspend () -> T,
        failed: (com.fishers.app.clubs.Refusal?) -> Unit = {},
        done: (T) -> Unit,
    ) {
        if (_state.value.isBusy) return
        _state.update { it.copy(isBusy = true, error = null, message = null) }
        viewModelScope.launch {
            runCatching { call() }
                .onSuccess { result ->
                    _state.update { it.copy(isBusy = false) }
                    done(result)
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    failed(refusal)
                    _state.update { it.copy(isBusy = false, error = failureText(e, refusal)) }
                    if (refusal?.meansReload == true) {
                        previewing?.cancel()
                        _state.update { it.copy(choosing = false, preview = null, cashOpen = false, cashTicked = emptySet()) }
                        load()
                    }
                }
        }
    }
}
