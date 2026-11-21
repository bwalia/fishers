package com.fishers.app.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.clubs.ClubMemberDetail
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

/** A choice that was made, even when what was chosen is "none". */
data class Pick<T>(val value: T)

/**
 * What this phone set for a member while the page was open. The server does
 * not read a member's group or payer back yet, so these are all the page can
 * show; null in a field means "not changed here".
 */
data class MemberMoney(
    /** Set to the standard price: [groupSet] with a null [groupId]. */
    val groupSet: Boolean = false,
    val groupId: String? = null,
    val payerSet: Boolean = false,
    val payerId: String? = null,
)

data class PricesAdminState(
    /** Every group, those no longer used included. */
    val types: List<PriceType> = emptyList(),
    val members: List<ClubMemberDetail> = emptyList(),
    val isLoading: Boolean = true,
    val loadError: String? = null,
    val known: Map<String, MemberMoney> = emptyMap(),
    val isBusy: Boolean = false,
    val error: String? = null,
    val message: String? = null,
) {
    val inUse: List<PriceType> get() = types.filter { !it.isArchived }.sortedBy { it.sortOrder }
    val notInUse: List<PriceType> get() = types.filter { it.isArchived }

    /** Members on the books, by name: the list a secretary scans for a junior. */
    val roster: List<ClubMemberDetail> get() = members.filter { it.isOnTheBooks }.sortedBy { it.name.lowercase() }

    fun nameOf(userId: String?): String? = members.firstOrNull { it.userId == userId }?.name
}

/**
 * Prices for juniors, students and others, for money admins: name the
 * groups, mark one free or for guests, put a member in one, say who pays for
 * whom, and add a junior by name for a parent to pay for.
 */
class PricesAdminViewModel(
    private val api: PaymentsApi,
    private val clubId: String,
) : ViewModel() {

    private val _state = MutableStateFlow(PricesAdminState())
    val state: StateFlow<PricesAdminState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            coroutineScope {
                val types = async { runCatching { api.priceTypes(clubId) } }
                val members = async { runCatching { api.clubMembers(clubId) } }
                val got = types.await()
                val membersNow = members.await().getOrNull()
                _state.update { s ->
                    val base = s.copy(isLoading = false, members = membersNow ?: s.members)
                    got.fold(onSuccess = { base.copy(types = it, loadError = null) }, onFailure = { e -> base.copy(loadError = failureText(e)) })
                }
            }
        }
    }

    fun dismissMessage() = _state.update { it.copy(message = null, error = null) }

    // ---- the groups ----

    /** A new group: "Junior", "Student", "Coach" (free), "Guest" (for guests). Null when it can be sent. */
    fun addGroup(name: String, free: Boolean, forGuests: Boolean): String? {
        val clean = name.trim().split(Regex("\\s+")).joinToString(" ")
        if (clean.isEmpty() || clean.length > 30) return t("pa3.group_name_needed")
        busy({ api.addPriceType(clubId, PriceTypeBody(name = clean, free = free, forGuests = forGuests)) }) { made ->
            _state.update { s -> s.copy(types = s.types + made, message = t("pa3.group_added", vars = mapOf("group" to made.name))) }
        }
        return null
    }

    /** Rename it, make it free or for guests, or stop (and start) using it. */
    fun changeGroup(type: PriceType, body: PriceTypeBody, said: String? = null) {
        busy({ api.changePriceType(type.id, body) }) { changed ->
            _state.update { s -> s.copy(types = s.types.map { if (it.id == changed.id) changed else it }, message = said) }
        }
    }

    // ---- members ----

    /**
     * A member's group (null: the standard price) and who pays for them
     * (null: themselves) — whichever of the two was picked, one after the
     * other. Each is remembered on the page as soon as the server has it.
     */
    fun saveMember(member: ClubMemberDetail, group: Pick<PriceType?>?, payer: Pick<ClubMemberDetail?>?) {
        if (group == null && payer == null) return
        val said = mutableListOf<String>()
        busy({
            group?.let { pick ->
                api.setMemberPriceType(clubId, member.userId, MemberPriceTypeBody(pick.value?.id))
                noteDown(member.userId) { it.copy(groupSet = true, groupId = pick.value?.id) }
                said += pick.value?.let { t("pa3.member_in_group", vars = mapOf("name" to member.name, "group" to it.name)) }
                    ?: t("pa3.member_standard_price", vars = mapOf("name" to member.name))
            }
            payer?.let { pick ->
                api.setPayer(clubId, member.userId, PayerBody(pick.value?.userId))
                noteDown(member.userId) { it.copy(payerSet = true, payerId = pick.value?.userId) }
                said += pick.value?.let { t("pa3.now_pays_for", vars = mapOf("payer" to it.name, "name" to member.name)) }
                    ?: t("pa3.pays_for_themselves", vars = mapOf("name" to member.name))
            }
        }) { _state.update { it.copy(message = said.joinToString(" ")) } }
    }

    private fun noteDown(userId: String, change: (MemberMoney) -> MemberMoney) =
        _state.update { s -> s.copy(known = s.known + (userId to change(s.known[userId] ?: MemberMoney()))) }

    /**
     * A junior by name, with no sign-in of their own, paid for by [payer].
     * Null when it can be sent; the reason it cannot otherwise.
     */
    fun addJunior(name: String, payer: ClubMemberDetail?): String? {
        val clean = name.trim().split(Regex("\\s+")).joinToString(" ")
        if (clean.isEmpty() || clean.length > 70) return t("pa3.junior_name_needed")
        val who = payer ?: return t("pa3.junior_payer_needed")
        busy({ api.addJunior(clubId, ManagedMemberBody(clean, who.userId)) }) { made ->
            _state.update { s ->
                s.copy(
                    known = s.known + (made.userId to MemberMoney(payerSet = true, payerId = who.userId)),
                    message = t("pa3.junior_added", vars = mapOf("name" to made.name, "payer" to who.name)),
                )
            }
            load()
        }
        return null
    }

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
                    if (refusal?.meansReload == true) load()
                }
        }
    }
}
