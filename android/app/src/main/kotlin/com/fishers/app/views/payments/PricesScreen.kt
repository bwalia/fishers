package com.fishers.app.views.payments

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SuggestionChip
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.i18n.t
import com.fishers.app.net.PaymentsApi
import com.fishers.app.payments.MoneyMember
import com.fishers.app.payments.Pick
import com.fishers.app.payments.PriceType
import com.fishers.app.payments.PriceTypeBody
import com.fishers.app.payments.PricesAdminState
import com.fishers.app.payments.PricesAdminViewModel
import com.fishers.app.views.clubs.ClubScreen
import com.fishers.app.views.clubs.ErrorLine
import com.fishers.app.views.clubs.SectionHeading
import com.fishers.app.views.nav.LocalAppDeps

/**
 * Payments → Prices for juniors, students…, for money admins: the club's
 * groups with their own price (one free, one for guests), then every member
 * — tap one to put them in a group and say who pays for them — and Add a
 * junior by name, for a parent to pay for.
 */
@Composable
internal fun PricesPage(clubId: String) {
    val deps = LocalAppDeps.current
    val model = remember(clubId) { PricesAdminViewModel(deps.service<PaymentsApi>(), clubId) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(clubId) { model.load() }

    var adding by remember { mutableStateOf(false) }
    var changing by remember { mutableStateOf<PriceType?>(null) }
    var member by remember { mutableStateOf<MoneyMember?>(null) }
    var addingJunior by remember { mutableStateOf(false) }

    ClubScreen(title = t("pa3.prices_title")) {
        when {
            state.types.isEmpty() && state.members.isEmpty() && state.isLoading ->
                Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            state.types.isEmpty() && state.loadError != null -> Column(Modifier.padding(24.dp)) {
                ErrorLine(state.loadError ?: "")
                TextButton(onClick = model::load, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("rest.try_again")) }
            }
            else -> Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                state.message?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary) }
                state.error?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.error) }
                Body(t("pa3.prices_intro"))

                // ---- the groups ----
                SectionHeading(t("pa3.groups"))
                if (state.inUse.isEmpty()) Body(t("pa3.no_groups_yet"))
                state.inUse.forEach { type ->
                    GroupRow(type, action = t("la.change"), busy = state.isBusy, onAction = { changing = type })
                }
                Button(onClick = { adding = true }, enabled = !state.isBusy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Text(t("pa3.add_group"), modifier = Modifier.padding(start = 8.dp))
                }
                Body(t("pa3.groups_session_hint"))
                if (state.notInUse.isNotEmpty()) {
                    Text(t("pa3.groups_not_used"), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp))
                    state.notInUse.forEach { type ->
                        GroupRow(type, action = t("pa3.use_again"), busy = state.isBusy, onAction = {
                            model.changeGroup(type, PriceTypeBody(archived = false), t("pa3.group_back", vars = mapOf("group" to type.name)))
                        })
                    }
                }

                // ---- members ----
                SectionHeading(t("cl.members"))
                Body(t("pa3.members_hint"))
                OutlinedButton(onClick = { addingJunior = true }, enabled = !state.isBusy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    Icon(Icons.Filled.PersonAdd, contentDescription = null)
                    Text(t("pa3.add_junior"), modifier = Modifier.padding(start = 8.dp))
                }
                state.roster.forEach { person ->
                    MemberRow(person, state, onOpen = { member = person })
                }
            }
        }
    }

    if (adding) {
        AddGroupDialog(
            busy = state.isBusy,
            onAdd = { name, free, guests -> model.addGroup(name, free, guests).also { if (it == null) adding = false } },
            onDismiss = { adding = false },
        )
    }
    changing?.let { type ->
        ChangeGroupDialog(
            type = type,
            onSave = { body -> changing = null; model.changeGroup(type, body, t("pa3.group_saved", vars = mapOf("group" to (body.name ?: type.name)))) },
            onStop = { changing = null; model.changeGroup(type, PriceTypeBody(archived = true), t("pa3.group_stopped", vars = mapOf("group" to type.name))) },
            onDismiss = { changing = null },
        )
    }
    member?.let { person ->
        MemberMoneyDialog(
            member = person,
            state = state,
            onSave = { group, payer -> member = null; model.saveMember(person, group, payer) },
            onDismiss = { member = null },
        )
    }
    if (addingJunior) {
        AddJuniorDialog(
            payers = state.payers,
            onAdd = { name, payer -> model.addJunior(name, payer).also { if (it == null) addingJunior = false } },
            onDismiss = { addingJunior = false },
        )
    }
}

@Composable
private fun GroupRow(type: PriceType, action: String, busy: Boolean, onAction: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(type.label, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
        TextButton(onClick = onAction, enabled = !busy, modifier = Modifier.heightIn(min = 48.dp)) { Text(action) }
    }
    HorizontalDivider()
}

/** A member, with their price and who pays: "Junior · Neha Gill pays". */
@Composable
private fun MemberRow(person: MoneyMember, state: PricesAdminState, onOpen: () -> Unit) {
    val said = listOf(
        state.groupOf(person)?.name ?: t("pa3.standard_price"),
        person.payerName?.let { t("pa3.name_pays", vars = mapOf("name" to it)) } ?: t("pa3.pays_themselves"),
    )
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(role = Role.Button, onClick = onOpen)
            .padding(vertical = 8.dp),
    ) {
        Text(person.name, style = MaterialTheme.typography.bodyLarge)
        Body(said.joinToString(" · "))
    }
    HorizontalDivider()
}

/** "Add a group": a name, and whether it is free or the guests' price. Common ones are a tap away. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AddGroupDialog(busy: Boolean, onAdd: (String, Boolean, Boolean) -> String?, onDismiss: () -> Unit) {
    var name by rememberSaveable { mutableStateOf("") }
    var free by rememberSaveable { mutableStateOf(false) }
    var guests by rememberSaveable { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(t("pa3.add_group")) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(
                        Triple(t("pa3.suggest_junior"), false, false),
                        Triple(t("pa3.suggest_student"), false, false),
                        Triple(t("pa3.suggest_coach"), true, false),
                        Triple(t("pay.guest"), false, true),
                    ).forEach { (word, isFree, isGuest) ->
                        SuggestionChip(
                            onClick = { name = word; free = isFree; guests = isGuest; problem = null },
                            label = { Text(word) },
                            modifier = Modifier.heightIn(min = 48.dp),
                        )
                    }
                }
                OutlinedTextField(
                    value = name,
                    onValueChange = { if (it.length <= 30) { name = it; problem = null } },
                    label = { Text(t("pa3.group_name")) },
                    singleLine = true,
                    isError = problem != null,
                    supportingText = problem?.let { { Text(it) } },
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    modifier = Modifier.fillMaxWidth(),
                )
                SwitchLine(t("pa3.group_is_free"), t("pa3.group_is_free_hint"), free) { free = it }
                SwitchLine(t("pa3.group_is_guests"), t("pa3.group_is_guests_hint"), guests) { guests = it }
            }
        },
        confirmButton = {
            TextButton(onClick = { problem = onAdd(name, free, guests) }, enabled = !busy && name.isNotBlank(), modifier = Modifier.heightIn(min = 48.dp)) {
                Text(t("sc.add"))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
    )
}

@Composable
private fun ChangeGroupDialog(type: PriceType, onSave: (PriceTypeBody) -> Unit, onStop: () -> Unit, onDismiss: () -> Unit) {
    var name by rememberSaveable { mutableStateOf(type.name) }
    var free by rememberSaveable { mutableStateOf(type.free) }
    var guests by rememberSaveable { mutableStateOf(type.forGuests) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(type.name) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { if (it.length <= 30) name = it },
                    label = { Text(t("pa3.group_name")) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    modifier = Modifier.fillMaxWidth(),
                )
                SwitchLine(t("pa3.group_is_free"), t("pa3.group_is_free_hint"), free) { free = it }
                SwitchLine(t("pa3.group_is_guests"), t("pa3.group_is_guests_hint"), guests) { guests = it }
                TextButton(onClick = onStop, modifier = Modifier.heightIn(min = 48.dp)) {
                    Text(t("pa3.stop_using_group"), color = MaterialTheme.colorScheme.error)
                }
                Body(t("pa3.stop_using_group_hint"))
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onSave(
                        PriceTypeBody(
                            name = name.trim().takeIf { it.isNotEmpty() && it != type.name },
                            free = free.takeIf { it != type.free },
                            forGuests = guests.takeIf { it != type.forGuests },
                        ),
                    )
                },
                enabled = name.isNotBlank(),
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(t("lc.save")) }
        },
        dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
    )
}

/**
 * One member's money: their price (the standard one, or a group's) and who
 * pays for them. Only what is picked here is sent.
 */
@Composable
private fun MemberMoneyDialog(
    member: MoneyMember,
    state: PricesAdminState,
    onSave: (Pick<PriceType?>?, Pick<MoneyMember?>?) -> Unit,
    onDismiss: () -> Unit,
) {
    var group by remember { mutableStateOf(Pick(state.groupOf(member))) }
    var payer by remember { mutableStateOf(Pick(member.payerId?.let { id -> state.members.firstOrNull { it.userId == id } })) }
    var changedGroup by remember { mutableStateOf(false) }
    var changedPayer by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(member.name) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Text(t("pa3.their_price"), style = MaterialTheme.typography.titleSmall)
                ChoiceRow(t("pa3.standard_price"), group.value == null) { group = Pick(null); changedGroup = true }
                state.inUse.filter { !it.forGuests }.forEach { type ->
                    ChoiceRow(type.label, group.value?.id == type.id) { group = Pick(type); changedGroup = true }
                }
                Text(t("pa3.who_pays_for_them"), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 16.dp))
                ChoiceRow(t("pa3.they_pay_themselves"), payer.value == null) { payer = Pick(null); changedPayer = true }
                state.payers.filter { it.userId != member.userId }.forEach { other ->
                    ChoiceRow(other.name, payer.value?.userId == other.userId) { payer = Pick(other); changedPayer = true }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(group.takeIf { changedGroup }, payer.takeIf { changedPayer }) },
                enabled = changedGroup || changedPayer,
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(t("lc.save")) }
        },
        dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
    )
}

/** "Add a junior by name": no sign-in of their own; a member who pays for them. */
@Composable
private fun AddJuniorDialog(payers: List<MoneyMember>, onAdd: (String, MoneyMember?) -> String?, onDismiss: () -> Unit) {
    var name by rememberSaveable { mutableStateOf("") }
    var payer by remember { mutableStateOf<MoneyMember?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(t("pa3.add_junior")) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Body(t("pa3.add_junior_hint"))
                OutlinedTextField(
                    value = name,
                    onValueChange = { if (it.length <= 70) { name = it; problem = null } },
                    label = { Text(t("pa3.junior_name")) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(t("pa3.who_pays_for_them"), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp))
                payers.forEach { p -> ChoiceRow(p.name, payer?.userId == p.userId) { payer = p; problem = null } }
                problem?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            TextButton(onClick = { problem = onAdd(name, payer) }, enabled = name.isNotBlank(), modifier = Modifier.heightIn(min = 48.dp)) {
                Text(t("sc.add"))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) } },
    )
}
