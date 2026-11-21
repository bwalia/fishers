package com.fishers.app.views.payments

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.clubs.money
import com.fishers.app.i18n.t
import com.fishers.app.net.PaymentsApi
import com.fishers.app.payments.AccountState
import com.fishers.app.payments.BankDetails
import com.fishers.app.payments.ClubDues
import com.fishers.app.payments.Dues
import com.fishers.app.payments.DuesViewModel
import com.fishers.app.payments.PayScreen
import com.fishers.app.payments.PayState
import com.fishers.app.payments.PayViewModel
import com.fishers.app.payments.Payment
import com.fishers.app.payments.PaymentMethod
import com.fishers.app.payments.Share
import com.fishers.app.payments.shortDay
import com.fishers.app.views.clubs.ClubScreen
import com.fishers.app.views.clubs.ErrorLine
import com.fishers.app.views.clubs.Hint
import com.fishers.app.views.clubs.SectionHeading
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator

/**
 * Pay one club: the amount, the bank details and your reference, each to copy
 * into your banking app, then "I've paid".
 */
@Composable
internal fun PayPage(clubId: String, clubName: String) {
    val deps = LocalAppDeps.current
    val model = remember(clubId) { PayViewModel(deps.service<PaymentsApi>(), clubId) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(clubId) { model.load() }

    val name = state.pay?.clubName?.takeIf { it.isNotBlank() } ?: clubName
    ClubScreen(title = if (name.isBlank()) t("pay.pay_the_club") else t("pay.pay_club", vars = mapOf("club" to name))) {
        val pay = state.pay
        when {
            pay == null && state.isLoading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            pay == null -> Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ErrorLine(state.error ?: t("rest.something_went_wrong_plain"))
                TextButton(onClick = model::load, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("rest.try_again")) }
            }
            else -> PayBody(
                pay = pay,
                state = state,
                onClaim = model::claim,
                onUndo = model::undo,
            )
        }
    }
}

@Composable
private fun PayBody(
    pay: PayScreen,
    state: PayState,
    onClaim: (PaymentMethod) -> Unit,
    onUndo: (Payment) -> Unit,
) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // ---- how much ----
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (pay.owedCents > 0) {
                Text(t("pay.you_owe"), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                Text(money(pay.owedCents, pay.currency), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
            } else if (pay.waitingCents <= 0) {
                Text(t("pay.all_paid_up"), style = MaterialTheme.typography.titleLarge)
            }
            if (pay.waitingCents > 0) {
                Hint(t("pay.amount_waiting_to_confirm", vars = mapOf("amount" to money(pay.waitingCents, pay.currency))))
            }
            if (pay.creditCents > 0) {
                Hint(t("pay.you_have_credit", vars = mapOf("amount" to money(pay.creditCents, pay.currency))))
            }
        }

        state.message?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary) }
        state.error?.let { ErrorLine(it) }

        // ---- where to ----
        if (pay.owedCents > 0) {
            val account = pay.account
            when (pay.accountState) {
                AccountState.Active -> if (account != null) {
                    BankDetailsCard(pay, account)
                    Text(t("pay.pay_then_come_back"), style = MaterialTheme.typography.bodyMedium)
                    Button(
                        onClick = { onClaim(PaymentMethod.Transfer) },
                        enabled = !state.isClaiming,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    ) { Text(if (state.isClaiming) t("pay.sending") else t("pay.ive_paid")) }
                }
                AccountState.Frozen -> StopNote(t("pay.details_being_checked"))
                AccountState.None -> Hint(t("pay.no_details_pay_secretary"))
                AccountState.Unreadable -> Hint(t("pay.details_need_entering_again"))
                else -> Unit
            }
            // Smaller, and offered whatever the state of the details: cash
            // at the ground is how a lot of clubs are still paid.
            if (pay.accountState != AccountState.Frozen) {
                TextButton(
                    onClick = { onClaim(PaymentMethod.Cash) },
                    enabled = !state.isClaiming,
                    modifier = Modifier.heightIn(min = 48.dp),
                ) { Text(t("pay.i_paid_cash")) }
            }
        }

        // ---- claims waiting for the club ----
        if (pay.claims.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                SectionHeading(t("pay.waiting_for_the_club"))
                pay.claims.forEach { claim -> ClaimRow(claim, undoing = state.undoing == claim.id, onUndo = { onUndo(claim) }) }
            }
        }

        // ---- what for ----
        if (pay.shares.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                SectionHeading(t("pay.what_its_for"))
                pay.shares.forEach { ShareLine(it) }
            }
        }
    }
}

/** Each detail with its own Copy, then Copy all: banking apps ask for them one box at a time. */
@Composable
private fun BankDetailsCard(pay: PayScreen, account: BankDetails) {
    val context = LocalContext.current
    account.changedAt?.let { AmberNote(t("pay.details_changed_on", vars = mapOf("date" to shortDay(it)))) }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            CopyRow(t("pay.amount"), money(pay.owedCents, pay.currency), copyAs = amountForBank(pay.owedCents)) {
                copy(context, t("pay.amount"), it)
            }
            CopyRow(t("pay.account_name"), account.holderName) { copy(context, t("pay.account_name"), it) }
            if (account.isPersonal) Hint(t("pay.personal_account"))
            CopyRow(t("pay.sort_code"), account.sortCode, mono = true) { copy(context, t("pay.sort_code"), it) }
            CopyRow(t("pay.account_number"), account.accountNumber, mono = true) {
                copy(context, t("pay.account_number"), it, sensitive = true)
            }
            CopyRow(t("pay.reference"), pay.reference, mono = true) { copy(context, t("pay.reference"), it) }
            Hint(t("pay.reference_explainer"))
            OutlinedButton(
                onClick = { copy(context, t("pay.copy_all"), pay.copyAll(), sensitive = true) },
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp).heightIn(min = 48.dp),
            ) {
                Icon(Icons.Filled.ContentCopy, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(t("pay.copy_all"), modifier = Modifier.padding(start = 8.dp))
            }
        }
    }
}

/** "15.00": what a banking app's amount box takes — no symbol, two places. */
private fun amountForBank(cents: Long): String = "%d.%02d".format(java.util.Locale.ROOT, cents / 100, cents % 100)

@Composable
private fun CopyRow(label: String, value: String, mono: Boolean = false, copyAs: String = value, onCopy: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Hint(label)
            Text(
                value,
                style = MaterialTheme.typography.titleMedium,
                fontFamily = if (mono) FontFamily.Monospace else null,
            )
        }
        IconButton(onClick = { onCopy(copyAs) }) {
            Icon(Icons.Filled.ContentCopy, contentDescription = t("pay.copy_what", vars = mapOf("what" to label)))
        }
    }
}

@Composable
private fun ClaimRow(claim: Payment, undoing: Boolean, onUndo: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(money(claim.amountCents, claim.currency), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            Hint(listOfNotNull(claim.method.label.takeIf { it.isNotEmpty() }, claim.reference, shortDay(claim.createdAt).takeIf { it.isNotEmpty() }).joinToString(" · "))
        }
        TextButton(onClick = onUndo, enabled = !undoing, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("pay.undo")) }
    }
    HorizontalDivider()
}

/** "Friday nets · Fri 20 Nov   £15.00 Owed". */
@Composable
internal fun ShareLine(share: Share, trailing: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(share.title, style = MaterialTheme.typography.bodyLarge)
            Hint(shortDay(share.eventStartAt))
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(money(share.amountCents, share.currency), style = MaterialTheme.typography.bodyLarge)
            StateLabel(share.state)
        }
        trailing()
    }
}

// ---- what you owe, across clubs ----

/**
 * "You owe £15.00 to Riverside Strikers" — on Home and in Profile. Opens the
 * list by club. [showSettled] keeps it up for waiting amounts and credit too,
 * which Profile wants and Home does not.
 */
@Composable
fun YouOweCard(dues: Dues?, showSettled: Boolean = false, onOpen: () -> Unit) {
    if (dues == null) return
    val owing = dues.owing
    if (owing.isEmpty() && !(showSettled && dues.hasAnything)) return
    Card(
        Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onOpen)
            .semantics(mergeDescendants = true) { contentDescription = t("pay.open_what_you_owe") },
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                if (owing.isEmpty()) t("pay.payments") else t("pay.you_owe"),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            owing.forEach { club ->
                Text(
                    t("pay.amount_to_club", vars = mapOf("amount" to money(club.owedCents, club.currency), "club" to club.clubName)),
                    style = MaterialTheme.typography.titleMedium,
                )
            }
            dues.clubs.filter { it.waitingCents > 0 }.forEach { club ->
                Hint(t("pay.amount_waiting_to_confirm", vars = mapOf("amount" to money(club.waitingCents, club.currency))))
            }
            Text(t("pay.tap_to_pay"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
        }
    }
}

/** Everything you owe, a club at a time, each with the way to pay it. */
@Composable
internal fun DuesPage() {
    val deps = LocalAppDeps.current
    val nav = LocalNavigator.current
    val model = remember { DuesViewModel(deps.service<PaymentsApi>()) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { model.load() }

    ClubScreen(title = t("pay.payments")) {
        val dues = state.dues
        when {
            dues == null && state.isLoading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            dues == null -> Column(Modifier.padding(24.dp)) {
                ErrorLine(state.error ?: t("rest.something_went_wrong_plain"))
                TextButton(onClick = model::load, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("rest.try_again")) }
            }
            dues.clubs.isEmpty() -> Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
                Text(t("pay.nothing_owed_anywhere"), style = MaterialTheme.typography.bodyLarge)
            }
            else -> Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                dues.clubs.forEach { club -> ClubDuesCard(club, onPay = { nav.push(PayRoute(club.clubId, club.clubName)) }) }
            }
        }
    }
}

@Composable
private fun ClubDuesCard(club: ClubDues, onPay: () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(club.clubName, style = MaterialTheme.typography.titleMedium)
            when {
                club.owedCents > 0 -> AmountLine(t("pay.you_owe"), money(club.owedCents, club.currency), strong = true)
                club.waitingCents <= 0 -> Hint(t("pay.all_paid_up"))
            }
            if (club.waitingCents > 0) {
                Hint(t("pay.amount_waiting_to_confirm", vars = mapOf("amount" to money(club.waitingCents, club.currency))))
            }
            if (club.creditCents > 0) {
                Hint(t("pay.you_have_credit", vars = mapOf("amount" to money(club.creditCents, club.currency))))
            }
            club.shares.forEach { ShareLine(it) }
            if (club.owedCents > 0) {
                Button(onClick = onPay, modifier = Modifier.fillMaxWidth().padding(top = 8.dp).heightIn(min = 48.dp)) {
                    Text(t("pay.pay"))
                }
            } else if (club.waitingCents > 0) {
                // Somewhere to undo a claim made by mistake.
                TextButton(onClick = onPay, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("pay.see_details")) }
            }
        }
    }
}
