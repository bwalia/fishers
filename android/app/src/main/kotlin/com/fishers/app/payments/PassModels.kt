package com.fishers.app.payments

import com.fishers.app.clubs.money
import com.fishers.app.i18n.Strings
import com.fishers.app.i18n.t
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.MonthDay
import java.time.format.DateTimeFormatter
import java.util.Locale

// Passes, prices for juniors and others, group fees and paying for others:
// steps B and C of docs/CLUB_PAYMENTS_V2_PLAN.md (§11). The shapes are
// `backend/api/src/routes/passes.rs`.
//
// As everywhere in payments, every word the server names (`billing`,
// `standing`, a session kind) is kept as the string it sent and read through
// an enum with an `Unknown` arm, so a new word never stops a screen loading.
//
// The words a player reads never say "subscription", "holder", "dependent",
// "price type" or "collection": a pass, a group fee, pays for, prices for
// juniors and others.

// ---- prices for juniors, students, guests ----

/** One of the club's groups with its own price: Junior, Student, Coach (free), Guest. */
@Serializable
data class PriceType(
    val id: String,
    @SerialName("club_id") val clubId: String = "",
    val name: String = "",
    /** Never charged: a coach, a captain. */
    val free: Boolean = false,
    /** The price guests (people not in the club) pay. One per club. */
    @SerialName("for_guests") val forGuests: Boolean = false,
    @SerialName("sort_order") val sortOrder: Int = 0,
    @SerialName("archived_at") val archivedAt: String? = null,
) {
    val isArchived: Boolean get() = archivedAt != null

    /** "Junior", "Coach · free", "Guest · for guests". */
    val label: String
        get() = listOfNotNull(
            name,
            t("pa3.group_free").takeIf { free },
            t("pa3.group_for_guests").takeIf { forGuests },
        ).joinToString(" · ")
}

/** `POST /clubs/{id}/price-types` and `PATCH /price-types/{id}`: only what is sent changes. */
@Serializable
data class PriceTypeBody(
    val name: String? = null,
    val free: Boolean? = null,
    @SerialName("for_guests") val forGuests: Boolean? = null,
    val archived: Boolean? = null,
)

/** `PUT /clubs/{id}/members/{user_id}/price-type`. Null (left out) is the standard price. */
@Serializable
data class MemberPriceTypeBody(@SerialName("price_type_id") val priceTypeId: String? = null)

/** A session's price for one group, as `GET /events/{id}/bill` reads it back. */
@Serializable
data class TypePrice(
    @SerialName("price_type_id") val priceTypeId: String,
    val name: String = "",
    @SerialName("amount_cents") val amountCents: Long = 0,
)

/** A session's price for one group, as the cost form sends it. 0 makes it free for that session. */
@Serializable
data class PriceIn(
    @SerialName("price_type_id") val priceTypeId: String,
    @SerialName("amount_cents") val amountCents: Long,
)

/** "Junior: £3.00 · Guest: £8.00 · Trialist: free" — a session's own prices, under its cost. */
fun typePricesWords(prices: List<TypePrice>, currency: String): String =
    prices.joinToString(" · ") { p ->
        if (p.amountCents == 0L) t("pa3.group_free_here", vars = mapOf("group" to p.name))
        else t("pa3.group_price", vars = mapOf("group" to p.name, "amount" to money(p.amountCents, currency)))
    }

/**
 * What "Different price for juniors?" comes to: the prices to send, or what
 * is wrong. [typed] is by group id; an empty box is the usual price.
 */
sealed interface TypePricesCheck {
    data class Ok(val prices: List<PriceIn>) : TypePricesCheck
    data class Invalid(val problems: Map<String, String>) : TypePricesCheck
}

fun checkTypePrices(typed: Map<String, String>): TypePricesCheck {
    val prices = mutableListOf<PriceIn>()
    val problems = mutableMapOf<String, String>()
    typed.forEach { (id, text) ->
        if (text.isBlank()) return@forEach
        // "0" is a real answer here: free for this session. `parseAmount`
        // says no to nothing at all, rightly everywhere else.
        val digits = text.filter(Char::isDigit)
        val cents = if (digits.isNotEmpty() && digits.all { it == '0' } && '-' !in text) 0L else parseAmount(text)
        when {
            cents == null -> problems[id] = t("pay.amount_not_valid")
            cents > MAX_SHARE_CENTS -> problems[id] = t("pay.amount_too_big")
            else -> prices += PriceIn(id, cents)
        }
    }
    return if (problems.isEmpty()) TypePricesCheck.Ok(prices) else TypePricesCheck.Invalid(problems)
}

// ---- passes ----

/** How a pass is paid for. */
enum class PassBilling(val wire: String) {
    Once("once"), Monthly("monthly"), Instalments("instalments"), Unknown("");

    companion object {
        fun of(wire: String?): PassBilling = entries.firstOrNull { it.wire == wire && it != Unknown } ?: Unknown
    }
}

/** How a pass stands with its payments. */
enum class PassStanding {
    UpToDate,
    /** A payment is late, but it still covers: say so. */
    Behind,
    /** Not covering until it's paid up ("paused", in its words). */
    Suspended,
    Unknown;

    companion object {
        fun of(wire: String?): PassStanding = when (wire) {
            "up_to_date" -> UpToDate
            "behind" -> Behind
            "suspended" -> Suspended
            else -> Unknown
        }
    }
}

/** A kind of session a pass can cover. */
enum class SessionKind(val wire: String) {
    Nets("nets"), Training("training"), Friendly("friendly"), LeagueMatch("league_match"), Tournament("tournament"), Social("social");

    /** "nets", "league matches": the way it sits in "covers nets and training". */
    val words: String
        get() = when (this) {
            Nets -> t("pa3.kind_nets")
            Training -> t("pa3.kind_training")
            Friendly -> t("pa3.kind_friendly")
            LeagueMatch -> t("pa3.kind_league_match")
            Tournament -> t("pa3.kind_tournament")
            Social -> t("pa3.kind_social")
        }

    /** "Nets", for a tick box on its own. */
    val label: String get() = words.replaceFirstChar { it.titlecase(Locale.ROOT) }

    companion object {
        fun of(wire: String?): SessionKind? = entries.firstOrNull { it.wire == wire }
    }
}

/** "nets", "nets and training", "nets, training and league matches". Unknown kinds are left out. */
fun coversWords(covers: List<String>): String? {
    val words = covers.mapNotNull { SessionKind.of(it)?.words }.distinct()
    return when (words.size) {
        0 -> null
        1 -> words[0]
        else -> t("pa3.list_and", vars = mapOf("list" to words.dropLast(1).joinToString(", "), "last" to words.last()))
    }
}

/** "Covers nets and training", "Covers 10 sessions: nets", "Covers nets until 31 Mar", "Membership". */
fun passCoversLine(covers: List<String>, validUntil: String?, sessions: Int?): String {
    val what = coversWords(covers) ?: return t("pa3.covers_membership")
    val until = dayMonth(validUntil).takeIf { it.isNotEmpty() }
    return when {
        sessions != null -> t("pa3.covers_sessions", count = sessions, vars = mapOf("n" to sessions, "what" to what))
        until != null -> t("pa3.covers_until", vars = mapOf("what" to what, "date" to until))
        else -> t("pa3.covers", vars = mapOf("what" to what))
    }
}

/** A pass the club offers: `GET /clubs/{id}/passes`, one entry. */
@Serializable
data class PassPlan(
    val id: String,
    @SerialName("club_id") val clubId: String = "",
    val name: String = "",
    @SerialName("price_cents") val priceCents: Long = 0,
    val currency: String = "GBP",
    @SerialName("billing") val billingName: String = "",
    /** How many parts, for a pass paid in instalments. */
    val instalments: Int? = null,
    val covers: List<String> = emptyList(),
    @SerialName("team_id") val teamId: String? = null,
    /** A date: covers until then. */
    @SerialName("valid_until") val validUntil: String? = null,
    /** A bundle: covers this many sessions. */
    val sessions: Int? = null,
    /** Only for members in this group (juniors, say). */
    @SerialName("price_type_id") val priceTypeId: String? = null,
    /** Players can get it themselves; otherwise the secretary adds them. */
    @SerialName("open_to_join") val openToJoin: Boolean = false,
    @SerialName("archived_at") val archivedAt: String? = null,
    /** One payment: the price, or one part of it. */
    @SerialName("charge_cents") val chargeCents: Long = 0,
    /** How many people are on it now. */
    val holders: Int = 0,
    /** Your own pass on it, if you have one (cancelled ones too, until they end). */
    val mine: PassHolder? = null,
) {
    val billing: PassBilling get() = PassBilling.of(billingName)
    val isArchived: Boolean get() = archivedAt != null

    /** "£20.00 a month", "£60.00", "£120.00, or 3 payments of £40.00". */
    fun priceWords(): String = when (billing) {
        PassBilling.Monthly -> t("pa3.price_monthly", vars = mapOf("amount" to money(chargeCents.orPrice(), currency)))
        PassBilling.Instalments -> t(
            "pa3.price_instalments",
            vars = mapOf("total" to money(priceCents, currency), "n" to (instalments ?: 1), "amount" to money(chargeCents.orPrice(), currency)),
        )
        else -> money(priceCents, currency)
    }

    private fun Long.orPrice(): Long = if (this > 0) this else priceCents

    /** "Covers nets and training", "Covers 10 sessions: nets", "Covers nets until 31 Mar", "Membership". */
    fun coversLine(): String = passCoversLine(covers, validUntil, sessions)

    /** "Only for Junior members", when it is kept for one group and the group is known. */
    fun onlyForWords(types: List<PriceType>): String? =
        priceTypeId?.let { id -> types.firstOrNull { it.id == id }?.name }?.let { t("pa3.only_for_group", vars = mapOf("group" to it)) }
}

/**
 * Somebody's pass: `GET /passes/{id}/holders`, a plan's `mine`, and — with the
 * club, the amount and the standing order — `GET /me/passes`.
 */
@Serializable
data class PassHolder(
    val id: String,
    @SerialName("plan_id") val planId: String = "",
    @SerialName("club_id") val clubId: String = "",
    @SerialName("user_id") val userId: String = "",
    val name: String = "",
    @SerialName("started_on") val startedOn: String? = null,
    /** Set once cancelled: the last day it covers. */
    @SerialName("ends_on") val endsOn: String? = null,
    @SerialName("cancelled_at") val cancelledAt: String? = null,
    /** A money admin said to keep covering them however late the payments are. */
    @SerialName("keep_covering") val keepCovering: Boolean = false,
    @SerialName("plan_name") val planName: String = "",
    @SerialName("billing") val billingName: String = "",
    @SerialName("standing") val standingName: String = "",
    /** A bundle's sessions left. */
    @SerialName("sessions_left") val sessionsLeft: Int? = null,
    /** It covers sessions today. */
    val running: Boolean = false,
    /** When the next monthly payment or part falls. */
    @SerialName("next_charge_on") val nextChargeOn: String? = null,
    // Only from `GET /me/passes`:
    @SerialName("club_name") val clubName: String = "",
    @SerialName("charge_cents") val chargeCents: Long = 0,
    val currency: String = "GBP",
    /** Exactly what to type into a banking app, for a monthly pass not cancelled. */
    @SerialName("standing_order") val standingOrder: StandingOrder? = null,
    /** What the pass covers, until when, for how many sessions: `/me/passes` says, so no plan has to be read for it. */
    val covers: List<String>? = null,
    @SerialName("valid_until") val validUntil: String? = null,
    val sessions: Int? = null,
) {
    val billing: PassBilling get() = PassBilling.of(billingName)
    val standing: PassStanding get() = PassStanding.of(standingName)
    val isCancelled: Boolean get() = cancelledAt != null

    /** "Covers nets and training"; null where the server did not say (a money admin's list). */
    fun coversLine(): String? = covers?.let { passCoversLine(it, validUntil, sessions) }

    /**
     * How the pass stands, as the person on it (or who pays for them) would
     * want it said: the problem first, then what it still covers.
     */
    fun standingWords(validUntil: String? = this.validUntil): String {
        val until = dayMonth(endsOn ?: validUntil).takeIf { it.isNotEmpty() }
        return when {
            isCancelled -> if (until != null) t("pa3.cancelled_covers_until", vars = mapOf("date" to until)) else t("pa3.pass_cancelled_short")
            standing == PassStanding.Suspended -> t("pa3.standing_paused_player")
            standing == PassStanding.Behind -> t("pa3.standing_late_player")
            sessionsLeft == 0 -> t("pa3.used_up")
            !running -> t("pa3.not_covering_now")
            sessionsLeft != null -> t("pa3.sessions_left", count = sessionsLeft, vars = mapOf("n" to sessionsLeft))
            until != null -> t("pa3.covered_until", vars = mapOf("date" to until))
            else -> t("pa3.covered_now")
        }
    }

    /** "Next payment 21 Dec", for a monthly pass or one in parts that is still going. */
    fun nextPaymentWords(): String? =
        nextChargeOn.takeIf { !isCancelled }?.let(::dayMonth)?.takeIf { it.isNotEmpty() }
            ?.let { t("pa3.next_payment_on", vars = mapOf("date" to it)) }

    /** A problem the person needs to act on: a late payment, or paused. */
    val needsPaying: Boolean get() = !isCancelled && (standing == PassStanding.Behind || standing == PassStanding.Suspended)

    /** For the money admin's list: "Paused: payments late · 3 sessions left · Next payment 21 Dec". */
    fun adminWords(): String {
        val first = when {
            isCancelled -> dayMonth(endsOn).takeIf { it.isNotEmpty() }
                ?.let { t("pa3.cancelled_covers_until", vars = mapOf("date" to it)) } ?: t("pa3.pass_cancelled_short")
            standing == PassStanding.Suspended && keepCovering -> t("pa3.standing_late_kept")
            standing == PassStanding.Suspended -> t("pa3.standing_paused")
            standing == PassStanding.Behind -> t("pa3.standing_late")
            standing == PassStanding.UpToDate -> t("pa3.standing_up_to_date")
            else -> null
        }
        val left = sessionsLeft?.let { t("pa3.sessions_left", count = it, vars = mapOf("n" to it)) }
        return listOfNotNull(first, left, nextPaymentWords()).joinToString(" · ")
    }
}

/** What to set up in a banking app for a monthly pass. */
@Serializable
data class StandingOrder(
    @SerialName("amount_cents") val amountCents: Long = 0,
    /** "month", for now. */
    val every: String = "month",
    @SerialName("first_payment_on") val firstPaymentOn: String? = null,
    val reference: String = "",
)

/**
 * Everything somebody who pays for you needs to set the standing order up, in
 * words: sent by the person, from their own phone, to someone they chose.
 */
fun standingOrderToSend(pass: PassHolder, order: StandingOrder, account: BankDetails?, clubName: String): String {
    val amount = money(order.amountCents, pass.currency)
    return listOfNotNull(
        t("pa3.so_intro", vars = mapOf("pass" to pass.planName, "club" to clubName)),
        "",
        account?.let { t("pay.copy_all_name", vars = mapOf("name" to it.holderName)) },
        account?.let { t("pay.copy_all_sort_code", vars = mapOf("code" to it.sortCode)) },
        account?.let { t("pay.copy_all_account", vars = mapOf("number" to it.accountNumber)) },
        t("pay.copy_all_amount", vars = mapOf("amount" to amount)),
        t("pa3.so_every_month"),
        dayMonth(order.firstPaymentOn).takeIf { it.isNotEmpty() }?.let { t("pa3.so_first_payment_line", vars = mapOf("date" to it)) },
        t("pa2.details_reference", vars = mapOf("reference" to order.reference)),
    ).joinToString("\n")
}

/** `POST /clubs/{id}/passes`. A monthly pass has no end date or session count. */
@Serializable
data class NewPassBody(
    val name: String,
    @SerialName("price_cents") val priceCents: Long,
    val billing: String,
    val instalments: Int? = null,
    val covers: List<String> = emptyList(),
    @SerialName("team_id") val teamId: String? = null,
    @SerialName("valid_until") val validUntil: String? = null,
    val sessions: Int? = null,
    @SerialName("price_type_id") val priceTypeId: String? = null,
    @SerialName("open_to_join") val openToJoin: Boolean = true,
)

/** `PATCH /passes/{id}`: only what is sent changes. A new price applies from the next payment. */
@Serializable
data class PassChangeBody(
    val name: String? = null,
    @SerialName("price_cents") val priceCents: Long? = null,
    @SerialName("open_to_join") val openToJoin: Boolean? = null,
    val archived: Boolean? = null,
)

/** `POST /passes/{id}/holders`: a money admin puts somebody on it. */
@Serializable
data class AddHolderBody(
    @SerialName("user_id") val userId: String,
    @SerialName("started_on") val startedOn: String? = null,
)

/** `POST /passes/{id}/join`: for yourself, or for somebody you pay for. */
@Serializable
data class JoinPassBody(@SerialName("for_user_id") val forUserId: String? = null)

/** `PUT /pass-holders/{id}/keep-covering`. */
@Serializable
data class KeepCoveringBody(val on: Boolean)

// ---- the pass templates a secretary starts from ----

/** How long a pass lasts. A monthly one runs until it's cancelled. */
enum class PassLength { UntilDate, Sessions, NoEnd }

/** A pass being made, as typed: amounts are text until it is sent. */
data class PassDraft(
    val name: String,
    val price: String,
    val billing: PassBilling,
    val instalments: Int = 3,
    val covers: Set<SessionKind> = emptySet(),
    val length: PassLength = PassLength.NoEnd,
    val until: LocalDate? = null,
    val sessions: String = "",
    val priceTypeId: String? = null,
    val openToJoin: Boolean = true,
)

enum class PassTemplate {
    WinterNets, TenSessions, MonthlyNets, SeasonMembership, JuniorMembership;

    /** The template, with today's dates and the club's junior group where it has one. */
    fun draft(today: LocalDate, types: List<PriceType>): PassDraft = when (this) {
        WinterNets -> PassDraft(
            name = t("pa3.tpl_winter_nets"),
            price = "60",
            billing = PassBilling.Once,
            covers = setOf(SessionKind.Nets),
            length = PassLength.UntilDate,
            until = MonthDay.of(3, 31).atYear(today.year).let { if (it.isBefore(today)) it.plusYears(1) else it },
        )
        TenSessions -> PassDraft(
            name = t("pa3.tpl_ten_sessions"),
            price = "40",
            billing = PassBilling.Once,
            covers = setOf(SessionKind.Nets),
            length = PassLength.Sessions,
            sessions = "10",
        )
        MonthlyNets -> PassDraft(
            name = t("pa3.tpl_monthly_nets"),
            price = "20",
            billing = PassBilling.Monthly,
            covers = setOf(SessionKind.Nets),
        )
        SeasonMembership -> PassDraft(
            name = t("pa3.tpl_season_membership"),
            price = "120",
            billing = PassBilling.Instalments,
            instalments = 3,
            // The secretary adds people: it's usually paid at the AGM.
            openToJoin = false,
        )
        JuniorMembership -> PassDraft(
            name = t("pa3.tpl_junior_membership"),
            price = "50",
            billing = PassBilling.Once,
            priceTypeId = types.firstOrNull { !it.isArchived && it.name.contains("junior", ignoreCase = true) }?.id,
        )
    }

    val title: String
        get() = when (this) {
            WinterNets -> t("pa3.tpl_winter_nets")
            TenSessions -> t("pa3.tpl_ten_sessions")
            MonthlyNets -> t("pa3.tpl_monthly_nets")
            SeasonMembership -> t("pa3.tpl_season_in_parts")
            JuniorMembership -> t("pa3.tpl_junior_membership")
        }
}

sealed interface PassDraftCheck {
    data class Ok(val body: NewPassBody) : PassDraftCheck
    data class Invalid(val problem: String) : PassDraftCheck
}

/** The server's rules, said before it has to: a name, a price, 2–12 parts, 1–500 sessions, a date for "until". */
fun PassDraft.check(): PassDraftCheck {
    val cleanName = name.trim().split(Regex("\\s+")).joinToString(" ")
    if (cleanName.isEmpty() || cleanName.length > 60) return PassDraftCheck.Invalid(t("pa3.pass_name_needed"))
    val cents = parseAmount(price) ?: return PassDraftCheck.Invalid(t("pay.amount_not_valid"))
    if (cents > MAX_BILL_CENTS) return PassDraftCheck.Invalid(t("pay.amount_too_big"))
    if (billing == PassBilling.Unknown) return PassDraftCheck.Invalid(t("pa3.pass_how_paid_needed"))
    if (billing == PassBilling.Instalments && instalments !in 2..12) return PassDraftCheck.Invalid(t("pa3.parts_2_to_12"))
    // A monthly pass runs until it's cancelled: no date, no count.
    val how = if (billing == PassBilling.Monthly) PassLength.NoEnd else length
    var sessionCount: Int? = null
    var date: String? = null
    when (how) {
        PassLength.Sessions -> {
            sessionCount = sessions.trim().toIntOrNull()?.takeIf { it in 1..500 }
                ?: return PassDraftCheck.Invalid(t("pa3.sessions_1_to_500"))
        }
        PassLength.UntilDate -> date = (until ?: return PassDraftCheck.Invalid(t("pa3.pick_end_date"))).toString()
        PassLength.NoEnd -> Unit
    }
    return PassDraftCheck.Ok(
        NewPassBody(
            name = cleanName,
            priceCents = cents,
            billing = billing.wire,
            instalments = instalments.takeIf { billing == PassBilling.Instalments },
            // In the server's order, so the same pass reads the same everywhere.
            covers = SessionKind.entries.filter { it in covers }.map { it.wire },
            validUntil = date,
            sessions = sessionCount,
            priceTypeId = priceTypeId,
            openToJoin = openToJoin,
        ),
    )
}

/** What a draft would look like as a pass, for the words on the template cards. */
fun PassDraft.preview(currency: String): PassPlan {
    val cents = parseAmount(price) ?: 0
    val parts = if (billing == PassBilling.Instalments) instalments.coerceAtLeast(1) else 1
    return PassPlan(
        id = "",
        name = name,
        priceCents = cents,
        currency = currency,
        billingName = billing.wire,
        instalments = instalments.takeIf { billing == PassBilling.Instalments },
        covers = SessionKind.entries.filter { it in covers }.map { it.wire },
        validUntil = until?.toString()?.takeIf { length == PassLength.UntilDate && billing != PassBilling.Monthly },
        sessions = sessions.toIntOrNull()?.takeIf { length == PassLength.Sessions && billing != PassBilling.Monthly },
        priceTypeId = priceTypeId,
        // Rounded up, as the server does: the last part is never short.
        chargeCents = (cents + parts - 1) / parts,
    )
}

// ---- group fees ----

/**
 * A group fee: a bill with no session — league fees, the tour, match balls.
 * `POST /clubs/{id}/collections`, `GET /collections/{bill_id}` and the list.
 * [shares] are everybody's for a money admin, and empty in the list.
 */
@Serializable
data class GroupFee(
    val id: String,
    @SerialName("club_id") val clubId: String = "",
    val title: String = "",
    @SerialName("mode") val modeName: String = "",
    @SerialName("amount_cents") val amountCents: Long = 0,
    @SerialName("total_cents") val totalCents: Long = 0,
    val currency: String = "GBP",
    val status: String = "",
    val note: String? = null,
    @SerialName("issued_at") val issuedAt: String? = null,
    @SerialName("voided_at") val voidedAt: String? = null,
    @SerialName("void_reason") val voidReason: String? = null,
    @SerialName("due_on") val dueOn: String? = null,
    @SerialName("paid_cents") val paidCents: Long = 0,
    @SerialName("waiting_cents") val waitingCents: Long = 0,
    @SerialName("owed_cents") val owedCents: Long = 0,
    val people: Int = 0,
    val shares: List<Share> = emptyList(),
) {
    val mode: CostMode get() = CostMode.of(modeName)
    val isCancelled: Boolean get() = voidedAt != null || status == "void" || status == "voided"

    /** "£15.00 each, by 6 Dec" or "£45.00 split between 3". */
    fun howMuchWords(): String {
        val how = when (mode) {
            CostMode.PerPlayer -> t("pa3.fee_each", vars = mapOf("amount" to money(amountCents, currency)))
            CostMode.SplitTotal -> t("pa3.fee_split", count = people, vars = mapOf("amount" to money(totalCents, currency), "n" to people))
        }
        val due = dayMonth(dueOn).takeIf { it.isNotEmpty() }?.let { t("pa3.by_date", vars = mapOf("date" to it)) }
        return listOfNotNull(how, due).joinToString(", ")
    }

    /** Somebody still owes: worth a reminder. */
    val anyoneOwes: Boolean get() = !isCancelled && owedCents > 0
}

/** Who a group fee is for. */
enum class FeeWho { Everyone, Team, Group, Names }

/** A group fee being made, as typed. */
data class GroupFeeDraft(
    val title: String = "",
    val mode: CostMode = CostMode.PerPlayer,
    val amount: String = "",
    val who: FeeWho = FeeWho.Everyone,
    val teamId: String? = null,
    val priceTypeId: String? = null,
    val names: Set<String> = emptySet(),
    val guests: List<String> = emptyList(),
    val dueOn: LocalDate? = null,
    val note: String = "",
)

/** `POST /clubs/{id}/collections`: one way of saying who, or only guests. */
@Serializable
data class NewGroupFeeBody(
    val title: String,
    val mode: String,
    @SerialName("amount_cents") val amountCents: Long,
    @SerialName("due_on") val dueOn: String? = null,
    val note: String? = null,
    val everyone: Boolean = false,
    @SerialName("team_id") val teamId: String? = null,
    @SerialName("price_type_id") val priceTypeId: String? = null,
    @SerialName("user_ids") val userIds: List<String>? = null,
    val guests: List<String> = emptyList(),
)

sealed interface GroupFeeCheck {
    data class Ok(val body: NewGroupFeeBody) : GroupFeeCheck
    data class Invalid(val problem: String) : GroupFeeCheck
}

/** What a group fee form comes to: what to send, or the first thing wrong, in the order it is filled in. */
fun GroupFeeDraft.check(): GroupFeeCheck {
    val cleanTitle = title.trim().split(Regex("\\s+")).joinToString(" ")
    if (cleanTitle.isEmpty() || cleanTitle.length > 80) return GroupFeeCheck.Invalid(t("pa3.fee_what_for_needed"))
    val cents = when (val c = checkCost(mode, amount)) {
        is CostCheck.Ok -> c.cents
        is CostCheck.Confirm -> c.cents
        is CostCheck.Invalid -> return GroupFeeCheck.Invalid(c.message)
    }
    val body = NewGroupFeeBody(
        title = cleanTitle,
        mode = mode.wire,
        amountCents = cents,
        dueOn = dueOn?.toString(),
        note = note.trim().takeIf { it.isNotEmpty() }?.take(200),
        guests = guests,
    )
    return when (who) {
        FeeWho.Everyone -> GroupFeeCheck.Ok(body.copy(everyone = true))
        FeeWho.Team -> teamId?.let { GroupFeeCheck.Ok(body.copy(teamId = it)) } ?: GroupFeeCheck.Invalid(t("pa3.fee_pick_team"))
        FeeWho.Group -> priceTypeId?.let { GroupFeeCheck.Ok(body.copy(priceTypeId = it)) } ?: GroupFeeCheck.Invalid(t("pa3.fee_pick_group"))
        FeeWho.Names -> when {
            names.isNotEmpty() -> GroupFeeCheck.Ok(body.copy(userIds = names.sorted()))
            guests.isNotEmpty() -> GroupFeeCheck.Ok(body)
            else -> GroupFeeCheck.Invalid(t("pa3.fee_pick_names"))
        }
    }
}

// ---- paying for others ----

/**
 * `POST /clubs/{id}/payments/for-others`: one payment for several people —
 * those you pay for, or friends on a bill you're on. Each is recorded for
 * what they owe, under your reference.
 */
@Serializable
data class ForOthersBody(
    val method: String,
    val people: List<String>,
    @SerialName("include_me") val includeMe: Boolean = false,
    val note: String? = null,
)

@Serializable
data class ForOthers(
    val payments: List<Payment> = emptyList(),
    @SerialName("total_cents") val totalCents: Long = 0,
    val reference: String? = null,
)

/**
 * A member as "Prices and who pays" sees them: `GET /clubs/{id}/payments/members`,
 * with their price group (null: the standard price) and who pays for them
 * (null: themselves). [managed] means added by name, with no sign-in.
 */
@Serializable
data class MoneyMember(
    @SerialName("user_id") val userId: String,
    val name: String = "",
    @SerialName("price_type_id") val priceTypeId: String? = null,
    @SerialName("payer_id") val payerId: String? = null,
    @SerialName("payer_name") val payerName: String? = null,
    val managed: Boolean = false,
)

/** Somebody on a bill you're on who still owes: for "I'm paying for friends too". */
@Serializable
data class Friend(
    @SerialName("user_id") val userId: String,
    val name: String = "",
    @SerialName("owed_cents") val owedCents: Long = 0,
)

/** `PUT /clubs/{id}/members/{member_id}/payer`. Null (left out): they pay for themselves. */
@Serializable
data class PayerBody(@SerialName("payer_id") val payerId: String? = null)

/** `POST /clubs/{id}/members/managed`: a junior by name, with no sign-in of their own. */
@Serializable
data class ManagedMemberBody(val name: String, @SerialName("payer_id") val payerId: String)

@Serializable
data class ManagedMember(
    @SerialName("user_id") val userId: String,
    val name: String = "",
    @SerialName("payer_id") val payerId: String? = null,
)

// ---- dates ----

/**
 * "6 Dec" for a date (not a time) the server sends as `2026-12-06`; "31 Mar
 * 2028" when it is not this year or next. Empty when it cannot be read.
 */
fun dayMonth(iso: String?, today: LocalDate = LocalDate.now()): String =
    iso?.let {
        runCatching {
            val date = LocalDate.parse(it.take(10))
            val near = date.year == today.year || date.year == today.year + 1 && date.isBefore(today.plusMonths(11))
            DateTimeFormatter.ofPattern(if (near) "d MMM" else "d MMM yyyy", Locale.forLanguageTag(Strings.language.code)).format(date)
        }.getOrNull()
    } ?: ""
