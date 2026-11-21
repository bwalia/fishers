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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.clubs.money
import com.fishers.app.i18n.t
import com.fishers.app.net.PaymentsApi
import com.fishers.app.payments.CostMode
import com.fishers.app.payments.FeeWho
import com.fishers.app.payments.GroupFee
import com.fishers.app.payments.GroupFeeDraft
import com.fishers.app.payments.GroupFeesState
import com.fishers.app.payments.GroupFeesViewModel
import com.fishers.app.payments.LinkUse
import com.fishers.app.payments.Outgoing
import com.fishers.app.payments.dayMonth
import com.fishers.app.views.clubs.ClubScreen
import com.fishers.app.views.clubs.ErrorLine
import com.fishers.app.views.clubs.SectionHeading
import com.fishers.app.views.nav.LocalAppDeps
import java.time.LocalDate

/**
 * Payments → Group fees, for money admins: a charge that isn't one session.
 * The list; New group fee (who, how much, by when); one opened with
 * everybody's lines, Share to WhatsApp and Cancel. The form and an opened
 * one sit in place of the list; Back returns to it.
 */
@Composable
internal fun GroupFeesPage(clubId: String, currency: String) {
    val deps = LocalAppDeps.current
    val model = remember(clubId) { GroupFeesViewModel(deps.service<PaymentsApi>(), clubId) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(clubId) { model.load() }

    // The link's words go to WhatsApp, or the link to the clipboard, once.
    val context = LocalContext.current
    LaunchedEffect(state.outgoing) {
        when (val out = state.outgoing ?: return@LaunchedEffect) {
            is Outgoing.Share -> shareToWhatsApp(context, out.text)
            is Outgoing.Copy -> copy(context, t("pa2.pay_link"), out.url)
        }
        model.handled()
    }

    val draft = state.draft
    val open = state.open
    BackHandler(enabled = draft != null || open != null) { if (draft != null) model.closeDraft() else model.close() }

    ClubScreen(
        title = when {
            draft != null -> t("pa3.new_group_fee")
            open != null -> open.title
            else -> t("pa3.group_fees")
        },
    ) {
        when {
            draft != null -> FeeForm(draft, state, currency, model)
            open != null -> OneFee(open, state, model)
            state.fees.isEmpty() && state.isLoading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            state.fees.isEmpty() && state.loadError != null -> Column(Modifier.padding(24.dp)) {
                ErrorLine(state.loadError ?: "")
                TextButton(onClick = model::load, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("rest.try_again")) }
            }
            else -> FeeList(state, model)
        }
    }
}

@Composable
private fun Said(state: GroupFeesState) {
    state.message?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary) }
    state.error?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.error) }
}

@Composable
private fun FeeList(state: GroupFeesState, model: GroupFeesViewModel) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Said(state)
        Body(t("pa3.group_fees_hint"))
        Button(onClick = model::startNew, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
            Icon(Icons.Filled.Add, contentDescription = null)
            Text(t("pa3.new_group_fee"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 8.dp))
        }
        if (state.fees.isEmpty()) {
            Body(t("pa3.no_group_fees"))
        } else {
            SectionHeading(t("pa3.group_fees"))
            state.fees.forEach { fee ->
                Column(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 56.dp)
                        .clickable(role = Role.Button) { model.open(fee.id) }
                        .padding(vertical = 8.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(fee.title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                        Text(money(fee.totalCents, fee.currency), style = MaterialTheme.typography.bodyLarge)
                    }
                    Body(
                        if (fee.isCancelled) t("pay.state_void")
                        else listOf(
                            fee.howMuchWords(),
                            t("pay.collected_of_total", vars = mapOf("collected" to money(fee.paidCents, fee.currency), "total" to money(fee.totalCents, fee.currency))),
                        ).joinToString(" · "),
                    )
                }
                HorizontalDivider()
            }
        }
    }
}

// ---- a new one ----

/**
 * New group fee: what it's for; who (everyone, a team, a group such as the
 * juniors, or ticked names, plus guests); how much (a total to split, or the
 * same from each); and a date to pay by.
 */
@Composable
private fun FeeForm(draft: GroupFeeDraft, state: GroupFeesState, currency: String, model: GroupFeesViewModel) {
    var pickingDate by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        OutlinedTextField(
            value = draft.title,
            onValueChange = { v -> if (v.length <= 80) model.changeDraft { it.copy(title = v) } },
            label = { Text(t("pa3.fee_what_for")) },
            placeholder = { Text(t("pa3.fee_what_for_example")) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            modifier = Modifier.fillMaxWidth(),
        )

        SectionHeading(t("pa3.fee_who"))
        ChoiceRow(t("pa3.fee_everyone"), draft.who == FeeWho.Everyone) { model.changeDraft { it.copy(who = FeeWho.Everyone) } }
        if (state.teams.isNotEmpty()) {
            ChoiceRow(t("pa3.fee_a_team"), draft.who == FeeWho.Team) { model.changeDraft { it.copy(who = FeeWho.Team) } }
            if (draft.who == FeeWho.Team) {
                Column(Modifier.padding(start = 24.dp)) {
                    state.teams.forEach { team ->
                        ChoiceRow(team.name, draft.teamId == team.id) { model.changeDraft { it.copy(teamId = team.id) } }
                    }
                }
            }
        }
        val groups = state.priceTypes.filter { !it.forGuests }
        if (groups.isNotEmpty()) {
            ChoiceRow(t("pa3.fee_a_group"), draft.who == FeeWho.Group) { model.changeDraft { it.copy(who = FeeWho.Group) } }
            if (draft.who == FeeWho.Group) {
                Column(Modifier.padding(start = 24.dp)) {
                    groups.forEach { type ->
                        ChoiceRow(type.name, draft.priceTypeId == type.id) { model.changeDraft { it.copy(priceTypeId = type.id) } }
                    }
                }
            }
        }
        ChoiceRow(t("pa3.fee_pick_names_choice"), draft.who == FeeWho.Names) { model.changeDraft { it.copy(who = FeeWho.Names) } }
        if (draft.who == FeeWho.Names) {
            Column(Modifier.padding(start = 24.dp)) {
                state.members.filter { it.isOnTheBooks }.sortedBy { it.name.lowercase() }.forEach { member ->
                    val ticked = member.userId in draft.names
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .toggleable(value = ticked, role = Role.Checkbox) { on ->
                                model.changeDraft { it.copy(names = if (on) it.names + member.userId else it.names - member.userId) }
                            },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Checkbox(checked = ticked, onCheckedChange = null)
                        Text(member.name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 12.dp))
                    }
                }
            }
        }

        Text(t("pay.guests"), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp))
        Body(t("pa3.fee_guests_hint"))
        draft.guests.forEach { guest ->
            Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(guest, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                IconButton(onClick = { model.changeDraft { it.copy(guests = it.guests - guest) } }) {
                    Icon(Icons.Filled.Close, contentDescription = t("pay.remove_guest", vars = mapOf("name" to guest)))
                }
            }
        }
        GuestField(onAdd = { name ->
            val clean = name.trim().split(Regex("\\s+")).joinToString(" ")
            model.changeDraft { d -> if (clean.isEmpty() || d.guests.any { it.equals(clean, ignoreCase = true) }) d else d.copy(guests = d.guests + clean) }
        })

        SectionHeading(t("pa3.fee_how_much"))
        CostModeChoice(draft.mode, onMode = { m -> model.changeDraft { it.copy(mode = m) } })
        AmountField(
            value = draft.amount,
            onValue = { v -> model.changeDraft { it.copy(amount = v) } },
            label = if (draft.mode == CostMode.SplitTotal) t("pay.total_cost") else t("pay.each_pays"),
            currency = currency,
        )

        SectionHeading(t("pa3.fee_by_when"))
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(onClick = { pickingDate = true }, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(draft.dueOn?.let { t("pa3.by_date", vars = mapOf("date" to dayMonth(it.toString()))) } ?: t("pa3.fee_pick_date"))
            }
            if (draft.dueOn != null) {
                TextButton(onClick = { model.changeDraft { it.copy(dueOn = null) } }, modifier = Modifier.heightIn(min = 48.dp)) {
                    Text(t("pa3.fee_no_date"))
                }
            }
        }

        OutlinedTextField(
            value = draft.note,
            onValueChange = { v -> if (v.length <= 200) model.changeDraft { it.copy(note = v) } },
            label = { Text(t("pay.note_optional")) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )

        state.draftProblem?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.error) }
        Body(t("pa3.fee_everyone_told"))
        Button(onClick = model::saveDraft, enabled = !state.isBusy, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
            Text(if (state.isBusy) t("pay.sending") else t("pa3.fee_send"), style = MaterialTheme.typography.titleMedium)
        }
        TextButton(onClick = model::closeDraft, enabled = !state.isBusy, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) }
    }

    if (pickingDate) {
        DayPickerDialog(
            initial = draft.dueOn ?: LocalDate.now().plusWeeks(2),
            onPick = { day -> pickingDate = false; model.changeDraft { it.copy(dueOn = day) } },
            onDismiss = { pickingDate = false },
        )
    }
}

// ---- one opened ----

@Composable
private fun OneFee(fee: GroupFee, state: GroupFeesState, model: GroupFeesViewModel) {
    var cancelling by remember { mutableStateOf(false) }
    var switchingOff by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Said(state)
        Text(fee.howMuchWords(), style = MaterialTheme.typography.titleMedium)
        fee.note?.let { Body(it) }
        if (fee.isCancelled) {
            StopNote(fee.voidReason?.let { t("pa3.fee_cancelled_because", vars = mapOf("reason" to it)) } ?: t("pay.state_void"))
        } else {
            Text(
                t("pay.collected_of_total", vars = mapOf("collected" to money(fee.paidCents, fee.currency), "total" to money(fee.totalCents, fee.currency))),
                style = MaterialTheme.typography.titleSmall,
            )
            AmountLine(t("pay.waiting_to_check"), money(fee.waitingCents, fee.currency))
            AmountLine(t("pay.still_owed"), money(fee.owedCents, fee.currency))

            // ---- share to WhatsApp ----
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Text(t("pa2.share_to_whatsapp"), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.semantics { heading() })
            Body(t("pa2.share_hint"))
            Button(onClick = { model.share(fee, LinkUse.Bill) }, enabled = !state.isBusy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Icon(Icons.Filled.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(if (state.isBusy) t("pa2.getting_link") else t("pa3.share_group_fee"), modifier = Modifier.padding(start = 8.dp))
            }
            if (fee.anyoneOwes) {
                OutlinedButton(onClick = { model.share(fee, LinkUse.Reminder) }, enabled = !state.isBusy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    Text(t("pa2.remind_who_hasnt_paid"))
                }
            }
            Row {
                TextButton(onClick = { model.share(fee, LinkUse.CopyLink) }, enabled = !state.isBusy, modifier = Modifier.heightIn(min = 48.dp)) {
                    Icon(Icons.Filled.Link, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(t("pa2.copy_link"), modifier = Modifier.padding(start = 8.dp))
                }
                TextButton(onClick = { switchingOff = true }, enabled = !state.isBusy, modifier = Modifier.heightIn(min = 48.dp)) {
                    Text(t("pa2.switch_link_off"))
                }
            }
        }

        // ---- everybody's lines ----
        if (fee.shares.isNotEmpty()) {
            SectionHeading(t("pa3.fee_people", vars = mapOf("n" to fee.shares.size)))
            fee.shares.forEach { share ->
                Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(share.name, style = MaterialTheme.typography.bodyLarge)
                        if (share.userId == null) Body(t("pay.guest"))
                        share.reason?.let { Body(it) }
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        if (!share.isCovered) Text(money(share.amountCents, share.currency), style = MaterialTheme.typography.bodyMedium)
                        StateLabel(share, admin = true)
                    }
                }
                HorizontalDivider()
            }
        }

        if (!fee.isCancelled) {
            TextButton(
                onClick = { cancelling = true },
                enabled = !state.isBusy,
                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(t("pa3.cancel_group_fee")) }
        }
    }

    if (cancelling) {
        ReasonDialog(
            title = t("pa3.cancel_group_fee_title", vars = mapOf("title" to fee.title)),
            explainer = t("pa3.cancel_group_fee_body"),
            confirm = t("pa3.cancel_group_fee"),
            destructive = true,
            onConfirm = { cancelling = false; model.cancel(fee, it) },
            onDismiss = { cancelling = false },
        )
    }
    if (switchingOff) {
        AlertDialog(
            onDismissRequest = { switchingOff = false },
            title = { Text(t("pa2.switch_link_off_title")) },
            text = { Text(t("pa3.switch_fee_link_off_body"), style = MaterialTheme.typography.bodyLarge) },
            confirmButton = {
                TextButton(
                    onClick = { switchingOff = false; model.switchLinkOff(fee) },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier.heightIn(min = 48.dp),
                ) { Text(t("pa2.switch_link_off")) }
            },
            dismissButton = { TextButton(onClick = { switchingOff = false }, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
        )
    }
}
