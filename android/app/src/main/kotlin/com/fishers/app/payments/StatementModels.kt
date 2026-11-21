package com.fishers.app.payments

import com.fishers.app.clubs.money
import com.fishers.app.i18n.t
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Importing a bank statement: step D of docs/CLUB_PAYMENTS_V2_PLAN.md (§12).
// The shapes are `backend/api/src/routes/statements.rs`.
//
// The statement is the club's whole banking, not only members' payments: it
// stays in memory while the screen is open, goes to the server as it is, and
// never reaches a log line, saved state or a `toString`.

/** What the server proposes for one line of money in. */
enum class StatementAction {
    /** It is the money somebody said they'd sent: tick their "I've paid". */
    Confirm,
    /** Their reference, but they hadn't said: it is put down as paid. */
    Record,
    /** A person has to look: [StatementLine.why] says why. */
    Check,
    /** Nobody's reference — bank interest, a refund from a shop. A word this version does not know reads the same. */
    Unknown,
    /** Applied from this statement before. */
    Already;

    companion object {
        fun of(wire: String?): StatementAction = when (wire) {
            "confirm" -> Confirm
            "record" -> Record
            "check" -> Check
            "already" -> Already
            else -> Unknown
        }
    }
}

/** One line of money in, and what it matches. */
@Serializable
data class StatementLine(
    /** Send it back to apply this line. */
    val hash: String,
    val row: Int = 0,
    /** A date, not a time. */
    val date: String? = null,
    @SerialName("amount_cents") val amountCents: Long = 0,
    /** What the bank wrote, for the treasurer to recognise it. */
    val text: String = "",
    @SerialName("action") val actionName: String = "",
    /** Whose reference it carries. */
    @SerialName("user_id") val userId: String? = null,
    val name: String? = null,
    /** The "I've paid"s a confirm ticks: several when one transfer paid for two juniors. */
    @SerialName("payment_ids") val paymentIds: List<String> = emptyList(),
    /** For a check: `different_amount` or `shared_name`. */
    val why: String? = null,
) {
    val action: StatementAction get() = StatementAction.of(actionName)

    /** Ticked off: applied unless somebody unticks it. */
    val canApply: Boolean get() = action == StatementAction.Confirm || action == StatementAction.Record

    /** Whose it is, or what the bank wrote when it is nobody's. */
    val who: String get() = name?.takeIf { it.isNotBlank() } ?: text

    /** The bank's words never reach a log line. */
    override fun toString(): String = "StatementLine(row=$row, $actionName)"
}

@Serializable
data class StatementSummary(
    val credits: Int = 0,
    val confirm: Int = 0,
    val record: Int = 0,
    val check: Int = 0,
    val unknown: Int = 0,
    val already: Int = 0,
)

/** `POST /clubs/{id}/statement/preview`: changes nothing. Money going out is left out. */
@Serializable
data class StatementPreview(
    val currency: String = "GBP",
    val summary: StatementSummary = StatementSummary(),
    val lines: List<StatementLine> = emptyList(),
) {
    /** "Ticked off": each ticked to start with. */
    val toApply: List<StatementLine> get() = lines.filter { it.canApply }

    /** "Needs a look". */
    val toCheck: List<StatementLine> get() = lines.filter { it.action == StatementAction.Check }

    /** "Not recognised", folded away. */
    val unrecognised: List<StatementLine> get() = lines.filter { it.action == StatementAction.Unknown }

    /** "Already done": applied from this statement before. */
    val already: List<StatementLine> get() = lines.filter { it.action == StatementAction.Already }
}

/** `POST /clubs/{id}/statement/apply`: the statement again, and which of its lines. */
@Serializable
data class StatementBody(val csv: String, val lines: List<String>) {
    /** Never the statement itself. */
    override fun toString(): String = "StatementBody(${lines.size} lines)"
}

/** [skipped]: asked for, but applied meanwhile, or the "I've paid" was decided by somebody else. */
@Serializable
data class StatementApplied(val confirmed: Int = 0, val recorded: Int = 0, val skipped: Int = 0) {
    val ticked: Int get() = confirmed + recorded
}

/**
 * Why a line needs a look, in words: "Two members called SHARMA — the
 * number was left off", "Said £6.00, sent £9.00".
 *
 * The server names neither the surname nor what was said, so both come from
 * what the treasurer can already see: [names], the club's members (a
 * reference is the surname in capitals), and [claims], the payments waiting
 * to be checked. Without a match it says as much as it knows.
 */
fun StatementLine.whyWords(currency: String, names: List<String>, claims: List<Payment>): String = when (why) {
    "shared_name" -> {
        val words = text.uppercase().split(Regex("[^\\p{L}]+")).toSet()
        val shared = names.mapNotNull { it.trim().split(Regex("\\s+")).takeIf { w -> w.size > 1 }?.last()?.uppercase() }
            .groupingBy { it }.eachCount()
            .entries.firstOrNull { (surname, n) -> n >= 2 && surname in words }
        when {
            shared == null -> t("pw4.why_shared")
            shared.value == 2 -> t("pw4.why_shared_two", vars = mapOf("name" to shared.key))
            else -> t("pw4.why_shared_many", vars = mapOf("count" to shared.value, "name" to shared.key))
        }
    }
    "different_amount" -> {
        // The server matches a line to the "I've paid"s of whoever's reference it carries.
        val said = claims.filter { (it.createdBy ?: it.userId) == userId && it.method == PaymentMethod.Transfer }
        val sent = money(amountCents, currency)
        said.singleOrNull()?.let { t("pw4.why_different", vars = mapOf("said" to money(it.amountCents, it.currency), "sent" to sent)) }
            ?: t("pw4.why_different_unknown", vars = mapOf("sent" to sent))
    }
    else -> t("pw4.why_look")
}

/** Under a ticked-off line: whether it ticks somebody's "I've paid" (for how many), or puts it down as paid. */
fun StatementLine.matchWords(): String = when {
    action == StatementAction.Record -> t("pw4.hadnt_said")
    paymentIds.size > 1 -> t("pw4.said_paid_for_n", vars = mapOf("n" to paymentIds.size))
    else -> t("pw4.said_paid")
}

/** "8 payments ticked off." and, when some had changed meanwhile, how many were left alone. */
fun StatementApplied.words(): String = listOfNotNull(
    t("pa4.statement_applied", count = ticked, vars = mapOf("n" to ticked)),
    skipped.takeIf { it > 0 }?.let { t("pw4.applied_skipped", count = it, vars = mapOf("n" to it)) },
).joinToString(" ")

/**
 * What a refused statement says, by its code, in the app's words (and so in
 * Punjabi too); the server's sentence for anything else.
 */
fun statementProblem(code: String?): String? = when (code) {
    "empty_statement" -> t("pw4.statement_empty")
    "unknown_statement" -> t("pw4.statement_unknown")
    "statement_too_long" -> t("pw4.statement_too_long")
    else -> null
}
