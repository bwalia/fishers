package com.fishers.app.views.payments

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fishers.app.clubs.money
import com.fishers.app.i18n.t
import com.fishers.app.payments.BankDetails
import com.fishers.app.payments.PassBilling
import com.fishers.app.payments.PassHolder
import com.fishers.app.payments.PassPlan
import com.fishers.app.payments.PayState
import com.fishers.app.payments.StandingOrder
import com.fishers.app.payments.dayMonth
import com.fishers.app.payments.standingOrderToSend
import com.fishers.app.views.clubs.SectionHeading

/**
 * "Passes", on the club's pay screen (§11, "What each app builds", 1): your
 * own pass and how it stands, the standing order to set up for a monthly
 * one, the passes of anybody you pay for, then each pass the club offers in
 * one line with Get this pass. Nothing at all when the club has none.
 */
@Composable
internal fun PassesPart(
    state: PayState,
    clubName: String,
    onGet: (PassPlan, String?) -> Unit,
    onCancel: (PassHolder) -> Unit,
) {
    if (!state.hasPasses) return
    var getting by remember { mutableStateOf<PassPlan?>(null) }
    var cancelling by remember { mutableStateOf<PassHolder?>(null) }
    val account = state.pay?.account

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeading(t("pa3.passes"))
        state.ownPasses.forEach { holder ->
            PassCard(
                holder = holder,
                plan = state.planOf(holder),
                title = holder.planName,
                own = true,
                account = account,
                clubName = clubName,
                busy = state.cancelling == holder.id,
                onCancel = { cancelling = holder },
            )
        }
        state.theirPasses.forEach { holder ->
            PassCard(
                holder = holder,
                plan = state.planOf(holder),
                title = t("pa3.name_and_pass", vars = mapOf("name" to holder.name, "pass" to holder.planName)),
                own = false,
                account = account,
                clubName = clubName,
                busy = state.cancelling == holder.id,
                onCancel = { cancelling = holder },
            )
        }
        if (state.offered.isNotEmpty()) {
            Text(
                if (state.ownPasses.isEmpty()) t("pa3.passes_offered_intro") else t("pa3.passes_offered_more"),
                style = MaterialTheme.typography.bodyLarge,
            )
            state.offered.forEach { plan ->
                OfferRow(plan, onlyFor = plan.onlyForWords(state.priceTypes), busy = state.joining == plan.id, onGet = { getting = plan })
            }
        }
    }

    getting?.let { plan ->
        GetPassDialog(
            plan = plan,
            people = state.people.map { it.userId to it.name },
            onYes = { who -> getting = null; onGet(plan, who) },
            onNo = { getting = null },
        )
    }
    cancelling?.let { holder ->
        CancelPassDialog(holder, onYes = { cancelling = null; onCancel(holder) }, onNo = { cancelling = null })
    }
}

/** One pass the club offers: "Monthly nets", "£20.00 a month · Covers nets and training", and the button. */
@Composable
private fun OfferRow(plan: PassPlan, onlyFor: String?, busy: Boolean, onGet: () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(plan.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(plan.priceWords(), style = MaterialTheme.typography.bodyLarge)
            Body(plan.coversLine())
            onlyFor?.let { Body(it) }
            OutlinedButton(onClick = onGet, enabled = !busy, modifier = Modifier.fillMaxWidth().padding(top = 4.dp).heightIn(min = 48.dp)) {
                Text(if (busy) t("pay.sending") else t("pa3.get_this_pass"))
            }
        }
    }
}

/**
 * A pass somebody is on: its name, how it stands in words (a late payment
 * first, in amber), what it covers, and — for a monthly one — the standing
 * order to set up, with Cancel my pass under it.
 */
@Composable
private fun PassCard(
    holder: PassHolder,
    plan: PassPlan?,
    title: String,
    /** Yours, or somebody's you pay for: "Cancel my pass" or "Cancel this pass". */
    own: Boolean,
    account: BankDetails?,
    clubName: String,
    busy: Boolean,
    onCancel: () -> Unit,
) {
    Card(
        Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
            val words = holder.standingWords(plan?.validUntil)
            if (holder.needsPaying) AmberNote(words) else Text(words, style = MaterialTheme.typography.bodyLarge)
            plan?.let { Body(it.coversLine()) }
            holder.nextPaymentWords()?.let { Body(it) }
            holder.standingOrder?.let { order ->
                StandingOrderCard(holder, order, account, clubName, own)
            }
            // Cancelling is for a monthly pass: the others are paid for already.
            if (holder.billing == PassBilling.Monthly && !holder.isCancelled) {
                TextButton(
                    onClick = onCancel,
                    enabled = !busy,
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier.heightIn(min = 48.dp),
                ) { Text(if (busy) t("pay.sending") else if (own) t("pa3.cancel_my_pass") else t("pa3.cancel_this_pass")) }
            }
        }
    }
}

/**
 * "Set up your standing order": exactly what the banking app asks for, one
 * row at a time with Copy — who, the amount, every month, the first payment
 * and the reference — and a way to send it to whoever does the banking.
 */
@Composable
private fun StandingOrderCard(holder: PassHolder, order: StandingOrder, account: BankDetails?, clubName: String, own: Boolean) {
    val context = LocalContext.current
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
            Text(t("pa3.so_title"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Body(t("pa3.so_body"))
            if (account != null) {
                BigCopyRow(t("pa3.so_who"), account.holderName)
                HorizontalDivider()
                BigCopyRow(t("pay.sort_code"), account.sortCode, mono = true)
                HorizontalDivider()
                BigCopyRow(t("pay.account_number"), account.accountNumber, mono = true, sensitive = true)
                HorizontalDivider()
            } else {
                Body(t("pa3.so_ask_for_details"), Modifier.padding(vertical = 8.dp))
            }
            BigCopyRow(t("pay.amount"), money(order.amountCents, holder.currency))
            HorizontalDivider()
            BigCopyRow(t("pa3.so_how_often"), t("pa3.so_every_month"))
            dayMonth(order.firstPaymentOn).takeIf { it.isNotEmpty() }?.let { first ->
                HorizontalDivider()
                BigCopyRow(t("pa3.so_first_payment"), first)
            }
            HorizontalDivider()
            BigCopyRow(t("pa2.row_reference"), order.reference, mono = true)
            OutlinedButton(
                onClick = { shareAnywhere(context, standingOrderToSend(holder, order, account, clubName)) },
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp).heightIn(min = 48.dp),
            ) {
                Icon(Icons.Filled.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                // A parent setting up a junior's is the one who pays: they send it on, if anyone.
                Text(if (own) t("pa3.so_send") else t("pa2.send_details"), modifier = Modifier.padding(start = 8.dp))
            }
        }
    }
}

/**
 * "Get Monthly nets?" — what it costs, what it covers, and that the first
 * payment is owed straight away. Somebody who pays for others is asked who
 * it is for.
 */
@Composable
private fun GetPassDialog(
    plan: PassPlan,
    people: List<Pair<String, String>>,
    onYes: (forUserId: String?) -> Unit,
    onNo: () -> Unit,
) {
    var who by remember { mutableStateOf<String?>(null) }
    val first = money(plan.chargeCents.takeIf { it > 0 } ?: plan.priceCents, plan.currency)
    AlertDialog(
        onDismissRequest = onNo,
        title = { Text(t("pa3.get_pass_title", vars = mapOf("pass" to plan.name))) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("${plan.priceWords()} · ${plan.coversLine()}", style = MaterialTheme.typography.bodyLarge)
                Text(
                    when (plan.billing) {
                        PassBilling.Monthly -> t("pa3.get_pass_monthly_body", vars = mapOf("amount" to first))
                        else -> t("pa3.get_pass_body", vars = mapOf("amount" to first))
                    },
                    style = MaterialTheme.typography.bodyMedium,
                )
                if (people.isNotEmpty()) {
                    Text(t("pa3.who_is_it_for"), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp))
                    (listOf<Pair<String?, String>>(null to t("pa3.for_me")) + people).forEach { (id, name) ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .heightIn(min = 48.dp)
                                .selectable(selected = who == id, role = Role.RadioButton) { who = id },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = who == id, onClick = null)
                            Text(name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 12.dp))
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(onClick = { onYes(who) }, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("pa3.yes_get_it")) }
        },
        dismissButton = { TextButton(onClick = onNo, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("pay.not_now")) } },
    )
}

/**
 * "Cancel Monthly nets?" Asked first, because it can't be undone here — and
 * for a monthly pass it says the other half: the standing order is in the
 * bank, and only the person can stop it.
 */
@Composable
private fun CancelPassDialog(holder: PassHolder, onYes: () -> Unit, onNo: () -> Unit) {
    AlertDialog(
        onDismissRequest = onNo,
        title = { Text(t("pa3.cancel_pass_title", vars = mapOf("pass" to holder.planName))) },
        text = {
            Text(
                if (holder.billing == PassBilling.Monthly) t("pa3.cancel_pass_monthly_body") else t("pa3.cancel_pass_body"),
                style = MaterialTheme.typography.bodyLarge,
            )
        },
        confirmButton = {
            TextButton(
                onClick = onYes,
                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(t("pa3.yes_cancel_it")) }
        },
        dismissButton = { TextButton(onClick = onNo, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("pa3.keep_it")) } },
    )
}
