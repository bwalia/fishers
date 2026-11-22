package com.fishers.app.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.clubs.Refusal
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
import java.time.LocalDate

data class PassesAdminState(
    /** Every pass, those no longer offered included (at the bottom). */
    val plans: List<PassPlan> = emptyList(),
    val isLoading: Boolean = true,
    /** It could not be read: the server's sentence. */
    val loadError: String? = null,
    val priceTypes: List<PriceType> = emptyList(),
    /** The roster, for "Add somebody". */
    val members: List<ClubMemberDetail> = emptyList(),
    /** The pass opened, and who is on it. */
    val openId: String? = null,
    val holders: List<PassHolder> = emptyList(),
    val holdersLoading: Boolean = false,
    /** A new pass being made from a template; open when not null. */
    val draft: PassDraft? = null,
    val draftProblem: String? = null,
    val isBusy: Boolean = false,
    val error: String? = null,
    val message: String? = null,
) {
    val open: PassPlan? get() = plans.firstOrNull { it.id == openId }
    val offered: List<PassPlan> get() = plans.filter { !it.isArchived }
    val stopped: List<PassPlan> get() = plans.filter { it.isArchived }

    /** Who could be added: active members not already on it (a cancelled pass can be started again). */
    val canAdd: List<ClubMemberDetail>
        get() {
            val on = holders.filter { !it.isCancelled }.map { it.userId }.toSet()
            return members.filter { it.isOnTheBooks && it.userId !in on }.sortedBy { it.name.lowercase() }
        }
}

/**
 * Passes, for money admins (§11, "What each app builds", 4): make one from a
 * template, see who is on each and how they stand, add somebody, cancel, and
 * keep covering somebody whose payments are late. Who may do it is the
 * server's 403, as everywhere in payments.
 */
class PassesAdminViewModel(
    private val api: PaymentsApi,
    private val clubId: String,
    private val today: () -> LocalDate = LocalDate::now,
) : ViewModel() {

    private val _state = MutableStateFlow(PassesAdminState())
    val state: StateFlow<PassesAdminState> = _state.asStateFlow()

    /** The passes; the groups and the roster alongside, without which only the pickers are emptier. */
    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            coroutineScope {
                val plans = async { runCatching { api.passes(clubId, all = true) } }
                val types = async { runCatching { api.priceTypes(clubId) } }
                val members = async { runCatching { api.clubMembers(clubId) } }
                val got = plans.await()
                val typesNow = types.await().getOrNull()
                val membersNow = members.await().getOrNull()
                _state.update { s ->
                    val base = s.copy(priceTypes = typesNow ?: s.priceTypes, members = membersNow ?: s.members, isLoading = false)
                    got.fold(
                        onSuccess = { base.copy(plans = it, loadError = null) },
                        onFailure = { e -> base.copy(loadError = failureText(e)) },
                    )
                }
            }
        }
    }

    fun dismissMessage() = _state.update { it.copy(message = null, error = null) }

    // ---- a new pass ----

    fun startFrom(template: PassTemplate) =
        _state.update { it.copy(draft = template.draft(today(), it.priceTypes), draftProblem = null, error = null, message = null) }

    fun changeDraft(change: (PassDraft) -> PassDraft) =
        _state.update { s -> s.draft?.let { s.copy(draft = change(it), draftProblem = null) } ?: s }

    fun closeDraft() = _state.update { it.copy(draft = null, draftProblem = null) }

    /** Make the pass. Its problems are said on the form; the server's too. */
    fun saveDraft() {
        val s = _state.value
        val draft = s.draft ?: return
        if (s.isBusy) return
        val body = when (val check = draft.check()) {
            is PassDraftCheck.Invalid -> return _state.update { it.copy(draftProblem = check.problem) }
            is PassDraftCheck.Ok -> check.body
        }
        busy({ api.addPass(clubId, body) }, onRefused = { said -> _state.update { it.copy(draftProblem = said) } }) { made ->
            _state.update { it.copy(draft = null, message = t("pa3.pass_made", vars = mapOf("pass" to made.name))) }
            load()
        }
    }

    // ---- one pass ----

    /** Open a pass: who is on it, and how each stands. */
    fun open(passId: String) {
        _state.update { it.copy(openId = passId, holdersLoading = true) }
        viewModelScope.launch {
            runCatching { api.passHolders(passId) }
                .onSuccess { list -> _state.update { s -> if (s.openId == passId) s.copy(holders = sorted(list), holdersLoading = false) else s } }
                .onFailure { e -> _state.update { it.copy(holdersLoading = false, error = failureText(e)) } }
        }
    }

    /** Back to the list. */
    fun closeOpen() = _state.update { it.copy(openId = null, holders = emptyList()) }

    /** Running ones first, then by name: the list a treasurer reads down. */
    private fun sorted(list: List<PassHolder>) = list.sortedWith(compareBy<PassHolder> { it.isCancelled }.thenBy { it.name.lowercase() })

    private fun reopen() {
        _state.value.openId?.let(::open)
        load()
    }

    /** Put somebody on the open pass. The first payment is charged at once, and they are told. */
    fun add(member: ClubMemberDetail) {
        val plan = _state.value.open ?: return
        busy({ api.addToPass(plan.id, AddHolderBody(member.userId)) }) {
            _state.update { it.copy(message = t("pa3.added_to_pass", vars = mapOf("name" to member.name, "pass" to plan.name))) }
            reopen()
        }
    }

    /** Take somebody off — asked first on the screen. A monthly pass runs to the end of the month paid. */
    fun cancel(holder: PassHolder) {
        busy({ api.cancelPass(holder.id) }) { done ->
            val until = dayMonth(done.endsOn).takeIf { it.isNotEmpty() && done.billing == PassBilling.Monthly }
            _state.update {
                it.copy(
                    message = until?.let { d -> t("pa3.holder_cancelled_until", vars = mapOf("name" to holder.name, "date" to d)) }
                        ?: t("pa3.holder_cancelled", vars = mapOf("name" to holder.name)),
                )
            }
            reopen()
        }
    }

    /** Keep covering somebody however late their payments are — or stop. */
    fun keepCovering(holder: PassHolder, on: Boolean) {
        busy({ api.keepCovering(holder.id, KeepCoveringBody(on)) }) { done ->
            _state.update { s -> s.copy(holders = sorted(s.holders.map { if (it.id == done.id) done else it })) }
        }
    }

    /** Players can get it themselves from the pay screen, or only the secretary adds them. */
    fun setOpenToJoin(plan: PassPlan, on: Boolean) = change(plan, PassChangeBody(openToJoin = on), null)

    /**
     * A new price, from the next payment. Everybody on a monthly pass is told
     * to change their standing order: the screen says so before it is sent.
     */
    fun changePrice(plan: PassPlan, text: String): String? {
        val cents = parseAmount(text) ?: return t("pay.amount_not_valid")
        if (cents > MAX_BILL_CENTS) return t("pay.amount_too_big")
        change(plan, PassChangeBody(priceCents = cents), t("pa3.price_changed"))
        return null
    }

    /** No longer offered: nobody new can get it. Those on it keep it. */
    fun stopOffering(plan: PassPlan) = change(plan, PassChangeBody(archived = true), t("pa3.pass_stopped", vars = mapOf("pass" to plan.name)))

    fun offerAgain(plan: PassPlan) = change(plan, PassChangeBody(archived = false), t("pa3.pass_offered_again", vars = mapOf("pass" to plan.name)))

    private fun change(plan: PassPlan, body: PassChangeBody, said: String?) {
        busy({ api.changePass(plan.id, body) }) { changed ->
            _state.update { s ->
                // The list answers without `mine`, and without "all": keep what the list knew.
                s.copy(plans = s.plans.map { if (it.id == changed.id) changed.copy(mine = it.mine) else it }, message = said)
            }
        }
    }

    /**
     * One change at a time. A refusal that means the page is out of date
     * (somebody else cancelled it, it is already on) reads it again.
     */
    private fun <T> busy(call: suspend () -> T, onRefused: ((String) -> Unit)? = null, done: (T) -> Unit) {
        if (_state.value.isBusy) return
        _state.update { it.copy(isBusy = true, error = null, message = null) }
        viewModelScope.launch {
            runCatching { call() }
                .onSuccess { result ->
                    _state.update { it.copy(isBusy = false) }
                    done(result)
                }
                .onFailure { e ->
                    val refusal: Refusal? = refusalOf(e)
                    val said = failureText(e, refusal)
                    _state.update { it.copy(isBusy = false, error = if (onRefused == null) said else null) }
                    onRefused?.invoke(said)
                    if (refusal?.meansReload == true) reopen()
                }
        }
    }
}
