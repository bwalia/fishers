package com.fishers.app.views.payments

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.clubs.money
import com.fishers.app.i18n.t
import com.fishers.app.net.PaymentsApi
import com.fishers.app.payments.Candidate
import com.fishers.app.payments.CostCheck
import com.fishers.app.payments.CostMode
import com.fishers.app.payments.EventCost
import com.fishers.app.payments.EventMoney
import com.fishers.app.payments.EventMoneyState
import com.fishers.app.payments.EventMoneyViewModel
import com.fishers.app.payments.LinkUse
import com.fishers.app.payments.Outgoing
import com.fishers.app.payments.Share
import com.fishers.app.payments.amountText
import com.fishers.app.payments.checkCost
import com.fishers.app.views.components.ButtonLabel
import com.fishers.app.views.components.ButtonRow
import com.fishers.app.views.clubs.ErrorLine
import com.fishers.app.views.clubs.Hint
import com.fishers.app.views.clubs.SectionHeading
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator

/**
 * An event's money, on its own page: the cost, "who came?", the bill and
 * everybody's share for whoever runs it, and your own share with Pay for
 * everyone else. Nothing at all when there is nothing for this person — a
 * player at an event with no cost sees no empty box.
 *
 * [inSeries] offers to change the later weeks' cost as well.
 */
@Composable
fun EventMoneySection(eventId: String, inSeries: Boolean = false) {
    val deps = LocalAppDeps.current
    val nav = LocalNavigator.current
    val model = remember(eventId) { EventMoneyViewModel(deps.service<PaymentsApi>(), eventId) }
    val state by model.state.collectAsStateWithLifecycle()
    // Each time the page shows: back from paying, the share says so.
    LaunchedEffect(eventId) { model.load(keepTicks = true) }

    val money = state.money ?: return
    if (!money.isWorthShowing) return

    var editingCost by remember { mutableStateOf(false) }
    var removingCost by remember { mutableStateOf(false) }
    var cancelling by remember { mutableStateOf(false) }
    var lettingOff by remember { mutableStateOf<Share?>(null) }
    var switchingOff by remember { mutableStateOf(false) }

    // The link's words go to WhatsApp, or the link to the clipboard, once.
    val context = LocalContext.current
    LaunchedEffect(state.outgoing) {
        when (val out = state.outgoing ?: return@LaunchedEffect) {
            is Outgoing.Share -> shareToWhatsApp(context, out.text)
            is Outgoing.Copy -> copy(context, t("pa2.pay_link"), out.url)
        }
        model.handled()
    }

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(t("pay.money"), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
            state.message?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary) }
            state.error?.let { ErrorLine(it) }

            CostPart(money, state, onEdit = { editingCost = true }, onRemove = { removingCost = true })

            money.bill?.let { BillPart(money, state, onLetOff = { lettingOff = it }) }

            // Billed, and this person runs it: share it to the group, and
            // tick off cash handed over at the ground.
            if (money.bill != null && money.canBill && !state.choosing) {
                if (state.cashOpen) {
                    WhoPaidCash(money, state, model)
                } else {
                    ShareToWhatsApp(state, model, onSwitchOff = { switchingOff = true })
                    if (state.anyoneOwes) {
                        OutlinedButton(
                            onClick = model::startCash,
                            enabled = !state.isBusy,
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                        ) {
                            Icon(Icons.Filled.Payments, contentDescription = null, modifier = Modifier.size(18.dp))
                            Text(t("pa2.who_paid_cash"), modifier = Modifier.padding(start = 8.dp))
                        }
                    }
                }
            }

            if (state.choosing) {
                WhoCame(money, state, model)
            } else if (money.canBill && money.cost != null) {
                if (money.bill == null) Hint(t("pay.after_the_session_tick"))
                ButtonRow(
                    labels = if (money.bill == null) listOf(t("pay.tick_who_came")) else listOf(t("pay.change_who_came"), t("pay.cancel_bill")),
                ) { i, m ->
                    if (i == 0) {
                        OutlinedButton(onClick = model::startChoosing, enabled = !state.isBusy, modifier = m.heightIn(min = 48.dp)) {
                            ButtonLabel(if (money.bill == null) t("pay.tick_who_came") else t("pay.change_who_came"))
                        }
                    } else {
                        TextButton(onClick = { cancelling = true }, enabled = !state.isBusy, modifier = m.heightIn(min = 48.dp)) {
                            ButtonLabel(t("pay.cancel_bill"))
                        }
                    }
                }
            }

            MySharePart(money, onPay = { nav.push(PayRoute(money.clubId)) })
        }
    }

    if (editingCost) {
        CostDialog(
            current = money.cost,
            currency = money.currency,
            inSeries = inSeries,
            onSave = { mode, cents, note, series ->
                editingCost = false
                model.saveCost(mode, cents, note, series)
            },
            onDismiss = { editingCost = false },
        )
    }
    if (removingCost) {
        AlertDialog(
            onDismissRequest = { removingCost = false },
            text = { Text(t("pay.remove_cost_confirm")) },
            confirmButton = {
                TextButton(onClick = { removingCost = false; model.removeCost() }, modifier = Modifier.heightIn(min = 48.dp)) {
                    Text(t("pay.remove_cost"))
                }
            },
            dismissButton = { TextButton(onClick = { removingCost = false }, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
        )
    }
    if (cancelling) {
        ReasonDialog(
            title = t("pay.cancel_bill"),
            explainer = t("pay.cancel_bill_explainer"),
            placeholder = t("pay.cancel_bill_example"),
            confirm = t("pay.cancel_bill"),
            destructive = true,
            onConfirm = { cancelling = false; model.cancelBill(it) },
            onDismiss = { cancelling = false },
        )
    }
    if (switchingOff) {
        AlertDialog(
            onDismissRequest = { switchingOff = false },
            title = { Text(t("pa2.switch_link_off_title")) },
            text = { Text(t("pa2.switch_link_off_body")) },
            confirmButton = {
                TextButton(
                    onClick = { switchingOff = false; model.switchLinkOff() },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier.heightIn(min = 48.dp),
                ) { Text(t("pa2.switch_link_off")) }
            },
            dismissButton = {
                TextButton(onClick = { switchingOff = false }, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) }
            },
        )
    }
    lettingOff?.let { share ->
        ReasonDialog(
            title = t("pay.let_off_name", vars = mapOf("name" to share.name)),
            explainer = t("pay.let_off_explainer", vars = mapOf("amount" to money(share.amountCents, share.currency))),
            placeholder = t("pay.let_off_example"),
            confirm = t("pay.let_off"),
            onConfirm = { lettingOff = null; model.letOff(share, it) },
            onDismiss = { lettingOff = null },
        )
    }
}

/** What it costs. Changeable by whoever runs it until it is billed; after that, re-split instead. */
@Composable
private fun CostPart(money: EventMoney, state: EventMoneyState, onEdit: () -> Unit, onRemove: () -> Unit) {
    val cost = money.cost
    if (cost != null) {
        Text(cost.summary, style = MaterialTheme.typography.bodyLarge)
        cost.note?.let { Hint(it) }
    }
    if (!money.canBill || money.bill != null) return
    if (cost == null) Hint(t("pay.no_cost_yet"))
    else if (!money.hasPayoutAccount) Hint(t("pay.no_bank_details_yet"))
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TextButton(onClick = onEdit, enabled = !state.isBusy, modifier = Modifier.heightIn(min = 48.dp)) {
            Text(if (cost == null) t("pay.add_a_cost") else t("pay.change_the_cost"))
        }
        if (cost != null) {
            TextButton(onClick = onRemove, enabled = !state.isBusy, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(t("pay.remove_cost"))
            }
        }
    }
}

/** Collected, waiting and owed, then everybody's share for those who run it. */
@Composable
private fun BillPart(money: EventMoney, state: EventMoneyState, onLetOff: (Share) -> Unit) {
    val bill = money.bill ?: return
    val c = bill.currency
    if (money.canBill || money.canManageMoney) {
        Text(
            t("pay.collected_of_total", vars = mapOf("collected" to money(bill.paidCents, c), "total" to money(bill.totalCents, c))),
            style = MaterialTheme.typography.titleSmall,
        )
        AmountLine(t("pay.waiting_to_check"), money(bill.waitingCents, c))
        AmountLine(t("pay.still_owed"), money(bill.owedCents, c))
        if (bill.surplusCents > 0) Hint(t("pay.surplus_note", vars = mapOf("amount" to money(bill.surplusCents, c))))
        if (money.shares.isNotEmpty()) {
            SectionHeading(t("pay.shares"))
            money.shares.forEachIndexed { i, share ->
                if (i > 0) HorizontalDivider()
                Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(share.name, style = MaterialTheme.typography.bodyLarge)
                        share.reason?.let { Hint(it) }
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(money(share.amountCents, share.currency), style = MaterialTheme.typography.bodyMedium)
                        StateLabel(share.state)
                    }
                    if (money.canManageMoney && share.canLetOff) {
                        TextButton(onClick = { onLetOff(share) }, enabled = !state.isBusy, modifier = Modifier.heightIn(min = 48.dp)) {
                            Text(t("pay.let_off"))
                        }
                    }
                }
            }
        }
    } else if (bill.note != null) {
        Hint(bill.note)
    }
}

/**
 * Share the bill to the club's WhatsApp group, remind whoever hasn't paid,
 * or copy the link. The words are the server's. Switching the link off is
 * tucked behind ⋮, with a question first.
 */
@Composable
private fun ShareToWhatsApp(state: EventMoneyState, model: EventMoneyViewModel, onSwitchOff: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    HorizontalDivider()
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            t("pa2.share_to_whatsapp"),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.weight(1f).semantics { heading() },
        )
        Box {
            IconButton(onClick = { menu = true }, enabled = !state.isBusy) {
                Icon(Icons.Filled.MoreVert, contentDescription = t("pa2.link_more"))
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(
                    text = { Text(t("pa2.switch_link_off")) },
                    leadingIcon = { Icon(Icons.Filled.LinkOff, contentDescription = null) },
                    onClick = { menu = false; onSwitchOff() },
                    modifier = Modifier.heightIn(min = 48.dp),
                )
            }
        }
    }
    Body(t("pa2.share_hint"))
    Button(
        onClick = { model.share(LinkUse.Bill) },
        enabled = !state.isBusy,
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
    ) {
        Icon(Icons.Filled.Share, contentDescription = null, modifier = Modifier.size(18.dp))
        Text(if (state.isBusy) t("pa2.getting_link") else t("pa2.share_the_bill"), modifier = Modifier.padding(start = 8.dp))
    }
    if (state.anyoneOwes) {
        OutlinedButton(
            onClick = { model.share(LinkUse.Reminder) },
            enabled = !state.isBusy,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
        ) { Text(t("pa2.remind_who_hasnt_paid")) }
    }
    TextButton(onClick = { model.share(LinkUse.CopyLink) }, enabled = !state.isBusy, modifier = Modifier.heightIn(min = 48.dp)) {
        Icon(Icons.Filled.Link, contentDescription = null, modifier = Modifier.size(18.dp))
        Text(t("pa2.copy_link"), modifier = Modifier.padding(start = 8.dp))
    }
}

/**
 * Cash at the ground: tick who handed some over, then save. Only those who
 * still owe are listed; each is recorded for what they still owe.
 */
@Composable
private fun WhoPaidCash(money: EventMoney, state: EventMoneyState, model: EventMoneyViewModel) {
    HorizontalDivider()
    SectionHeading(t("pa2.who_paid_cash"))
    Body(if (money.canManageMoney) t("pa2.who_paid_cash_hint") else t("pa2.who_paid_cash_hint_captain"))
    state.cashCandidates.forEach { share ->
        val ticked = share.id in state.cashTicked
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .toggleable(value = ticked, role = Role.Checkbox, onValueChange = { model.toggleCash(share.id) }),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Checkbox(checked = ticked, onCheckedChange = null)
            Text(share.name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 12.dp).weight(1f))
            Text(money(share.leftCents, share.currency), style = MaterialTheme.typography.bodyLarge)
        }
    }
    val n = state.cashTicked.size
    val save = if (n == 0) t("lc.save") else t("pa2.save_cash", count = n, vars = mapOf("n" to n))
    ButtonRow(labels = listOf(save, t("pay.not_now"))) { i, m ->
        if (i == 0) {
            Button(onClick = model::saveCash, enabled = n > 0 && !state.isBusy, modifier = m.heightIn(min = 48.dp)) {
                ButtonLabel(if (state.isBusy) t("pay.sending") else save)
            }
        } else {
            TextButton(onClick = model::stopCash, enabled = !state.isBusy, modifier = m.heightIn(min = 48.dp)) {
                ButtonLabel(t("pay.not_now"))
            }
        }
    }
}

/** Your own share, and the way to pay it. */
@Composable
private fun MySharePart(money: EventMoney, onPay: () -> Unit) {
    val mine = money.myShare ?: return
    HorizontalDivider()
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(t("pay.your_share"), style = MaterialTheme.typography.labelLarge)
            Text(money(mine.amountCents, mine.currency), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        }
        StateLabel(mine.state)
    }
    if (mine.leftCents > 0) {
        Button(onClick = onPay, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text(t("pay.pay")) }
    }
}

/**
 * Who came: everybody asked, ticked as the server suggests, then anybody else
 * in the club (a member who joined after it was scheduled can still have
 * come), then guests by name. The total underneath is the server's.
 */
@Composable
private fun WhoCame(money: EventMoney, state: EventMoneyState, model: EventMoneyViewModel) {
    HorizontalDivider()
    SectionHeading(t("pay.who_came"))
    val (asked, others) = money.candidates.partition { it.wasAsked }
    asked.forEach { CandidateRow(it, ticked = it.userId in state.ticked, onToggle = { model.toggle(it.userId) }) }
    if (others.isNotEmpty()) {
        Text(t("pay.others_in_the_club"), style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 8.dp))
        others.forEach { CandidateRow(it, ticked = it.userId in state.ticked, onToggle = { model.toggle(it.userId) }) }
    }

    Text(t("pay.guests"), style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 8.dp))
    state.guests.forEach { guest ->
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(guest, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            IconButton(onClick = { model.removeGuest(guest) }) {
                Icon(Icons.Filled.Close, contentDescription = t("pay.remove_guest", vars = mapOf("name" to guest)))
            }
        }
    }
    GuestField(onAdd = model::addGuest)

    // ---- what it comes to ----
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (state.isPreviewing) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
        val preview = state.preview
        when {
            preview != null -> Text(preview.summary, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
            state.previewProblem != null -> Hint(state.previewProblem)
        }
    }
    state.preview?.takeIf { it.surplusCents > 0 }?.let {
        Hint(t("pay.surplus_note", vars = mapOf("amount" to money(it.surplusCents, it.currency))))
    }

    val send = if (money.bill == null) t("pay.send_the_bill") else t("pay.resplit_the_bill")
    ButtonRow(labels = listOf(send, t("pay.not_now"))) { i, m ->
        if (i == 0) {
            Button(onClick = model::send, enabled = state.canSend && state.preview != null, modifier = m.heightIn(min = 48.dp)) {
                ButtonLabel(if (state.isBusy) t("pay.sending") else send)
            }
        } else {
            TextButton(onClick = model::stopChoosing, enabled = !state.isBusy, modifier = m.heightIn(min = 48.dp)) {
                ButtonLabel(t("pay.not_now"))
            }
        }
    }
    if (money.bill == null) Hint(t("pay.send_explainer"))
}

@Composable
private fun CandidateRow(candidate: Candidate, ticked: Boolean, onToggle: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .toggleable(value = ticked, role = Role.Checkbox, onValueChange = { onToggle() }),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(checked = ticked, onCheckedChange = null)
        Text(candidate.name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 12.dp).weight(1f))
        rsvpWord(candidate.rsvp)?.let { Hint(it) }
    }
}

/** What they said beforehand, beside the tick: a hint, not a rule. Unknown answers say nothing. */
private fun rsvpWord(rsvp: String): String? = when (rsvp) {
    "going" -> t("pay.said_going")
    "maybe" -> t("pay.said_maybe")
    "not_going" -> t("pay.said_not_going")
    else -> null
}

@Composable
private fun GuestField(onAdd: (String) -> Unit) {
    var name by rememberSaveable { mutableStateOf("") }
    val add = {
        if (name.isNotBlank()) {
            onAdd(name)
            name = ""
        }
    }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value = name,
            onValueChange = { if (it.length <= 60) name = it },
            label = { Text(t("pay.add_a_guest")) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { add() }),
            modifier = Modifier.weight(1f),
        )
        TextButton(onClick = add, enabled = name.isNotBlank(), modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.add")) }
    }
}

/**
 * Set or change what it costs: a total split between whoever comes, or the
 * same from each. Above £100 a head it asks once more — a slipped zero is easy
 * to type and hard to explain to eleven people.
 */
@Composable
internal fun CostDialog(
    current: EventCost?,
    currency: String?,
    inSeries: Boolean,
    onSave: (CostMode, Long, String?, Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    var mode by rememberSaveable { mutableStateOf(current?.mode ?: CostMode.SplitTotal) }
    var amount by rememberSaveable { mutableStateOf(current?.let { amountText(it.amountCents) } ?: "") }
    var note by rememberSaveable { mutableStateOf(current?.note ?: "") }
    var series by rememberSaveable { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    var confirming by remember { mutableStateOf<Long?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (current == null) t("pay.add_a_cost") else t("pay.change_the_cost")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CostModeChoice(mode, onMode = { mode = it; problem = null })
                AmountField(
                    value = amount,
                    onValue = { amount = it; problem = null },
                    label = if (mode == CostMode.SplitTotal) t("pay.total_cost") else t("pay.each_pays"),
                    currency = currency,
                    error = problem,
                )
                OutlinedTextField(
                    value = note,
                    onValueChange = { if (it.length <= 200) note = it },
                    label = { Text(t("pay.cost_note")) },
                    placeholder = { Text(t("pay.cost_note_example")) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                if (inSeries) {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .toggleable(value = series, role = Role.Switch, onValueChange = { series = it }),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(t("pay.apply_to_later_weeks"), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                        Switch(checked = series, onCheckedChange = null)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    when (val check = checkCost(mode, amount)) {
                        is CostCheck.Ok -> onSave(mode, check.cents, note, series)
                        is CostCheck.Confirm -> confirming = check.cents
                        is CostCheck.Invalid -> problem = check.message
                    }
                },
                enabled = amount.isNotBlank(),
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(t("lc.save")) }
        },
        dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
    )

    confirming?.let { cents ->
        BigAmountDialog(
            amount = money(cents, currency),
            onYes = { confirming = null; onSave(mode, cents, note, series) },
            onNo = { confirming = null },
        )
    }
}

/** "Split a total" or "Same for everyone", as two radio rows a thumb can hit. */
@Composable
internal fun CostModeChoice(mode: CostMode?, onMode: (CostMode) -> Unit, offerNone: Boolean = false, onNone: () -> Unit = {}) {
    Column {
        if (offerNone) {
            ChoiceRow(t("pay.no_cost"), selected = mode == null, onClick = onNone)
        }
        CostMode.entries.forEach { option ->
            ChoiceRow(option.label, selected = mode == option, onClick = { onMode(option) })
        }
    }
}

@Composable
private fun ChoiceRow(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = null)
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 12.dp))
    }
}

/** "£150.00 each — is that right?" */
@Composable
internal fun BigAmountDialog(amount: String, onYes: () -> Unit, onNo: () -> Unit) {
    AlertDialog(
        onDismissRequest = onNo,
        title = { Text(t("pay.big_amount_title", vars = mapOf("amount" to amount))) },
        text = { Text(t("pay.big_amount_body")) },
        confirmButton = { TextButton(onClick = onYes, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("pay.yes_thats_right")) } },
        dismissButton = { TextButton(onClick = onNo, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("pay.let_me_change_it")) } },
    )
}
