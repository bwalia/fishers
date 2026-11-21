package com.fishers.app.payments

import com.fishers.app.clubs.money
import com.fishers.app.i18n.t
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Easy paying, step A of docs/CLUB_PAYMENTS_V2_PLAN.md (§5 and §10):
// pay links shared to WhatsApp, cash at the ground, "all arrived", screenshots,
// and the pay screen in plain words. The shapes are
// `backend/api/src/routes/easy_paying.rs`.

// ---- pay links, for whoever runs the session ----

/**
 * `POST /events/{id}/bill/link`: the bill's open link (made if there is none)
 * and the server's own words for the group. The messages are posted as they
 * are; the app never writes its own, so web, iPhone and Android say the same.
 */
@Serializable
data class BillLink(
    val url: String = "",
    @SerialName("expires_at") val expiresAt: String? = null,
    /** "🏏 Friday nets, Fri 20 Nov: £15.00 each.\nTap to pay: …" */
    @SerialName("bill_message") val billMessage: String = "",
    /** "Still to pay for Friday nets, Fri 20 Nov: Aman and Tom.\nTap to pay: …" */
    @SerialName("reminder_message") val reminderMessage: String = "",
    /** Who still owes, by full name. */
    @SerialName("still_to_pay") val stillToPay: List<String> = emptyList(),
)

/** `POST /events/{id}/bill/link/disable`: how many links closed. */
@Serializable
data class DisabledLinks(val disabled: Int = 0)

/** `POST /events/{id}/bill/cash`: the shares somebody handed over cash for. */
@Serializable
data class CashBody(@SerialName("share_ids") val shareIds: List<String>)

/**
 * What ticking cash came to. [received] is true when a money admin ticked it
 * (it counts as paid); a captain's tick waits for the treasurer.
 */
@Serializable
data class CashRecorded(
    val recorded: Int = 0,
    @SerialName("total_cents") val totalCents: Long = 0,
    val received: Boolean = false,
)

/** `POST /clubs/{id}/payments/confirm`: "All arrived". */
@Serializable
data class ConfirmManyBody(val ids: List<String>)

/** One somebody else already decided is skipped, not refused. */
@Serializable
data class ConfirmedMany(val confirmed: Int = 0, val skipped: Int = 0)

// ---- the pay screen, in plain words ----

/** What is still to pay, oldest first as the server lists them. */
val PayScreen.owedShares: List<Share>
    get() = shares.filter { it.leftCents > 0 && (it.state == ShareState.Owed || it.state == ShareState.PartPaid) }

/**
 * "You owe £5.00 for Friday nets", "You owe £25.00 for Friday nets and 2
 * more", or just "You owe £5.00." when nothing on the list names it.
 */
fun PayScreen.oweHeadline(): String {
    val amount = money(owedCents, currency)
    val owed = owedShares
    val first = owed.firstOrNull()?.title?.takeIf { it.isNotBlank() }
        ?: return t("pay.you_owe_amount", vars = mapOf("amount" to amount))
    val more = owed.size - 1
    return if (more <= 0) {
        t("pa2.you_owe_for", vars = mapOf("amount" to amount, "what" to first))
    } else {
        t("pa2.you_owe_for_and_more", count = more, vars = mapOf("amount" to amount, "what" to first, "n" to more))
    }
}

/** "Aman" from "Aman Gill": how a player would say who they paid. */
fun firstName(name: String): String = name.trim().split(Regex("\\s+")).firstOrNull()?.takeIf { it.isNotEmpty() } ?: name.trim()

/**
 * Who the money goes to, as somebody would say it: the person, for their own
 * account; the account's name, for the club's.
 */
val BankDetails.payeeShortName: String
    get() = if (isPersonal) firstName(holderName) else holderName

/** "Pay Aman Gill, the club secretary." — the name, and what they are to the club. */
fun BankDetails.payeeLine(): String {
    val name = mapOf("name" to holderName)
    if (!isPersonal) return t("pa2.pay_name", vars = name)
    return when (payeeRole) {
        "secretary" -> t("pa2.pay_name_secretary", vars = name)
        "treasurer" -> t("pa2.pay_name_treasurer", vars = name)
        "owner" -> t("pa2.pay_name_owner", vars = name)
        else -> t("pa2.pay_name", vars = name)
    }
}

/** "This is Aman's own bank account. The club uses it to collect money." */
fun BankDetails.whoseAccount(): String =
    if (isPersonal) t("pa2.own_account", vars = mapOf("name" to firstName(holderName))) else t("pa2.club_account")

/** "Waiting for Aman to check it arrived." */
fun BankDetails?.waitingLine(): String =
    if (this != null && isPersonal) t("pa2.waiting_for_name", vars = mapOf("name" to firstName(holderName)))
    else t("pa2.waiting_for_the_club")

/**
 * A payment waiting for the club, as the pay screen lists it: "£5.00 by bank
 * transfer"; "For Jas Gill: £5.63 by bank transfer" when you paid for
 * somebody else; "Paid for you: …" when somebody paid for you. [me] is who is
 * signed in; without it, every one reads as your own.
 */
fun Payment.waitingWords(me: String?): String {
    val amount = money(amountCents, currency)
    val what = if (method == PaymentMethod.Cash) t("pa2.paid_in_cash", vars = mapOf("amount" to amount))
    else t("pa2.paid_by_transfer", vars = mapOf("amount" to amount))
    return when {
        me == null -> what
        userId != me -> t("pa4.claim_for_name", vars = mapOf("name" to name, "what" to what))
        createdBy != null && createdBy != me -> t("pa4.claim_paid_for_you", vars = mapOf("what" to what))
        else -> what
    }
}

/**
 * Everything somebody else needs to pay on your behalf — a son or daughter
 * who does the banking. Sent by the person, from their own phone, to someone
 * they chose: the only place the app puts the account number into words.
 */
fun PayScreen.detailsToSend(amountCents: Long = owedCents, forOthers: Boolean = false): String {
    val a = account ?: return ""
    // Paying for others too, it is more than one thing: the amount says it all.
    val what = owedShares.firstOrNull()?.title?.takeIf { it.isNotBlank() && !forOthers }
    return listOfNotNull(
        if (what != null) {
            t("pa2.details_intro_for", vars = mapOf("amount" to money(amountCents, currency), "club" to clubName, "what" to what))
        } else {
            t("pa2.details_intro", vars = mapOf("amount" to money(amountCents, currency), "club" to clubName))
        },
        "",
        t("pay.copy_all_name", vars = mapOf("name" to a.holderName)),
        t("pay.copy_all_sort_code", vars = mapOf("code" to a.sortCode)),
        t("pay.copy_all_account", vars = mapOf("number" to a.accountNumber)),
        t("pa2.details_reference", vars = mapOf("reference" to reference)),
    ).joinToString("\n")
}

/**
 * Whether this phone has been through "First time? Here's how". Per device,
 * as the plan says: a parent who pays from two phones sees it on each.
 */
interface PayGuideMemory {
    fun seen(): Boolean
    fun markSeen()

    /** For tests, and anywhere there is nothing to remember with. */
    class InMemory(private var seen: Boolean = false) : PayGuideMemory {
        override fun seen() = seen
        override fun markSeen() {
            seen = true
        }
    }
}

// ---- the usual prices ----

/** The usual nets price as words: "£60.00, split between whoever comes". */
fun usualNetsWords(settings: MoneySettings, currency: String): String? =
    settings.usualNets?.copy(currency = currency)?.summary

/**
 * What the price form typed comes to: what to send, or what is wrong. Either
 * price may be left empty — the club may only charge for nets.
 */
sealed interface UsualPricesCheck {
    data class Ok(val body: MoneySettingsBody) : UsualPricesCheck
    data class Invalid(val netsProblem: String?, val feeProblem: String?) : UsualPricesCheck
}

fun checkUsualPrices(netsMode: CostMode, netsText: String, feeText: String): UsualPricesCheck {
    val nets = netsText.takeIf { it.isNotBlank() }?.let { checkCost(netsMode, it) }
    val fee = feeText.takeIf { it.isNotBlank() }?.let { checkCost(CostMode.PerPlayer, it) }
    val netsProblem = (nets as? CostCheck.Invalid)?.message
    val feeProblem = (fee as? CostCheck.Invalid)?.message
    if (netsProblem != null || feeProblem != null) return UsualPricesCheck.Invalid(netsProblem, feeProblem)
    return UsualPricesCheck.Ok(
        MoneySettingsBody(
            defaultNets = nets?.centsOrNull?.let { DefaultPrice(netsMode.wire, it) },
            defaultMatchFeeCents = fee?.centsOrNull,
        ),
    )
}

/** The amount in a check that has one: a usual price over £100 is fine, the schedule form asks again. */
private val CostCheck.centsOrNull: Long?
    get() = when (this) {
        is CostCheck.Ok -> cents
        is CostCheck.Confirm -> cents
        is CostCheck.Invalid -> null
    }
