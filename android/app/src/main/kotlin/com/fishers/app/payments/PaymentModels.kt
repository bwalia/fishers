package com.fishers.app.payments

import com.fishers.app.clubs.money
import com.fishers.app.i18n.Strings
import com.fishers.app.i18n.t
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

// Paying the club by bank transfer: `backend/api/src/routes/club_payments.rs`,
// and §11 of docs/PAY_BY_BANK_TRANSFER.md. Money is always minor units plus a
// currency; the app never works a share out itself.
//
// Every state the server names (`state`, `account_state`, `status`, `method`,
// `mode`, `rsvp`) is kept as the string it sent and read through an enum with an
// `Unknown` arm. Network's Json does not coerce, so a closed enum here would
// turn one new word on the server into a whole screen that will not load.

/** A share's state, derived by the server. */
enum class ShareState {
    Owed, PartPaid, Waiting, Paid, Waived, Void, Unknown;

    val label: String
        get() = when (this) {
            Owed -> t("pay.state_owed")
            PartPaid -> t("pay.state_part_paid")
            Waiting -> t("pay.state_waiting")
            Paid -> t("pay.state_paid")
            Waived -> t("pay.state_waived")
            Void -> t("pay.state_void")
            Unknown -> ""
        }

    companion object {
        fun of(wire: String?): ShareState = when (wire) {
            "owed" -> Owed
            "part_paid" -> PartPaid
            "waiting" -> Waiting
            "paid" -> Paid
            "waived" -> Waived
            "void" -> Void
            else -> Unknown
        }
    }
}

/** One person's part of a bill. */
@Serializable
data class Share(
    val id: String,
    @SerialName("bill_id") val billId: String = "",
    @SerialName("event_id") val eventId: String = "",
    val title: String = "",
    @SerialName("event_start_at") val eventStartAt: String? = null,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("guest_name") val guestName: String? = null,
    val name: String = "",
    @SerialName("amount_cents") val amountCents: Long = 0,
    @SerialName("paid_cents") val paidCents: Long = 0,
    @SerialName("waiting_cents") val waitingCents: Long = 0,
    val currency: String = "GBP",
    @SerialName("state") val stateName: String = "",
    val reason: String? = null,
) {
    val state: ShareState get() = ShareState.of(stateName)

    /** Still to pay: neither paid nor said to be paid. */
    val leftCents: Long get() = (amountCents - paidCents - waitingCents).coerceAtLeast(0)

    /** Only a share somebody still owes can be let off. */
    val canLetOff: Boolean get() = state == ShareState.Owed || state == ShareState.PartPaid || state == ShareState.Waiting
}

// ---- the player's side ----

/** `GET /me/dues`: per club, what you owe, what is waiting, and your credit. */
@Serializable
data class Dues(val clubs: List<ClubDues> = emptyList()) {
    /** The clubs still owed something — what the "you owe" card lists. */
    val owing: List<ClubDues> get() = clubs.filter { it.owedCents > 0 }

    /** Anything at all to show under Profile: owed, waiting or credit. */
    val hasAnything: Boolean get() = clubs.any { it.owedCents > 0 || it.waitingCents > 0 || it.creditCents > 0 }
}

@Serializable
data class ClubDues(
    @SerialName("club_id") val clubId: String,
    @SerialName("club_name") val clubName: String = "",
    val currency: String = "GBP",
    @SerialName("owed_cents") val owedCents: Long = 0,
    @SerialName("waiting_cents") val waitingCents: Long = 0,
    @SerialName("credit_cents") val creditCents: Long = 0,
    /** Still to pay or waiting, then the most recent paid ones. */
    val shares: List<Share> = emptyList(),
)

/** What the pay screen can show about the club's bank details. */
enum class AccountState {
    /** The details are below. */
    Active,
    /** The club hasn't added any. */
    None,
    /** Somebody froze them: don't pay. */
    Frozen,
    /** The server cannot open them: the club must enter them again. */
    Unreadable,
    NothingOwed,
    Unknown;

    companion object {
        fun of(wire: String?): AccountState = when (wire) {
            "active" -> Active
            "none" -> None
            "frozen" -> Frozen
            "unreadable" -> Unreadable
            "nothing_owed" -> NothingOwed
            else -> Unknown
        }
    }
}

/**
 * The full details, as the pay screen gets them. The only place the whole
 * account number ever reaches the phone: it is shown and copied, never logged.
 */
@Serializable
data class BankDetails(
    val label: String = "",
    @SerialName("holder_name") val holderName: String = "",
    @SerialName("sort_code") val sortCode: String = "",
    @SerialName("account_number") val accountNumber: String = "",
    @SerialName("is_personal") val isPersonal: Boolean = false,
    /** When these replaced older details, if recently. */
    @SerialName("changed_at") val changedAt: String? = null,
) {
    /** No account number: this is what `toString` would otherwise put in a crash report. */
    override fun toString(): String = "BankDetails($label, $sortCode, ••••${accountNumber.takeLast(4)})"
}

/** `GET /clubs/{id}/pay`. */
@Serializable
data class PayScreen(
    @SerialName("club_id") val clubId: String = "",
    @SerialName("club_name") val clubName: String = "",
    val currency: String = "GBP",
    @SerialName("owed_cents") val owedCents: Long = 0,
    @SerialName("waiting_cents") val waitingCents: Long = 0,
    @SerialName("credit_cents") val creditCents: Long = 0,
    val shares: List<Share> = emptyList(),
    @SerialName("account_state") val accountStateName: String = "",
    val account: BankDetails? = null,
    val reference: String = "",
    /** Your claims nobody has confirmed yet. */
    val claims: List<Payment> = emptyList(),
) {
    val accountState: AccountState get() = AccountState.of(accountStateName)

    /** The details are there and there is something to pay. */
    val canPay: Boolean get() = accountState == AccountState.Active && account != null && owedCents > 0

    /**
     * Everything a banking app asks for, in one paste. The amount first: it is
     * the field people most often get wrong.
     */
    fun copyAll(): String {
        val a = account ?: return ""
        return listOf(
            t("pay.copy_all_amount", vars = mapOf("amount" to money(owedCents, currency))),
            t("pay.copy_all_name", vars = mapOf("name" to a.holderName)),
            t("pay.copy_all_sort_code", vars = mapOf("code" to a.sortCode)),
            t("pay.copy_all_account", vars = mapOf("number" to a.accountNumber)),
            t("pay.copy_all_reference", vars = mapOf("reference" to reference)),
        ).joinToString("\n")
    }
}

/** How a claim was paid, or how a treasurer recorded it. */
enum class PaymentMethod(val wire: String) {
    Transfer("transfer"), Cash("cash"), Card("card"), Credit("credit"), Refund("refund"), Unknown("");

    val label: String
        get() = when (this) {
            Transfer -> t("pay.method_transfer")
            Cash -> t("pay.method_cash")
            Card -> t("pay.method_card")
            Credit -> t("pay.method_credit")
            Refund -> t("pay.method_refund")
            Unknown -> ""
        }

    companion object {
        fun of(wire: String?): PaymentMethod = entries.firstOrNull { it.wire == wire && it != Unknown } ?: Unknown
    }
}

/** A payment: claimed by a player, or recorded by a treasurer. */
@Serializable
data class Payment(
    val id: String,
    @SerialName("club_id") val clubId: String = "",
    @SerialName("user_id") val userId: String? = null,
    @SerialName("guest_name") val guestName: String? = null,
    val name: String = "",
    @SerialName("amount_cents") val amountCents: Long = 0,
    val currency: String = "GBP",
    @SerialName("method") val methodName: String = "",
    val reference: String? = null,
    /** `claimed`, `confirmed`, `rejected`, `cancelled`. */
    val status: String = "",
    val note: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("decided_by_name") val decidedByName: String? = null,
    @SerialName("decision_reason") val decisionReason: String? = null,
) {
    val method: PaymentMethod get() = PaymentMethod.of(methodName)
    val isClaimed: Boolean get() = status == "claimed"
}

/** `POST /clubs/{id}/payments`. The amount defaults to everything owed. */
@Serializable
data class ClaimBody(
    val method: String,
    @SerialName("amount_cents") val amountCents: Long? = null,
    val note: String? = null,
)

// ---- bank details, as admins see them ----

/** Where a set of bank details is in its life. */
enum class PayoutState {
    Active, Pending, Frozen, Superseded, Retired, Unknown;

    companion object {
        fun of(wire: String?): PayoutState = when (wire) {
            "active" -> Active
            "pending" -> Pending
            "frozen" -> Frozen
            "superseded" -> Superseded
            "retired" -> Retired
            else -> Unknown
        }
    }
}

/** One set of bank details. Never the full number: the last four only. */
@Serializable
data class PayoutAccount(
    val id: String,
    val label: String = "",
    @SerialName("holder_name") val holderName: String = "",
    @SerialName("is_personal") val isPersonal: Boolean = false,
    @SerialName("sort_code") val sortCode: String? = null,
    val last4: String = "",
    @SerialName("state") val stateName: String = "",
    @SerialName("live_from") val liveFrom: String? = null,
    @SerialName("created_by_name") val createdByName: String? = null,
    @SerialName("freeze_reason") val freezeReason: String? = null,
    /** False when the server can no longer open the number: enter them again. */
    val readable: Boolean = true,
) {
    val state: PayoutState get() = PayoutState.of(stateName)
}

/** `GET /clubs/{id}/payout-account`, and what every change to it answers with. */
@Serializable
data class PayoutAccounts(
    @SerialName("can_manage") val canManage: Boolean = false,
    @SerialName("is_owner") val isOwner: Boolean = false,
    /** What players are shown. */
    val current: PayoutAccount? = null,
    /** A change waiting out its delay. Admins only. */
    val pending: PayoutAccount? = null,
    /** Frozen details waiting for the owner. Admins only. */
    val frozen: PayoutAccount? = null,
    @SerialName("changed_at") val changedAt: String? = null,
)

/**
 * `POST /clubs/{id}/payout-account`. The password is null for somebody who
 * signs in only with Google or Apple; the server asks (428) when it needs one.
 */
@Serializable
data class AddBankDetailsBody(
    @SerialName("holder_name") val holderName: String,
    @SerialName("sort_code") val sortCode: String,
    @SerialName("account_number") val accountNumber: String,
    val label: String? = null,
    @SerialName("is_personal") val isPersonal: Boolean = false,
    val password: String? = null,
) {
    /** Never the number or the password, wherever this ends up printed. */
    override fun toString(): String = "AddBankDetailsBody($holderName, $sortCode, ••••${accountNumber.takeLast(4)})"
}

/** Freezing, rejecting, letting off and cancelling all take a reason. */
@Serializable
data class ReasonBody(val reason: String? = null)

// ---- the treasurer's overview ----

@Serializable
data class MoneySettings(
    @SerialName("auto_bill") val autoBill: Boolean = true,
    @SerialName("auto_bill_after_hours") val autoBillAfterHours: Int = 24,
    @SerialName("round_shares_up") val roundSharesUp: Boolean = false,
)

/** `PUT /clubs/{id}/payments/settings`: only what is sent changes. */
@Serializable
data class MoneySettingsBody(
    @SerialName("auto_bill") val autoBill: Boolean? = null,
    @SerialName("auto_bill_after_hours") val autoBillAfterHours: Int? = null,
    @SerialName("round_shares_up") val roundSharesUp: Boolean? = null,
)

/** Somebody who owes, is waiting, or has credit. A guest has no user id. */
@Serializable
data class MemberBalance(
    @SerialName("user_id") val userId: String? = null,
    @SerialName("guest_name") val guestName: String? = null,
    val name: String = "",
    @SerialName("owed_cents") val owedCents: Long = 0,
    @SerialName("waiting_cents") val waitingCents: Long = 0,
    @SerialName("credit_cents") val creditCents: Long = 0,
) {
    val key: String get() = userId ?: "guest:${guestName ?: name}"
}

@Serializable
data class MoneyTotals(
    @SerialName("owed_cents") val owedCents: Long = 0,
    @SerialName("waiting_cents") val waitingCents: Long = 0,
    @SerialName("credit_cents") val creditCents: Long = 0,
)

@Serializable
data class BillSummary(
    @SerialName("bill_id") val billId: String,
    @SerialName("event_id") val eventId: String,
    val title: String = "",
    @SerialName("event_start_at") val eventStartAt: String? = null,
    val currency: String = "GBP",
    @SerialName("total_cents") val totalCents: Long = 0,
    @SerialName("paid_cents") val paidCents: Long = 0,
    @SerialName("waiting_cents") val waitingCents: Long = 0,
    @SerialName("owed_cents") val owedCents: Long = 0,
    val people: Int = 0,
    val unpaid: Int = 0,
    val waiting: Int = 0,
)

/** `GET /clubs/{id}/money` — money admins only; 403 for everyone else. */
@Serializable
data class MoneyOverview(
    val currency: String = "GBP",
    val settings: MoneySettings = MoneySettings(),
    val account: PayoutAccounts = PayoutAccounts(),
    @SerialName("to_check") val toCheck: List<Payment> = emptyList(),
    val members: List<MemberBalance> = emptyList(),
    val totals: MoneyTotals = MoneyTotals(),
    val bills: List<BillSummary> = emptyList(),
)

/** `POST /clubs/{id}/payments/record` and `/refund`: a member or a guest, not both. */
@Serializable
data class RecordBody(
    @SerialName("user_id") val userId: String? = null,
    @SerialName("guest_name") val guestName: String? = null,
    @SerialName("amount_cents") val amountCents: Long,
    /** `cash` or `transfer`; the server ignores it on a refund. */
    val method: String? = null,
    val note: String? = null,
)

// ---- an event's cost and bill ----

/** Split a total between whoever came, or the same from each of them. */
enum class CostMode(val wire: String) {
    SplitTotal("split_total"), PerPlayer("per_player");

    val label: String
        get() = when (this) {
            SplitTotal -> t("pay.split_a_total")
            PerPlayer -> t("pay.same_for_everyone")
        }

    companion object {
        /** An unknown mode reads as a fee a head: what the server falls back to as well. */
        fun of(wire: String?): CostMode = if (wire == "split_total") SplitTotal else PerPlayer
    }
}

@Serializable
data class EventCost(
    @SerialName("mode") val modeName: String = "",
    @SerialName("amount_cents") val amountCents: Long = 0,
    val currency: String = "GBP",
    val note: String? = null,
) {
    val mode: CostMode get() = CostMode.of(modeName)

    /** "£60.00 split between whoever comes", "£5.00 each". */
    val summary: String
        get() = when (mode) {
            CostMode.SplitTotal -> t("pay.cost_split_summary", vars = mapOf("amount" to money(amountCents, currency)))
            CostMode.PerPlayer -> t("pay.cost_each_summary", vars = mapOf("amount" to money(amountCents, currency)))
        }
}

/** `PUT /events/{id}/cost`. */
@Serializable
data class CostBody(
    val mode: String,
    @SerialName("amount_cents") val amountCents: Long,
    val note: String? = null,
    @SerialName("apply_to_series") val applyToSeries: Boolean = false,
)

@Serializable
data class CostResponse(
    val cost: EventCost? = null,
    @SerialName("series_updated") val seriesUpdated: Int = 0,
)

@Serializable
data class Bill(
    val id: String,
    @SerialName("total_cents") val totalCents: Long = 0,
    val currency: String = "GBP",
    /** Sent back with a re-split, so two people changing it at once cannot both win. */
    val version: Int = 0,
    val auto: Boolean = false,
    val note: String? = null,
    @SerialName("paid_cents") val paidCents: Long = 0,
    @SerialName("waiting_cents") val waitingCents: Long = 0,
    @SerialName("owed_cents") val owedCents: Long = 0,
    @SerialName("surplus_cents") val surplusCents: Long = 0,
)

/** Somebody who might have come, for the "who came?" ticks. */
@Serializable
data class Candidate(
    @SerialName("user_id") val userId: String,
    val name: String = "",
    /** going, maybe, not_going, invited — or not_invited for a member nobody asked. */
    val rsvp: String = "",
    val attended: Boolean? = null,
    /** Tick to start with: they came, or (nothing recorded yet) said they would. */
    val suggested: Boolean = false,
) {
    /** A member who joined after it was scheduled, or was never asked. */
    val wasAsked: Boolean get() = rsvp != "not_invited"
}

/** `GET /events/{id}/bill`, and what sending, re-splitting and cancelling answer with. */
@Serializable
data class EventMoney(
    @SerialName("event_id") val eventId: String = "",
    @SerialName("club_id") val clubId: String = "",
    val title: String = "",
    @SerialName("start_at") val startAt: String? = null,
    @SerialName("end_at") val endAt: String? = null,
    @SerialName("event_status") val eventStatus: String? = null,
    val cost: EventCost? = null,
    val bill: Bill? = null,
    /** Set the cost; send, re-split or cancel the bill. */
    @SerialName("can_bill") val canBill: Boolean = false,
    /** Let somebody off; see who has paid. */
    @SerialName("can_manage_money") val canManageMoney: Boolean = false,
    /** Everyone's, for whoever runs it; only your own otherwise. */
    val shares: List<Share> = emptyList(),
    @SerialName("my_share") val myShare: Share? = null,
    /** Empty unless [canBill]. */
    val candidates: List<Candidate> = emptyList(),
    /** Guests on the current bill, to carry into a re-split. */
    val guests: List<String> = emptyList(),
    @SerialName("has_payout_account") val hasPayoutAccount: Boolean = false,
    @SerialName("round_shares_up") val roundSharesUp: Boolean = false,
) {
    val currency: String get() = bill?.currency ?: cost?.currency ?: "GBP"

    /** Whether there is anything here for this person at all. */
    val isWorthShowing: Boolean get() = canBill || bill != null && (myShare != null || canManageMoney)

    /** Over, so it is time to say who came. A date the phone cannot read counts as over. */
    fun hasEnded(now: Instant = Instant.now()): Boolean =
        endAt?.let { runCatching { Instant.parse(it) <= now }.getOrDefault(true) } ?: true
}

/** `POST /events/{id}/bill` and `/bill/preview`. `version` only to re-split. */
@Serializable
data class BillBody(
    val attendees: List<String>,
    val guests: List<String> = emptyList(),
    val version: Int? = null,
    val note: String? = null,
)

@Serializable
data class PreviewShare(
    @SerialName("user_id") val userId: String? = null,
    val name: String = "",
    @SerialName("amount_cents") val amountCents: Long = 0,
)

@Serializable
data class BillPreview(
    val shares: List<PreviewShare> = emptyList(),
    @SerialName("total_cents") val totalCents: Long = 0,
    @SerialName("surplus_cents") val surplusCents: Long = 0,
    val currency: String = "GBP",
) {
    /**
     * "£60.00 between 9: 6 pay £6.67, 3 pay £6.66", or "£5.00 each" when
     * everybody pays the same — what the secretary checks before sending.
     */
    val summary: String
        get() {
            val total = money(totalCents, currency)
            val amounts = shares.groupingBy { it.amountCents }.eachCount().toSortedMap(compareByDescending { it })
            val each = amounts.entries.joinToString(", ") { (cents, n) ->
                t("pay.n_pay_amount", count = n, vars = mapOf("n" to n, "amount" to money(cents, currency)))
            }
            return if (amounts.size == 1) {
                t("pay.preview_even", count = shares.size, vars = mapOf("total" to total, "n" to shares.size, "amount" to money(amounts.firstKey(), currency)))
            } else {
                t("pay.preview_uneven", vars = mapOf("total" to total, "n" to shares.size, "each" to each))
            }
        }
}

// ---- amounts typed in ----

/** The most a share or a bill can be: `MAX_SHARE_CENTS` and `MAX_BILL_CENTS` in `money.rs`. */
const val MAX_SHARE_CENTS = 100_000L
const val MAX_BILL_CENTS = 1_000_000L

/** Above this a head, the app asks "are you sure?" before saving: a typo of a zero is easy. */
const val CONFIRM_ABOVE_CENTS = 10_000L

/**
 * "7.50", "£7.50", "7.5", "1,000" → minor units. Null for anything that is not
 * a positive amount with at most two decimal places — "7.505" is not money.
 */
fun parseAmount(text: String): Long? {
    // Checked first: the symbol-stripping below would otherwise read "-5" as 5.
    if ('-' in text) return null
    val cleaned = text.trim().filter { !it.isWhitespace() && it != ',' }.trimStart { !it.isDigit() && it != '.' }
    if (cleaned.isEmpty()) return null
    val match = Regex("""^(\d{0,7})(?:\.(\d{0,2}))?$""").matchEntire(cleaned) ?: return null
    val whole = match.groupValues[1]
    val fraction = match.groupValues[2]
    if (whole.isEmpty() && fraction.isEmpty()) return null
    val cents = (whole.ifEmpty { "0" }.toLong() * 100) + fraction.padEnd(2, '0').toLong()
    return cents.takeIf { it > 0 }
}

/** Minor units as a person would type them: "7.50", "60". For prefilling an amount field. */
fun amountText(cents: Long): String =
    if (cents % 100 == 0L) (cents / 100).toString() else "%d.%02d".format(Locale.ROOT, cents / 100, cents % 100)

/** What a cost typed into a form comes to. */
sealed interface CostCheck {
    data class Ok(val cents: Long) : CostCheck
    /** More than £100 a head: fine, once somebody says so. */
    data class Confirm(val cents: Long) : CostCheck
    data class Invalid(val message: String) : CostCheck
}

/**
 * The same limits as the server, said before it has to: at most £1,000 a head
 * and £10,000 in all, and a question above £100 a head. A split total's head
 * count is not known until the bill, so only a fee a head is asked about.
 */
fun checkCost(mode: CostMode, text: String): CostCheck {
    val cents = parseAmount(text) ?: return CostCheck.Invalid(t("pay.amount_not_valid"))
    val cap = if (mode == CostMode.PerPlayer) MAX_SHARE_CENTS else MAX_BILL_CENTS
    if (cents > cap) return CostCheck.Invalid(t("pay.amount_too_big"))
    return if (mode == CostMode.PerPlayer && cents > CONFIRM_ABOVE_CENTS) CostCheck.Confirm(cents) else CostCheck.Ok(cents)
}

// ---- bank details typed in ----

/** Spaces and dashes are how people type these; the digits are what count. */
private fun digitsOf(text: String): String = text.filter { it != ' ' && it != '-' }

/**
 * What is wrong with a bank details form, in the order it is filled in; null
 * when it can be sent. The number is typed twice because there is no modulus
 * check yet: a slip of one digit sends a club's subs to a stranger.
 */
fun bankDetailsProblem(holder: String, sortCode: String, number: String, again: String): String? {
    val code = digitsOf(sortCode)
    val digits = digitsOf(number)
    return when {
        holder.isBlank() -> t("pay.holder_name_needed")
        code.length != 6 || !code.all(Char::isDigit) -> t("pay.sort_code_six_digits")
        digits.length !in 7..8 || !digits.all(Char::isDigit) -> t("pay.account_number_eight_digits")
        digits != digitsOf(again) -> t("pay.account_numbers_differ")
        else -> null
    }
}

// ---- dates ----

/** "Sat 21 Nov", in the reader's zone and the app's language. */
fun shortDay(iso: String?, zone: ZoneId = ZoneId.systemDefault()): String =
    iso?.let {
        runCatching {
            DateTimeFormatter.ofPattern("EEE d MMM", Locale.forLanguageTag(Strings.language.code))
                .withZone(zone)
                .format(Instant.parse(it))
        }.getOrNull()
    } ?: ""

/** "Sat 21 Nov, 14:30" — when a change of bank details goes live. */
fun dayAndTime(iso: String?, zone: ZoneId = ZoneId.systemDefault()): String =
    iso?.let {
        runCatching {
            DateTimeFormatter.ofPattern("EEE d MMM, ${com.fishers.app.fixtures.clockPattern()}", Locale.forLanguageTag(Strings.language.code))
                .withZone(zone)
                .format(Instant.parse(it))
        }.getOrNull()
    } ?: ""
