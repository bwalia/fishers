package com.fishers.app.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.clubs.money
import com.fishers.app.clubs.refusalOf
import com.fishers.app.i18n.t
import com.fishers.app.net.PaymentsApi
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
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
    /** Which claim a screenshot is going up for. */
    val attaching: String? = null,
    /**
     * This phone has paid by transfer before: "Pay Aman as usual" instead of
     * "First time? Here's how".
     */
    val guideSeen: Boolean = false,
    /** In red. */
    val error: String? = null,
    /** Said quietly: "Thanks — the club will confirm it." */
    val message: String? = null,
    /** Who is signed in, to tell your own passes from those of people you pay for. */
    val me: String? = null,
    // ---- passes ----
    /** The club's passes, each with your own on it. Empty when they could not be read: paying still works. */
    val plans: List<PassPlan> = emptyList(),
    /** `GET /me/passes` in this club: yours, and those of the people you pay for. */
    val passes: List<PassHolder> = emptyList(),
    /** The club's groups, to say "Only for Junior members". */
    val priceTypes: List<PriceType> = emptyList(),
    /** The people you pay for in this club, and what they owe. */
    val people: List<PersonDues> = emptyList(),
    /** The pass being got, by plan id. */
    val joining: String? = null,
    /** The pass being cancelled, by holder id. */
    val cancelling: String? = null,
    // ---- paying for others ----
    /** "Pay for everyone": you and everybody you pay for, in one payment. */
    val forEveryone: Boolean = false,
    /** Friends ticked under "I'm paying for friends too", by user id. */
    val friendsTicked: Set<String> = emptySet(),
) {
    /** Your own passes in this club, cancelled ones included until they end. */
    val ownPasses: List<PassHolder>
        get() {
            // A plan's `mine` has no `covers`: it takes its plan's, which is all it stands in for.
            val mineOnPlans = plans.mapNotNull { p ->
                p.mine?.let { m -> if (m.covers != null) m else m.copy(covers = p.covers, validUntil = p.validUntil, sessions = p.sessions) }
            }
            val ids = mineOnPlans.map { it.id }.toSet()
            val fromMe = passes.filter { if (me != null) it.userId == me else it.id in ids }
            // /me/passes has the standing order; a plan's `mine` stands in if it could not be read.
            return fromMe + mineOnPlans.filter { m -> fromMe.none { it.id == m.id } }
        }

    /** Passes of the people you pay for: "Jas Gill · Monthly nets". */
    val theirPasses: List<PassHolder>
        get() {
            val own = ownPasses.map { it.id }.toSet()
            return passes.filter { it.id !in own }
        }

    /** What you could get: offered, open to players, and not already yours. */
    val offered: List<PassPlan> get() = plans.filter { !it.isArchived && it.openToJoin && it.mine == null }

    /** Whether there is anything at all to show under "Passes". */
    val hasPasses: Boolean get() = ownPasses.isNotEmpty() || theirPasses.isNotEmpty() || offered.isNotEmpty()

    /**
     * This month's charge for a monthly pass is still on the screen to pay,
     * while its standing order is set up: the standing order pays it too, so
     * it must not be paid by hand as well.
     */
    fun standingOrderPaysThisMonth(holder: PassHolder): Boolean {
        if (holder.standingOrder == null || holder.billing != PassBilling.Monthly) return false
        val lines = pay?.shares.orEmpty() + people.flatMap { it.dues.shares }
        // A pass charge is titled "Monthly nets — November 2026".
        return lines.any { it.kind == "pass" && it.userId == holder.userId && it.leftCents > 0 && it.title.startsWith(holder.planName) }
    }

    /** Everybody you pay for who owes something here. */
    val othersOwing: List<PersonDues> get() = people.filter { it.dues.owedCents > 0 }

    /** Friends who still owe on a bill you're on, as the server lists them. */
    val friends: List<Friend> get() = pay?.friends.orEmpty().filter { it.owedCents > 0 }

    /** Paying for more than yourself in this payment. */
    val payingForOthers: Boolean
        get() = if (forEveryone) othersOwing.isNotEmpty() else friendsTicked.isNotEmpty()

    /** The people (not you) this payment is for. */
    val othersInPayment: List<String>
        get() = if (forEveryone) othersOwing.map { it.userId }.sorted() else friendsTicked.sorted()

    /** What to send in the banking app: yours, plus everybody this payment covers. */
    val payingCents: Long
        get() {
            val own = pay?.owedCents ?: 0
            return own + if (forEveryone) {
                othersOwing.sumOf { it.dues.owedCents }
            } else {
                friends.filter { it.userId in friendsTicked }.sumOf { it.owedCents }
            }
        }
}

/**
 * The pay screen: what you owe one club, who the money goes to, the four
 * things to copy into your banking app, and "I've paid". After saying so, a
 * screenshot can go with it, and a mistake can be undone.
 *
 * Below it, the club's passes: yours and how it stands, the standing order
 * for a monthly one, and the ones you could get. With [forEveryone], it pays
 * for you and everybody you pay for at once — a parent and two juniors.
 *
 * A claim makes the share "waiting", never "paid": only the club confirming
 * that the money arrived does that.
 */
class PayViewModel(
    private val api: PaymentsApi,
    private val clubId: String,
    private val keys: AttemptKeys = AttemptKeys(),
    private val guide: PayGuideMemory = PayGuideMemory.InMemory(),
    me: String? = null,
    forEveryone: Boolean = false,
) : ViewModel() {

    private val _state = MutableStateFlow(PayState(guideSeen = guide.seen(), me = me, forEveryone = forEveryone))
    val state: StateFlow<PayState> = _state.asStateFlow()

    /**
     * The pay screen, and beside it the passes and the people you pay for.
     * Only the pay screen has to answer: the rest are extras, and a club
     * whose passes cannot be read today still gets paid.
     */
    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            coroutineScope {
                val pay = async { runCatching { api.payScreen(clubId) } }
                val plans = async { runCatching { api.passes(clubId) } }
                val passes = async { runCatching { api.myPasses() } }
                val types = async { runCatching { api.priceTypes(clubId) } }
                val dues = async { runCatching { api.myDues() } }
                val got = pay.await()
                val plansNow = plans.await().getOrNull()
                val passesNow = passes.await().getOrNull()?.filter { it.clubId == clubId }
                val typesNow = types.await().getOrNull()
                val peopleNow = dues.await().getOrNull()?.peopleIn(clubId)
                _state.update { s ->
                    val extras = s.copy(
                        plans = plansNow ?: s.plans,
                        passes = passesNow ?: s.passes,
                        priceTypes = typesNow ?: s.priceTypes,
                        people = peopleNow ?: s.people,
                    )
                    got.fold(
                        onSuccess = { p ->
                            extras.copy(
                                pay = p,
                                isLoading = false,
                                // A friend who has paid meanwhile drops off the ticks.
                                friendsTicked = extras.friendsTicked.filter { id -> p.friends.any { it.userId == id && it.owedCents > 0 } }.toSet(),
                            )
                        },
                        onFailure = { e -> extras.copy(isLoading = false, error = failureText(e)) },
                    )
                }
            }
        }
    }

    /**
     * "I've paid" (a transfer) or "I paid cash". The amount is left to the
     * server, which takes everything owed; the key is the same on every retry
     * of this tap until the server answers.
     */
    fun claim(method: PaymentMethod) {
        if (_state.value.isClaiming) return
        if (_state.value.payingForOthers) return claimForOthers(method)
        val attempt = "claim:$clubId:${method.wire}"
        val key = keys.keyFor(attempt)
        _state.update { it.copy(isClaiming = true, error = null, message = null) }
        viewModelScope.launch {
            runCatching { retryIfBusy { api.claimPayment(clubId, key, ClaimBody(method = method.wire)) } }
                .onSuccess {
                    keys.settled(attempt)
                    // Paid by transfer once from this phone: next time it is "as usual".
                    if (method == PaymentMethod.Transfer) guide.markSeen()
                    _state.update {
                        it.copy(
                            isClaiming = false,
                            guideSeen = guide.seen(),
                            message = t("pay.thanks_club_will_confirm"),
                        )
                    }
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
                    if (quiet || refusal?.code == "already_decided") load()
                }
        }
    }

    /**
     * Take back a claim nobody has confirmed — tapped by mistake, or not paid
     * after all. One made for somebody else (a junior, a friend) is taken
     * back the same way, and they owe it again.
     */
    fun undo(claim: Payment) {
        if (_state.value.undoing != null) return
        _state.update { it.copy(undoing = claim.id, error = null, message = null) }
        val me = _state.value.me
        val theirs = me != null && claim.userId != me
        viewModelScope.launch {
            runCatching { api.cancelClaim(claim.id) }
                .onSuccess {
                    _state.update {
                        it.copy(
                            undoing = null,
                            message = if (theirs) t("pa4.claim_undone_for", vars = mapOf("name" to claim.name)) else t("pay.claim_undone"),
                        )
                    }
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    _state.update { it.copy(undoing = null, error = failureText(e, refusal)) }
                }
            // Either way the list is out of date: it went, or the club decided it.
            load()
        }
    }

    /**
     * A picture of the payment, already shrunk by the picker to under a
     * megabyte, for the treasurer to see beside it. Optional, and only for a
     * claim still waiting.
     */
    fun attachScreenshot(paymentId: String, jpeg: ByteArray) {
        if (_state.value.attaching != null) return
        _state.update { it.copy(attaching = paymentId, error = null, message = null) }
        viewModelScope.launch {
            runCatching { api.uploadScreenshot(paymentId, JsonUpload.image(jpeg)) }
                .onSuccess {
                    _state.update { it.copy(attaching = null, message = t("pa2.screenshot_added")) }
                    load()
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    _state.update { it.copy(attaching = null, error = failureText(e, refusal)) }
                    // Checked meanwhile: the list shows what happened to it.
                    if (refusal?.meansReload == true) load()
                }
        }
    }

    /** The picker could not make anything of the picture: unreadable, or too big even shrunk. */
    fun screenshotProblem(text: String) = _state.update { it.copy(error = text, message = null) }

    fun dismissMessage() = _state.update { it.copy(message = null, error = null) }

    // ---- paying for others ----

    /** "I'm paying for friends too": tick or untick one. */
    fun toggleFriend(userId: String) = _state.update {
        it.copy(friendsTicked = if (userId in it.friendsTicked) it.friendsTicked - userId else it.friendsTicked + userId)
    }

    /** "I'm paying for friends too" switched off: nobody else is in this payment. */
    fun clearFriends() = _state.update { it.copy(friendsTicked = emptySet()) }

    /**
     * From your own pay screen to Pay for everyone: you and everybody you pay
     * for, in one payment — what a parent who has just undone a junior's
     * payment needs to pay it again.
     */
    fun payForEveryone() = _state.update { it.copy(forEveryone = true, friendsTicked = emptySet(), message = null, error = null) }

    /**
     * One payment for you and the others in it: everybody you pay for, or
     * the friends ticked. Each is recorded for what they owe, under your
     * reference. The key is the same on every retry of the same payment —
     * the same people, the same way — until the server answers.
     */
    private fun claimForOthers(method: PaymentMethod) {
        val s = _state.value
        val people = s.othersInPayment
        val includeMe = (s.pay?.owedCents ?: 0) > 0
        if (people.isEmpty()) return
        val attempt = "for-others:$clubId:${method.wire}:$people:$includeMe"
        val key = keys.keyFor(attempt)
        _state.update { it.copy(isClaiming = true, error = null, message = null) }
        viewModelScope.launch {
            runCatching { retryIfBusy { api.payForOthers(clubId, key, ForOthersBody(method = method.wire, people = people, includeMe = includeMe)) } }
                .onSuccess {
                    keys.settled(attempt)
                    if (method == PaymentMethod.Transfer) guide.markSeen()
                    _state.update {
                        it.copy(
                            isClaiming = false,
                            guideSeen = guide.seen(),
                            friendsTicked = emptySet(),
                            message = t("pay.thanks_club_will_confirm"),
                        )
                    }
                    load()
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    keys.failed(attempt, refusal)
                    val quiet = refusal?.code == "nothing_owed"
                    _state.update {
                        it.copy(
                            isClaiming = false,
                            error = if (quiet) null else failureText(e, refusal),
                            message = if (quiet) refusal.message else null,
                        )
                    }
                    if (quiet || refusal?.meansReload == true) load()
                }
        }
    }

    // ---- passes ----

    /**
     * "Get this pass", for yourself or for somebody you pay for. The first
     * payment is owed at once, so the screen is read again to show it.
     */
    fun getPass(plan: PassPlan, forUserId: String? = null) {
        if (_state.value.joining != null) return
        _state.update { it.copy(joining = plan.id, error = null, message = null) }
        viewModelScope.launch {
            runCatching { api.joinPass(plan.id, JoinPassBody(forUserId)) }
                .onSuccess { holder ->
                    val amount = money(plan.chargeCents.takeIf { it > 0 } ?: plan.priceCents, plan.currency)
                    val name = mapOf("pass" to plan.name, "amount" to amount)
                    _state.update {
                        it.copy(
                            joining = null,
                            message = when (plan.billing) {
                                PassBilling.Monthly -> t("pa3.got_pass_monthly", vars = name)
                                PassBilling.Instalments -> t("pa3.got_pass_parts", vars = name)
                                else -> t("pa3.got_pass_once", vars = name)
                            }.let { said -> if (forUserId != null) t("pa3.got_pass_for", vars = mapOf("name" to holder.name, "said" to said)) else said },
                        )
                    }
                    load()
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    _state.update { it.copy(joining = null, error = failureText(e, refusal)) }
                    if (refusal?.meansReload == true) load()
                }
        }
    }

    /**
     * Cancel a pass — the screen has asked first. A monthly one covers to the
     * end of the month already paid, and the standing order in the bank has
     * to be cancelled too: the app cannot do that, so it says so.
     */
    fun cancelPass(holder: PassHolder) {
        if (_state.value.cancelling != null) return
        _state.update { it.copy(cancelling = holder.id, error = null, message = null) }
        viewModelScope.launch {
            runCatching { api.cancelPass(holder.id) }
                .onSuccess { done ->
                    val until = dayMonth(done.endsOn).takeIf { it.isNotEmpty() }
                    _state.update {
                        it.copy(
                            cancelling = null,
                            message = when {
                                holder.billing == PassBilling.Monthly && until != null ->
                                    t("pa3.cancelled_monthly_done", vars = mapOf("pass" to holder.planName, "date" to until))
                                holder.billing == PassBilling.Monthly -> t("pa3.cancelled_monthly_done_now", vars = mapOf("pass" to holder.planName))
                                else -> t("pa3.cancelled_done", vars = mapOf("pass" to holder.planName))
                            },
                        )
                    }
                    load()
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    _state.update { it.copy(cancelling = null, error = failureText(e, refusal)) }
                    if (refusal?.meansReload == true) load()
                }
        }
    }
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
