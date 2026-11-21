package com.fishers.app.views.payments

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.clubs.money
import com.fishers.app.i18n.t
import com.fishers.app.net.PaymentsApi
import com.fishers.app.payments.BankForm
import com.fishers.app.payments.BillSummary
import com.fishers.app.payments.ClubMoneyState
import com.fishers.app.payments.ClubMoneyViewModel
import com.fishers.app.payments.MemberBalance
import com.fishers.app.payments.MoneySettings
import com.fishers.app.payments.Payment
import com.fishers.app.payments.PaymentMethod
import com.fishers.app.payments.PayoutAccount
import com.fishers.app.payments.PayoutAccounts
import com.fishers.app.payments.amountText
import com.fishers.app.payments.dayAndTime
import com.fishers.app.payments.parseAmount
import com.fishers.app.payments.shortDay
import com.fishers.app.views.clubs.ClubScreen
import com.fishers.app.views.clubs.ErrorLine
import com.fishers.app.views.clubs.Hint
import com.fishers.app.views.clubs.SectionHeading
import com.fishers.app.views.components.ButtonLabel
import com.fishers.app.views.components.ButtonRow
import com.fishers.app.views.fixtures.FixtureRoute
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator

/** The treasurer's page on its own, as a notification opens it. */
@Composable
internal fun ClubPaymentsPage(clubId: String, name: String, payIfNotAdmin: Boolean) {
    val deps = LocalAppDeps.current
    val nav = LocalNavigator.current
    val model = remember(clubId) { ClubMoneyViewModel(deps.service<PaymentsApi>(), clubId) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(clubId) { model.load() }
    // Not a money admin: the notification was about their own money.
    LaunchedEffect(state.notAllowed) {
        if (payIfNotAdmin && state.notAllowed != null) nav.replace(PayRoute(clubId, name))
    }
    ClubScreen(title = if (name.isBlank()) t("pay.payments") else t("pay.payments_for", vars = mapOf("club" to name))) {
        ClubPaymentsContent(state, model)
    }
}

/**
 * Club → Manage → Payments, for the owner, secretaries and treasurers: the
 * bank details, the payments to check, who owes what, recent bills and the
 * settings. Also the whole of [ClubPaymentsPage].
 */
@Composable
fun ClubPaymentsContent(state: ClubMoneyState, model: ClubMoneyViewModel) {
    val nav = LocalNavigator.current
    val overview = state.overview
    if (overview == null) {
        Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
            when {
                state.isLoading -> CircularProgressIndicator()
                state.notAllowed != null -> Hint(state.notAllowed)
                else -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    ErrorLine(state.loadError ?: t("rest.something_went_wrong_plain"))
                    TextButton(onClick = model::load, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("rest.try_again")) }
                }
            }
        }
        return
    }

    var rejecting by remember { mutableStateOf<Payment?>(null) }
    var recording by remember { mutableStateOf<MemberBalance?>(null) }
    var refunding by remember { mutableStateOf<MemberBalance?>(null) }
    var freezing by remember { mutableStateOf<PayoutAccount?>(null) }
    var removing by remember { mutableStateOf<PayoutAccount?>(null) }
    val currency = overview.currency

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        state.message?.let { item { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary) } }
        state.error?.let { item { ErrorLine(it) } }

        item {
            BankDetailsCard(
                accounts = overview.account,
                busy = state.isBusy,
                onAdd = model::openForm,
                onFreeze = { freezing = it },
                onUnfreeze = model::unfreeze,
                onRemove = { removing = it },
            )
        }

        // ---- payments to check ----
        item {
            SectionHeading(
                if (overview.toCheck.isEmpty()) t("pay.payments_to_check")
                else t("pay.payments_to_check_n", vars = mapOf("n" to overview.toCheck.size)),
            )
        }
        if (overview.toCheck.isEmpty()) {
            item { Hint(t("pay.nothing_to_check")) }
        } else {
            item { Hint(t("pay.check_your_bank")) }
            items(overview.toCheck, key = { "check-${it.id}" }) { payment ->
                ToCheckRow(
                    payment = payment,
                    busy = payment.id in state.deciding,
                    onReceived = { model.confirm(payment) },
                    onNotReceived = { rejecting = payment },
                )
            }
        }

        // ---- who owes what ----
        item { SectionHeading(t("pay.who_owes_what")) }
        item {
            AmountLine(t("pay.still_owed"), money(overview.totals.owedCents, currency), strong = true)
            if (overview.totals.waitingCents > 0) AmountLine(t("pay.waiting_to_check"), money(overview.totals.waitingCents, currency))
            if (overview.totals.creditCents > 0) AmountLine(t("pay.credit_held"), money(overview.totals.creditCents, currency))
        }
        if (overview.members.isEmpty()) {
            item { Hint(t("pay.nobody_owes")) }
        } else {
            items(overview.members, key = { "owes-${it.key}" }) { member ->
                BalanceRow(
                    member = member,
                    currency = currency,
                    busy = state.isBusy,
                    onRecord = { recording = member },
                    onRefund = { refunding = member },
                )
            }
        }

        // ---- recent bills ----
        if (overview.bills.isNotEmpty()) {
            item { SectionHeading(t("pay.recent_bills")) }
            items(overview.bills, key = { "bill-${it.billId}" }) { bill ->
                BillRow(bill, onOpen = { nav.push(FixtureRoute(bill.eventId)) })
            }
        }

        // ---- settings ----
        item { SettingsPart(overview.settings, onChange = model::changeSettings) }
    }

    state.form?.let { form ->
        BankDetailsDialog(
            form = form,
            changing = overview.account.current != null,
            onSave = model::saveBankDetails,
            onDismiss = model::closeForm,
        )
    }
    rejecting?.let { payment ->
        ReasonDialog(
            title = t("pay.not_received_title", vars = mapOf("name" to payment.name, "amount" to money(payment.amountCents, payment.currency))),
            explainer = t("pay.not_received_explainer"),
            placeholder = t("pay.not_received_example"),
            confirm = t("pay.not_received"),
            destructive = true,
            onConfirm = { rejecting = null; model.reject(payment, it) },
            onDismiss = { rejecting = null },
        )
    }
    recording?.let { member ->
        RecordDialog(
            member = member,
            currency = currency,
            refund = false,
            onSave = { cents, method, note -> recording = null; model.record(member, cents, method, note) },
            onDismiss = { recording = null },
        )
    }
    refunding?.let { member ->
        RecordDialog(
            member = member,
            currency = currency,
            refund = true,
            onSave = { cents, _, note -> refunding = null; model.refund(member, cents, note) },
            onDismiss = { refunding = null },
        )
    }
    freezing?.let { account ->
        ReasonDialog(
            title = t("pay.freeze_title"),
            explainer = t("pay.freeze_explainer"),
            confirm = t("pay.freeze"),
            required = false,
            destructive = true,
            onConfirm = { freezing = null; model.freeze(account, it) },
            onDismiss = { freezing = null },
        )
    }
    removing?.let { account ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text(if (account.stateName == "pending") t("pay.cancel_change_title") else t("pay.remove_details_title")) },
            text = { Text(if (account.stateName == "pending") t("pay.cancel_change_body") else t("pay.remove_details_body")) },
            confirmButton = {
                TextButton(
                    onClick = { removing = null; model.retire(account) },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier.heightIn(min = 48.dp),
                ) { Text(if (account.stateName == "pending") t("pay.cancel_change") else t("pay.remove")) }
            },
            dismissButton = { TextButton(onClick = { removing = null }, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
        )
    }
}

// ---- bank details ----

/**
 * What players are shown, a change waiting to go live, and details somebody
 * froze. Never the whole number: the last four are enough to recognise it.
 */
@Composable
private fun BankDetailsCard(
    accounts: PayoutAccounts,
    busy: Boolean,
    onAdd: () -> Unit,
    onFreeze: (PayoutAccount) -> Unit,
    onUnfreeze: (PayoutAccount) -> Unit,
    onRemove: (PayoutAccount) -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(t("pay.bank_details"), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
            val current = accounts.current
            if (current == null && accounts.pending == null && accounts.frozen == null) {
                Hint(t("pay.no_details_yet_admin"))
            }
            current?.let { account ->
                AccountLines(account)
                if (!account.readable) StopNote(t("pay.details_unreadable_admin"))
                accounts.changedAt?.let { Hint(t("pay.changed_on", vars = mapOf("date" to shortDay(it)))) }
                if (accounts.canManage) {
                    AccountButtons(
                        first = t("pay.freeze") to { onFreeze(account) },
                        second = t("pay.remove") to { onRemove(account) },
                        busy = busy,
                    )
                }
            }
            accounts.pending?.let { account ->
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
                AmberNote(t("pay.change_goes_live", vars = mapOf("when" to dayAndTime(account.liveFrom))))
                AccountLines(account)
                if (accounts.canManage) {
                    AccountButtons(
                        first = t("pay.freeze") to { onFreeze(account) },
                        second = t("pay.cancel_change") to { onRemove(account) },
                        busy = busy,
                    )
                }
            }
            accounts.frozen?.let { account ->
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
                StopNote(
                    account.freezeReason?.let { t("pay.frozen_because", vars = mapOf("reason" to it)) } ?: t("pay.frozen_no_reason"),
                )
                AccountLines(account)
                // Only the owner can let frozen details go live again, or take them away.
                if (accounts.isOwner) {
                    AccountButtons(
                        first = t("pay.unfreeze") to { onUnfreeze(account) },
                        second = t("pay.remove") to { onRemove(account) },
                        busy = busy,
                    )
                } else {
                    Hint(t("pay.only_owner_unfreezes"))
                }
            }
            if (accounts.canManage) {
                Button(onClick = onAdd, enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    Text(if (current == null && accounts.pending == null) t("pay.add_bank_details") else t("pay.change_bank_details"))
                }
            }
        }
    }
}

@Composable
private fun AccountLines(account: PayoutAccount) {
    Text(account.holderName, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
    Text(
        listOfNotNull(account.sortCode, "••••${account.last4}").joinToString("  "),
        style = MaterialTheme.typography.bodyMedium,
    )
    Hint(
        listOfNotNull(
            account.label.takeIf { it.isNotBlank() },
            t("pay.personal_account").takeIf { account.isPersonal },
            account.createdByName?.let { t("pay.added_by", vars = mapOf("name" to it)) },
        ).joinToString(" · "),
    )
}

@Composable
private fun AccountButtons(first: Pair<String, () -> Unit>, second: Pair<String, () -> Unit>, busy: Boolean) {
    ButtonRow(labels = listOf(first.first, second.first)) { i, m ->
        val (label, action) = if (i == 0) first else second
        OutlinedButton(onClick = action, enabled = !busy, modifier = m.heightIn(min = 48.dp)) { ButtonLabel(label) }
    }
}

/**
 * Add or change the details. The name must be the account's own, because
 * players' banks check it; the number is typed twice because nothing else
 * catches a slipped digit yet; and the password, because a borrowed phone
 * must not be enough to send the club's money somewhere else.
 *
 * The number and the password are held with `remember`, not `rememberSaveable`:
 * saved state can be written to disk, and these must never be.
 */
@Composable
private fun BankDetailsDialog(
    form: BankForm,
    changing: Boolean,
    onSave: (holder: String, sortCode: String, number: String, again: String, personal: Boolean, password: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var holder by rememberSaveable { mutableStateOf("") }
    var sortCode by rememberSaveable { mutableStateOf("") }
    var number by remember { mutableStateOf("") }
    var again by remember { mutableStateOf("") }
    var personal by rememberSaveable { mutableStateOf(false) }
    var password by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = { if (!form.isSaving) onDismiss() },
        title = { Text(if (changing) t("pay.change_bank_details") else t("pay.add_bank_details")) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = holder,
                    onValueChange = { if (it.length <= 70) holder = it },
                    label = { Text(t("pay.account_name")) },
                    supportingText = { Text(t("pay.holder_name_hint")) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, autoCorrectEnabled = false),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = sortCode,
                    onValueChange = { typed -> sortCode = typed.filter { it.isDigit() || it == '-' || it == ' ' }.take(8) },
                    label = { Text(t("pay.sort_code")) },
                    placeholder = { Text("12-34-56") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = number,
                    onValueChange = { typed -> number = typed.filter { it.isDigit() || it == ' ' }.take(10) },
                    label = { Text(t("pay.account_number")) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, autoCorrectEnabled = false),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = again,
                    onValueChange = { typed -> again = typed.filter { it.isDigit() || it == ' ' }.take(10) },
                    label = { Text(t("pay.account_number_again")) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, autoCorrectEnabled = false),
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .toggleable(value = personal, role = Role.Checkbox, onValueChange = { personal = it }),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Checkbox(checked = personal, onCheckedChange = null)
                    Column(Modifier.padding(start = 12.dp)) {
                        Text(t("pay.this_is_personal"), style = MaterialTheme.typography.bodyLarge)
                        Hint(t("pay.personal_hint"))
                    }
                }
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text(t("pay.your_password")) },
                    supportingText = {
                        Text(if (form.needsPassword) t("pay.password_needed") else t("pay.password_hint"))
                    },
                    isError = form.needsPassword && password.isEmpty(),
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
                    modifier = Modifier.fillMaxWidth(),
                )
                if (changing) Hint(t("pay.change_waits_24_hours"))
                form.error?.let { ErrorLine(it) }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(holder, sortCode, number, again, personal, password) },
                enabled = !form.isSaving,
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(if (form.isSaving) t("la.saving") else t("lc.save")) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !form.isSaving, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) }
        },
    )
}

// ---- payments to check ----

@Composable
private fun ToCheckRow(payment: Payment, busy: Boolean, onReceived: () -> Unit, onNotReceived: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(payment.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
            Text(money(payment.amountCents, payment.currency), style = MaterialTheme.typography.titleMedium)
        }
        Hint(
            listOfNotNull(
                payment.method.label.takeIf { it.isNotEmpty() },
                payment.reference,
                shortDay(payment.createdAt).takeIf { it.isNotEmpty() },
            ).joinToString(" · "),
        )
        payment.note?.let { Hint(it) }
        ButtonRow(labels = listOf(t("pay.received"), t("pay.not_received"))) { i, m ->
            if (i == 0) {
                Button(onClick = onReceived, enabled = !busy, modifier = m.heightIn(min = 48.dp)) { ButtonLabel(t("pay.received")) }
            } else {
                OutlinedButton(onClick = onNotReceived, enabled = !busy, modifier = m.heightIn(min = 48.dp)) {
                    ButtonLabel(t("pay.not_received"))
                }
            }
        }
    }
    HorizontalDivider()
}

// ---- who owes what ----

@Composable
private fun BalanceRow(member: MemberBalance, currency: String, busy: Boolean, onRecord: () -> Unit, onRefund: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(member.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                if (member.userId == null) Hint(t("pay.guest"))
            }
            if (member.owedCents > 0) {
                Text(money(member.owedCents, currency), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.error)
            }
        }
        if (member.waitingCents > 0) {
            Text(
                t("pay.amount_waiting_short", vars = mapOf("amount" to money(member.waitingCents, currency))),
                style = MaterialTheme.typography.bodySmall,
                color = AMBER,
            )
        }
        if (member.creditCents > 0) Hint(t("pay.amount_credit", vars = mapOf("amount" to money(member.creditCents, currency))))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(onClick = onRecord, enabled = !busy, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("pay.record_cash")) }
            if (member.creditCents > 0) {
                TextButton(onClick = onRefund, enabled = !busy, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("pay.refund")) }
            }
        }
    }
    HorizontalDivider()
}

/**
 * Record money that came without a claim, or hand back credit. Prefilled with
 * what they owe (or hold), since that is what it nearly always is.
 */
@Composable
private fun RecordDialog(
    member: MemberBalance,
    currency: String,
    refund: Boolean,
    onSave: (Long, PaymentMethod, String?) -> Unit,
    onDismiss: () -> Unit,
) {
    val start = if (refund) member.creditCents else member.owedCents
    var amount by rememberSaveable { mutableStateOf(if (start > 0) amountText(start) else "") }
    var method by rememberSaveable { mutableStateOf(PaymentMethod.Cash) }
    var note by rememberSaveable { mutableStateOf("") }
    var problem by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                if (refund) t("pay.refund_name", vars = mapOf("name" to member.name))
                else t("pay.record_for_name", vars = mapOf("name" to member.name)),
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (refund) {
                    Hint(t("pay.refund_explainer", vars = mapOf("amount" to money(member.creditCents, currency))))
                }
                AmountField(value = amount, onValue = { amount = it; problem = null }, label = t("pay.amount"), currency = currency, error = problem)
                if (!refund) {
                    listOf(PaymentMethod.Cash, PaymentMethod.Transfer).forEach { option ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .heightIn(min = 48.dp)
                                .selectable(selected = method == option, role = Role.RadioButton) { method = option },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = method == option, onClick = null)
                            Text(option.label, modifier = Modifier.padding(start = 12.dp))
                        }
                    }
                }
                OutlinedTextField(
                    value = note,
                    onValueChange = { if (it.length <= 200) note = it },
                    label = { Text(t("pay.note_optional")) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val cents = parseAmount(amount)
                    when {
                        cents == null -> problem = t("pay.amount_not_valid")
                        refund && cents > member.creditCents -> problem = t("pay.refund_at_most", vars = mapOf("amount" to money(member.creditCents, currency)))
                        else -> onSave(cents, method, note)
                    }
                },
                enabled = amount.isNotBlank(),
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(if (refund) t("pay.refund") else t("pay.record")) }
        },
        dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
    )
}

// ---- bills ----

@Composable
private fun BillRow(bill: BillSummary, onOpen: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(role = Role.Button, onClick = onOpen)
            .padding(vertical = 8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(bill.title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
            Text(money(bill.totalCents, bill.currency), style = MaterialTheme.typography.bodyMedium)
        }
        Hint(
            listOfNotNull(
                shortDay(bill.eventStartAt).takeIf { it.isNotEmpty() },
                t("pay.collected_of_total", vars = mapOf("collected" to money(bill.paidCents, bill.currency), "total" to money(bill.totalCents, bill.currency))),
                t("pay.n_unpaid", vars = mapOf("n" to bill.unpaid)).takeIf { bill.unpaid > 0 },
                t("pay.n_to_check", vars = mapOf("n" to bill.waiting)).takeIf { bill.waiting > 0 },
            ).joinToString(" · "),
        )
    }
    HorizontalDivider()
}

// ---- settings ----

/** The hours a bill may wait for "who came?" before it goes from the "going" list. */
private val AUTO_BILL_HOURS = listOf(6, 12, 24, 48, 72)

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SettingsPart(settings: MoneySettings, onChange: ((MoneySettings) -> MoneySettings) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        SectionHeading(t("pay.settings"))
        SwitchRow(t("pay.auto_send"), t("pay.auto_send_hint"), settings.autoBill) { on -> onChange { it.copy(autoBill = on) } }
        if (settings.autoBill) {
            Text(t("pay.auto_send_after"), style = MaterialTheme.typography.bodyMedium)
            // Chips wrap; each is its own size, never stretched across the row.
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                (AUTO_BILL_HOURS + settings.autoBillAfterHours).distinct().sorted().forEach { hours ->
                    FilterChip(
                        selected = hours == settings.autoBillAfterHours,
                        onClick = { onChange { it.copy(autoBillAfterHours = hours) } },
                        label = { Text(t("pay.n_hours", count = hours, vars = mapOf("n" to hours))) },
                        modifier = Modifier.heightIn(min = 48.dp),
                    )
                }
            }
        }
        SwitchRow(t("pay.round_up"), t("pay.round_up_hint"), settings.roundSharesUp) { on -> onChange { it.copy(roundSharesUp = on) } }
    }
}

@Composable
private fun SwitchRow(label: String, hint: String, on: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .toggleable(value = on, role = Role.Switch, onValueChange = onChange),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            Hint(hint)
        }
        Switch(checked = on, onCheckedChange = null)
    }
}
