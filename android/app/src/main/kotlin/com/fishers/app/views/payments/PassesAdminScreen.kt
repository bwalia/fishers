package com.fishers.app.views.payments

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
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
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.i18n.t
import com.fishers.app.net.PaymentsApi
import com.fishers.app.payments.PassBilling
import com.fishers.app.payments.PassDraft
import com.fishers.app.payments.PassHolder
import com.fishers.app.payments.PassLength
import com.fishers.app.payments.PassPlan
import com.fishers.app.payments.PassStanding
import com.fishers.app.payments.PassTemplate
import com.fishers.app.payments.PassesAdminState
import com.fishers.app.payments.PassesAdminViewModel
import com.fishers.app.payments.SessionKind
import com.fishers.app.payments.amountText
import com.fishers.app.payments.dayMonth
import com.fishers.app.payments.preview
import com.fishers.app.views.clubs.ClubScreen
import com.fishers.app.views.clubs.ErrorLine
import com.fishers.app.views.clubs.SectionHeading
import com.fishers.app.views.components.ButtonLabel
import com.fishers.app.views.components.ButtonRow
import com.fishers.app.views.nav.LocalAppDeps
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Payments → Passes, for money admins: make one from a template, then each
 * pass opens to who is on it and how they stand. The new-pass form and an
 * opened pass sit in place of the list; Back returns to it.
 */
@Composable
internal fun PassesAdminPage(clubId: String, currency: String) {
    val deps = LocalAppDeps.current
    val model = remember(clubId) { PassesAdminViewModel(deps.service<PaymentsApi>(), clubId) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(clubId) { model.load() }

    val draft = state.draft
    val open = state.open
    BackHandler(enabled = draft != null || open != null) { if (draft != null) model.closeDraft() else model.closeOpen() }

    ClubScreen(
        title = when {
            draft != null -> t("pa3.new_pass")
            open != null -> open.name
            else -> t("pa3.passes")
        },
    ) {
        when {
            state.plans.isEmpty() && state.isLoading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            state.plans.isEmpty() && state.loadError != null -> Column(Modifier.padding(24.dp)) {
                ErrorLine(state.loadError ?: "")
                TextButton(onClick = model::load, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("rest.try_again")) }
            }
            draft != null -> PassForm(draft, state, currency, model)
            open != null -> OnePass(open, state, model)
            else -> PassList(state, currency, model)
        }
    }
}

@Composable
private fun Said(state: PassesAdminState) {
    state.message?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary) }
    state.error?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.error) }
}

// ---- the list, and the templates ----

@Composable
private fun PassList(state: PassesAdminState, currency: String, model: PassesAdminViewModel) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Said(state)
        if (state.offered.isNotEmpty()) {
            SectionHeading(t("pa3.club_passes"))
            state.offered.forEach { plan -> PlanRow(plan, onOpen = { model.open(plan.id) }) }
        }

        SectionHeading(t("pa3.make_a_pass"))
        Body(t("pa3.make_a_pass_hint"))
        val today = remember { LocalDate.now() }
        PassTemplate.entries.forEach { template ->
            val preview = template.draft(today, state.priceTypes).preview(currency)
            Card(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 64.dp)
                    .clickable(role = Role.Button, enabled = !state.isBusy) { model.startFrom(template) },
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(template.title, style = MaterialTheme.typography.titleMedium)
                    Body("${preview.priceWords()} · ${preview.coversLine()}")
                }
            }
        }

        if (state.stopped.isNotEmpty()) {
            SectionHeading(t("pa3.no_longer_offered"))
            state.stopped.forEach { plan -> PlanRow(plan, onOpen = { model.open(plan.id) }) }
        }
    }
}

/** "Monthly nets · £20.00 a month · 4 people on it · 1 payment late". */
@Composable
private fun PlanRow(plan: PassPlan, onOpen: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(role = Role.Button, onClick = onOpen)
            .padding(vertical = 8.dp),
    ) {
        Text(plan.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
        Body(
            listOf(
                plan.priceWords(),
                t("pa3.people_on_it", count = plan.holders, vars = mapOf("n" to plan.holders)),
                if (plan.openToJoin) t("pa3.players_can_get_it") else t("pa3.you_add_people"),
            ).joinToString(" · "),
        )
    }
    HorizontalDivider()
}

// ---- a new pass ----

/**
 * The form a template fills in: name, price and how it's paid, what it
 * covers, how long, and who can have it. "What players will see" under it is
 * the same words the pay screen uses.
 */
@Composable
private fun PassForm(draft: PassDraft, state: PassesAdminState, currency: String, model: PassesAdminViewModel) {
    var pickingDate by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        OutlinedTextField(
            value = draft.name,
            onValueChange = { v -> if (v.length <= 60) model.changeDraft { it.copy(name = v) } },
            label = { Text(t("pa3.pass_name")) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            modifier = Modifier.fillMaxWidth(),
        )

        SectionHeading(t("pa3.how_its_paid"))
        ChoiceRow(t("pa3.paid_once"), draft.billing == PassBilling.Once) { model.changeDraft { it.copy(billing = PassBilling.Once) } }
        ChoiceRow(t("pa3.paid_monthly"), draft.billing == PassBilling.Monthly) { model.changeDraft { it.copy(billing = PassBilling.Monthly) } }
        ChoiceRow(t("pa3.paid_in_parts"), draft.billing == PassBilling.Instalments) {
            model.changeDraft { it.copy(billing = PassBilling.Instalments) }
        }
        if (draft.billing == PassBilling.Monthly) Body(t("pa3.monthly_hint"))
        if (draft.billing == PassBilling.Instalments) {
            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(t("pa3.how_many_parts"), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                IconButton(
                    onClick = { model.changeDraft { it.copy(instalments = (it.instalments - 1).coerceAtLeast(2)) } },
                    enabled = draft.instalments > 2,
                ) { Icon(Icons.Filled.Remove, contentDescription = t("pa3.fewer_parts")) }
                Text("${draft.instalments}", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(horizontal = 8.dp))
                IconButton(
                    onClick = { model.changeDraft { it.copy(instalments = (it.instalments + 1).coerceAtMost(12)) } },
                    enabled = draft.instalments < 12,
                ) { Icon(Icons.Filled.Add, contentDescription = t("pa3.more_parts")) }
            }
        }
        AmountField(
            value = draft.price,
            onValue = { v -> model.changeDraft { it.copy(price = v) } },
            label = when (draft.billing) {
                PassBilling.Monthly -> t("pa3.price_each_month")
                PassBilling.Instalments -> t("pa3.price_whole")
                else -> t("sh.price")
            },
            currency = currency,
        )

        SectionHeading(t("pa3.what_it_covers"))
        SessionKind.entries.forEach { kind ->
            val on = kind in draft.covers
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .toggleable(value = on, role = Role.Checkbox) { now ->
                        model.changeDraft { it.copy(covers = if (now) it.covers + kind else it.covers - kind) }
                    },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Checkbox(checked = on, onCheckedChange = null)
                Text(kind.label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 12.dp))
            }
        }
        if (draft.covers.isEmpty()) Body(t("pa3.covers_nothing_hint"))

        if (draft.billing != PassBilling.Monthly) {
            SectionHeading(t("pa3.how_long"))
            ChoiceRow(
                draft.until?.takeIf { draft.length == PassLength.UntilDate }?.let { t("pa3.until_date", vars = mapOf("date" to dayMonth(it.toString()))) }
                    ?: t("pa3.until_a_date"),
                draft.length == PassLength.UntilDate,
            ) {
                model.changeDraft { it.copy(length = PassLength.UntilDate) }
                pickingDate = true
            }
            ChoiceRow(t("pa3.for_a_number"), draft.length == PassLength.Sessions) { model.changeDraft { it.copy(length = PassLength.Sessions) } }
            if (draft.length == PassLength.Sessions) {
                OutlinedTextField(
                    value = draft.sessions,
                    onValueChange = { v -> model.changeDraft { it.copy(sessions = v.filter(Char::isDigit).take(3)) } },
                    label = { Text(t("pa3.how_many_sessions")) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            ChoiceRow(t("pa3.no_end_date"), draft.length == PassLength.NoEnd) { model.changeDraft { it.copy(length = PassLength.NoEnd) } }
        }

        val groups = state.priceTypes.filter { !it.isArchived && !it.forGuests }
        if (groups.isNotEmpty()) {
            SectionHeading(t("pa3.who_can_have_it"))
            ChoiceRow(t("pa3.anyone_in_club"), draft.priceTypeId == null) { model.changeDraft { it.copy(priceTypeId = null) } }
            groups.forEach { type ->
                ChoiceRow(t("pa3.only_group", vars = mapOf("group" to type.name)), draft.priceTypeId == type.id) {
                    model.changeDraft { it.copy(priceTypeId = type.id) }
                }
            }
        }

        SwitchLine(t("pa3.players_can_get_it_switch"), t("pa3.players_can_get_it_hint"), draft.openToJoin) { on ->
            model.changeDraft { it.copy(openToJoin = on) }
        }

        // Exactly what a player reads, as it is typed.
        SectionHeading(t("pa2.players_will_see"))
        val preview = draft.preview(currency)
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(draft.name.ifBlank { "…" }, style = MaterialTheme.typography.titleMedium)
                Text(preview.priceWords(), style = MaterialTheme.typography.bodyLarge)
                Body(preview.coversLine())
                preview.onlyForWords(state.priceTypes)?.let { Body(it) }
            }
        }

        state.draftProblem?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.error) }
        Button(onClick = model::saveDraft, enabled = !state.isBusy, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
            Text(if (state.isBusy) t("la.saving") else t("pa3.make_this_pass"), style = MaterialTheme.typography.titleMedium)
        }
        TextButton(onClick = model::closeDraft, enabled = !state.isBusy, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) }
    }

    if (pickingDate) {
        DayPickerDialog(
            initial = draft.until ?: LocalDate.now().plusMonths(3),
            onPick = { day -> pickingDate = false; model.changeDraft { it.copy(until = day, length = PassLength.UntilDate) } },
            onDismiss = { pickingDate = false },
        )
    }
}

/** A switch with its words, the whole row a target. */
@Composable
internal fun SwitchLine(label: String, hint: String?, on: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .toggleable(value = on, enabled = enabled, role = Role.Switch, onValueChange = onChange),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            hint?.let { Body(it) }
        }
        Switch(checked = on, onCheckedChange = null, enabled = enabled)
    }
}

/**
 * The calendar, from today on. The picker speaks UTC midnights, so a day is
 * read back as a UTC date — read in the phone's zone it is a day early west
 * of Greenwich.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DayPickerDialog(initial: LocalDate, onPick: (LocalDate) -> Unit, onDismiss: () -> Unit) {
    val today = remember { LocalDate.now() }
    val state = rememberDatePickerState(
        initialSelectedDateMillis = initial.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
        selectableDates = object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long): Boolean =
                !Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate().isBefore(today)

            override fun isSelectableYear(year: Int): Boolean = year >= today.year
        },
    )
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                onClick = { state.selectedDateMillis?.let { onPick(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) } ?: onDismiss() },
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(t("rest.ok")) }
        },
        dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
    ) {
        DatePicker(state = state)
    }
}

// ---- one pass ----

/**
 * One pass: what it is, whether players can get it themselves, its price,
 * then everybody on it with how they stand — "A payment is late", "Paused"
 * — with Keep covering for those behind, and Take off.
 */
@Composable
private fun OnePass(plan: PassPlan, state: PassesAdminState, model: PassesAdminViewModel) {
    var adding by remember { mutableStateOf(false) }
    var pricing by remember { mutableStateOf(false) }
    var stopping by remember { mutableStateOf(false) }
    var takingOff by remember { mutableStateOf<PassHolder?>(null) }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Said(state)
        Text(plan.priceWords(), style = MaterialTheme.typography.titleMedium)
        Body(plan.coversLine())
        plan.onlyForWords(state.priceTypes)?.let { Body(it) }
        if (plan.isArchived) AmberNote(t("pa3.not_offered_note"))

        if (!plan.isArchived) {
            SwitchLine(t("pa3.players_can_get_it_switch"), t("pa3.players_can_get_it_hint"), plan.openToJoin, enabled = !state.isBusy) { on ->
                model.setOpenToJoin(plan, on)
            }
            Button(onClick = { adding = true }, enabled = !state.isBusy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Text(t("pa3.add_somebody"), modifier = Modifier.padding(start = 8.dp))
            }
        }
        ButtonRow(labels = listOf(t("pa3.change_price"), if (plan.isArchived) t("pa3.offer_again") else t("pa3.stop_offering"))) { i, m ->
            if (i == 0) {
                OutlinedButton(onClick = { pricing = true }, enabled = !state.isBusy, modifier = m.heightIn(min = 48.dp)) {
                    ButtonLabel(t("pa3.change_price"))
                }
            } else {
                TextButton(
                    onClick = { if (plan.isArchived) model.offerAgain(plan) else stopping = true },
                    enabled = !state.isBusy,
                    modifier = m.heightIn(min = 48.dp),
                ) { ButtonLabel(if (plan.isArchived) t("pa3.offer_again") else t("pa3.stop_offering")) }
            }
        }

        val running = state.holders.count { !it.isCancelled }
        SectionHeading(t("pa3.whos_on_it", vars = mapOf("n" to running)))
        when {
            state.holdersLoading && state.holders.isEmpty() -> CircularProgressIndicator()
            state.holders.isEmpty() -> Body(t("pa3.nobody_on_it"))
            else -> state.holders.forEach { holder ->
                HolderRow(
                    holder = holder,
                    busy = state.isBusy,
                    onKeepCovering = { on -> model.keepCovering(holder, on) },
                    onTakeOff = { takingOff = holder },
                )
            }
        }
    }

    if (adding) {
        AddToPassDialog(
            plan = plan,
            members = state.canAdd,
            onAdd = { member -> adding = false; model.add(member) },
            onDismiss = { adding = false },
        )
    }
    if (pricing) {
        PassPriceDialog(plan, onSave = { text -> model.changePrice(plan, text).also { if (it == null) pricing = false } }, onDismiss = { pricing = false })
    }
    if (stopping) {
        AlertDialog(
            onDismissRequest = { stopping = false },
            title = { Text(t("pa3.stop_offering_title", vars = mapOf("pass" to plan.name))) },
            text = { Text(t("pa3.stop_offering_body"), style = MaterialTheme.typography.bodyLarge) },
            confirmButton = {
                TextButton(
                    onClick = { stopping = false; model.stopOffering(plan) },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier.heightIn(min = 48.dp),
                ) { Text(t("pa3.stop_offering")) }
            },
            dismissButton = { TextButton(onClick = { stopping = false }, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
        )
    }
    takingOff?.let { holder ->
        AlertDialog(
            onDismissRequest = { takingOff = null },
            title = { Text(t("pa3.take_off_title", vars = mapOf("name" to holder.name, "pass" to plan.name))) },
            text = {
                Text(
                    if (holder.billing == PassBilling.Monthly) t("pa3.take_off_monthly_body") else t("pa3.take_off_body"),
                    style = MaterialTheme.typography.bodyLarge,
                )
            },
            confirmButton = {
                TextButton(
                    onClick = { takingOff = null; model.cancel(holder) },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier.heightIn(min = 48.dp),
                ) { Text(t("pa3.take_off")) }
            },
            dismissButton = { TextButton(onClick = { takingOff = null }, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
        )
    }
}

@Composable
private fun HolderRow(holder: PassHolder, busy: Boolean, onKeepCovering: (Boolean) -> Unit, onTakeOff: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(holder.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
        val words = holder.adminWords()
        if (words.isNotEmpty()) {
            Text(
                words,
                style = MaterialTheme.typography.bodyMedium,
                color = if (holder.needsPaying) AMBER else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        val behind = holder.standing == PassStanding.Behind || holder.standing == PassStanding.Suspended
        if (!holder.isCancelled && (behind || holder.keepCovering)) {
            SwitchLine(t("pa3.keep_covering"), t("pa3.keep_covering_hint"), holder.keepCovering, enabled = !busy, onChange = onKeepCovering)
        }
        if (!holder.isCancelled) {
            TextButton(
                onClick = onTakeOff,
                enabled = !busy,
                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(t("pa3.take_off")) }
        }
    }
    HorizontalDivider()
}

/** Pick one member to put on the pass. Their first payment is charged at once, and they are told. */
@Composable
private fun AddToPassDialog(plan: PassPlan, members: List<ClubMemberDetail>, onAdd: (ClubMemberDetail) -> Unit, onDismiss: () -> Unit) {
    var picked by remember { mutableStateOf<ClubMemberDetail?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(t("pa3.add_to_pass_title", vars = mapOf("pass" to plan.name))) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Body(t("pa3.add_to_pass_hint"))
                if (members.isEmpty()) Body(t("pa3.everyone_on_it"))
                members.forEach { member ->
                    ChoiceRow(member.name, picked?.userId == member.userId) { picked = member }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { picked?.let(onAdd) }, enabled = picked != null, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.add")) }
        },
        dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
    )
}

/** A new price, from the next payment. For a monthly pass it says who will be told. */
@Composable
private fun PassPriceDialog(plan: PassPlan, onSave: (String) -> String?, onDismiss: () -> Unit) {
    var text by rememberSaveable { mutableStateOf(amountText(plan.priceCents)) }
    var problem by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(t("pa3.change_price_title", vars = mapOf("pass" to plan.name))) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                AmountField(
                    value = text,
                    onValue = { text = it; problem = null },
                    label = if (plan.billing == PassBilling.Monthly) t("pa3.price_each_month") else t("sh.price"),
                    currency = plan.currency,
                    error = problem,
                )
                Body(if (plan.billing == PassBilling.Monthly) t("pa3.change_price_monthly_hint") else t("pa3.change_price_hint"))
            }
        },
        confirmButton = {
            TextButton(onClick = { problem = onSave(text) }, enabled = text.isNotBlank(), modifier = Modifier.heightIn(min = 48.dp)) { Text(t("lc.save")) }
        },
        dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
    )
}
