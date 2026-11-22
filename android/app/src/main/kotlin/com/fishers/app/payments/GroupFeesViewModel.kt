package com.fishers.app.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.clubs.Team
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
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.decodeFromJsonElement

data class GroupFeesState(
    /** The 50 newest, totals only. */
    val fees: List<GroupFee> = emptyList(),
    val isLoading: Boolean = true,
    val loadError: String? = null,
    /** For "who": the roster, the teams and the groups. */
    val members: List<ClubMemberDetail> = emptyList(),
    val teams: List<Team> = emptyList(),
    val priceTypes: List<PriceType> = emptyList(),
    /** A new group fee being made; open when not null. */
    val draft: GroupFeeDraft? = null,
    val draftProblem: String? = null,
    /** One opened, with everybody's lines. */
    val open: GroupFee? = null,
    /** The opened one's pay link, once read: null while it has none (Share makes it). */
    val link: BillLink? = null,
    /** Whether [link] has been read for the opened one: "no link yet" only once it is known. */
    val linkRead: Boolean = false,
    val isBusy: Boolean = false,
    val error: String? = null,
    val message: String? = null,
    /** Something for the screen to hand to the phone — the share sheet, the clipboard — once. */
    val outgoing: Outgoing? = null,
)

/**
 * Group fees, for money admins: a charge with no session — league fees, the
 * tour, kit, match balls. New (who, how much, a due date), the list, one
 * opened, Share to WhatsApp with the server's words, and cancel with why.
 */
class GroupFeesViewModel(
    private val api: PaymentsApi,
    private val clubId: String,
    private val keys: AttemptKeys = AttemptKeys(),
) : ViewModel() {

    private val _state = MutableStateFlow(GroupFeesState())
    val state: StateFlow<GroupFeesState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            coroutineScope {
                val fees = async { runCatching { api.groupFees(clubId) } }
                val members = async { runCatching { api.clubMembers(clubId) } }
                val teams = async { runCatching { api.clubTeams(clubId) } }
                val types = async { runCatching { api.priceTypes(clubId) } }
                val got = fees.await()
                val membersNow = members.await().getOrNull()
                val teamsNow = teams.await().getOrNull()
                val typesNow = types.await().getOrNull()
                _state.update { s ->
                    val base = s.copy(
                        isLoading = false,
                        members = membersNow ?: s.members,
                        teams = teamsNow ?: s.teams,
                        priceTypes = typesNow?.filter { !it.isArchived } ?: s.priceTypes,
                    )
                    got.fold(onSuccess = { base.copy(fees = it, loadError = null) }, onFailure = { e -> base.copy(loadError = failureText(e)) })
                }
            }
        }
    }

    fun dismissMessage() = _state.update { it.copy(message = null, error = null) }

    // ---- a new one ----

    fun startNew() = _state.update { it.copy(draft = GroupFeeDraft(), draftProblem = null, error = null, message = null) }

    fun changeDraft(change: (GroupFeeDraft) -> GroupFeeDraft) =
        _state.update { s -> s.draft?.let { s.copy(draft = change(it), draftProblem = null) } ?: s }

    fun closeDraft() = _state.update { it.copy(draft = null, draftProblem = null) }

    /**
     * Raise it: everybody in it is told. The same form sent again (a retry
     * on a bad signal) carries the same key.
     */
    fun saveDraft() {
        val s = _state.value
        val draft = s.draft ?: return
        if (s.isBusy) return
        val body = when (val check = draft.check()) {
            is GroupFeeCheck.Invalid -> return _state.update { it.copy(draftProblem = check.problem) }
            is GroupFeeCheck.Ok -> check.body
        }
        val attempt = "group-fee:$clubId:$body"
        val key = keys.keyFor(attempt)
        _state.update { it.copy(isBusy = true, draftProblem = null, error = null, message = null) }
        viewModelScope.launch {
            runCatching { retryIfBusy { api.addGroupFee(clubId, key, body) } }
                .onSuccess { made ->
                    keys.settled(attempt)
                    _state.update {
                        it.copy(
                            isBusy = false,
                            draft = null,
                            open = made,
                            // Just made: nobody has shared it yet.
                            link = null,
                            linkRead = true,
                            message = t("pa3.fee_made", count = made.people, vars = mapOf("title" to made.title, "n" to made.people)),
                        )
                    }
                    load()
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    keys.failed(attempt, refusal)
                    _state.update { it.copy(isBusy = false, draftProblem = failureText(e, refusal)) }
                }
        }
    }

    // ---- one opened ----

    /** One group fee with everybody's lines, and its pay link if it has one — read, never made. */
    fun open(billId: String) {
        if (_state.value.open?.id != billId) _state.update { it.copy(link = null, linkRead = false) }
        viewModelScope.launch {
            runCatching { api.groupFee(billId) }
                .onSuccess { fee -> _state.update { it.copy(open = fee) } }
                .onFailure { e -> _state.update { it.copy(error = failureText(e)) } }
        }
        viewModelScope.launch {
            runCatching { api.currentGroupFeeLink(billId) }
                .onSuccess { found ->
                    val link = found.takeIf { it !is JsonNull }?.let { json.decodeFromJsonElement<BillLink>(it) }
                    _state.update { s -> if (s.open == null || s.open.id == billId) s.copy(link = link, linkRead = true) else s }
                }
            // Not read: the buttons still work, and Share makes one.
        }
    }

    fun close() = _state.update { it.copy(open = null, link = null, linkRead = false) }

    /**
     * Share it, remind who hasn't paid, or copy the link: the words are the
     * server's, asked for each time so a reminder names whoever owes now.
     */
    fun share(fee: GroupFee, use: LinkUse) {
        busy({ api.groupFeeLink(fee.id) }) { link ->
            _state.update {
                it.copy(
                    link = link,
                    linkRead = true,
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

    fun handled() = _state.update { it.copy(outgoing = null) }

    fun switchLinkOff(fee: GroupFee) {
        busy({ api.disableGroupFeeLink(fee.id) }) { _state.update { it.copy(link = null, message = t("pa2.link_switched_off")) } }
    }

    /** Cancelled, with why: anything paid becomes credit, and its link closes. */
    fun cancel(fee: GroupFee, reason: String) {
        val why = reason.trim()
        if (why.isEmpty()) return
        busy({ api.cancelGroupFee(fee.id, ReasonBody(why)) }) { done ->
            // Its link closes with it.
            _state.update { it.copy(open = done, link = null, message = t("pa3.fee_cancelled", vars = mapOf("title" to fee.title))) }
            load()
        }
    }

    private val json = Json { ignoreUnknownKeys = true }

    private fun <T> busy(call: suspend () -> T, done: (T) -> Unit) {
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
                    _state.update { it.copy(isBusy = false, error = failureText(e, refusal)) }
                    if (refusal?.meansReload == true) {
                        _state.value.open?.let { open(it.id) }
                        load()
                    }
                }
        }
    }
}
