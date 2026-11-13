package com.fishers.app.views.match.start

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.fishers.app.R
import com.fishers.app.i18n.t
import com.fishers.app.match.start.Ball
import com.fishers.app.match.start.Ground
import com.fishers.app.match.start.MatchConditions
import com.fishers.app.match.start.MatchPlayer
import com.fishers.app.match.start.MatchSetupState
import com.fishers.app.match.start.MatchSetupViewModel
import com.fishers.app.match.start.SetupStep
import com.fishers.app.match.start.Side
import com.fishers.app.match.start.TossCall

/** The wizard — `CricketScoringFlowView.swift`'s steps before the live scorer. */
@Composable
fun MatchSetupScreen(
    state: MatchSetupState,
    model: MatchSetupViewModel,
    onBack: () -> Unit,
    onPickOpposition: () -> Unit,
    onFollow: () -> Unit,
) {
    val title = state.title.ifBlank { t("ld.start_match") }
    StartPage(
        title = title,
        onBack = onBack,
        actions = {
            // Another captain agreeing on their own phone is news only with signal.
            if (state.step == SetupStep.Agreement && !state.offline) {
                IconButton(onClick = model::refresh) {
                    Icon(Icons.Filled.Refresh, contentDescription = t("sc.refresh"))
                }
            }
        },
    ) {
        if (state.isLoading) {
            Loading()
            return@StartPage
        }
        state.blocked?.let {
            ErrorLine(it)
            BigButton(t("ms.follow_the_match"), onClick = onFollow)
            return@StartPage
        }
        if (state.offline) OfflineNote(t("ms.kept_on_this_phone"))
        Footnote(stepLabel(state.step))
        when (state.step) {
            SetupStep.Terms -> TermsStep(state, model, onPickOpposition)
            SetupStep.Agreement -> AgreementStep(state, model)
            SetupStep.Toss -> TossStep(state, model)
            SetupStep.Sheets -> SheetsStep(state, model)
            SetupStep.Openers -> OpenersStep(state, model)
            SetupStep.Scoring -> Loading()
        }
    }
}

private fun stepLabel(step: SetupStep): String {
    val (n, name) = when (step) {
        SetupStep.Terms -> 1 to t("sc.format")
        SetupStep.Agreement -> 2 to t("lp.captains")
        SetupStep.Toss -> 3 to t("sc.the_toss")
        SetupStep.Sheets -> 4 to t("la.team_sheets")
        SetupStep.Openers, SetupStep.Scoring -> 5 to t("sc.openers")
    }
    return t("ms.step_of", vars = mapOf("n" to n, "total" to 5, "name" to name))
}

// MARK: Step 1 — the match and its terms

@Composable
private fun TermsStep(state: MatchSetupState, model: MatchSetupViewModel, onPickOpposition: () -> Unit) {
    val brand = stringResource(R.string.brand_name)
    val c = state.conditions

    OutlinedTextField(
        value = state.homeName,
        onValueChange = model::setHomeName,
        label = { Text(t("sc.batting_first_home_side")) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
        modifier = Modifier.fillMaxWidth(),
    )
    OutlinedButton(onClick = onPickOpposition, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
        Column(Modifier.fillMaxWidth()) {
            Text(t("sc.opposition"), style = MaterialTheme.typography.labelMedium)
            Text(state.awayName.ifBlank { t("sc.choose_ellipsis") }, style = MaterialTheme.typography.titleMedium)
            if (state.opponent != null) {
                Text(t("ms.on_brand", vars = mapOf("brand" to brand)), style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary)
            }
        }
    }
    Footnote(t("ms.code_search_or_type"))

    SectionTitle(t("sc.format"))
    Text(t("sc.overs"), style = MaterialTheme.typography.labelLarge)
    Choices(MatchConditions.overPresets, c.oversLimit, { it.toString() }, model::setOvers, minWidth = 64.dp)
    Stepper(
        t("sc.overs_per_bowler"),
        if (c.oversPerBowler == 0) t("sc.no_bowler_limit") else c.oversPerBowler.toString(),
        onMinus = { model.setConditions(c.copy(oversPerBowler = c.oversPerBowler - 1)) },
        onPlus = { model.setConditions(c.copy(oversPerBowler = c.oversPerBowler + 1)) },
        canMinus = c.oversPerBowler > 0,
        canPlus = c.oversPerBowler < c.oversLimit,
    )
    Stepper(
        t("sc.powerplay_overs"),
        if (c.powerplayOvers == 0) t("sc.no_powerplay") else c.powerplayOvers.toString(),
        onMinus = { model.setConditions(c.copy(powerplayOvers = c.powerplayOvers - 1)) },
        onPlus = { model.setConditions(c.copy(powerplayOvers = c.powerplayOvers + 1)) },
        canMinus = c.powerplayOvers > 0,
        canPlus = c.powerplayOvers < c.oversLimit,
    )
    Stepper(
        t("sc.overs_per_hour"),
        if (c.targetOversPerHour == 0) t("sc.over_rate_not_counted") else c.targetOversPerHour.toString(),
        onMinus = { model.setConditions(c.copy(targetOversPerHour = c.targetOversPerHour - 1)) },
        onPlus = { model.setConditions(c.copy(targetOversPerHour = c.targetOversPerHour + 1)) },
        canMinus = c.targetOversPerHour > 0,
        canPlus = c.targetOversPerHour < 25,
    )
    Footnote(
        t("sc.usual_allocation_and_powerplay", vars = mapOf(
            "perBowler" to MatchConditions.standardOversPerBowler(c.oversLimit),
            "overs" to c.oversLimit,
            "powerplay" to MatchConditions.standardPowerplay(c.oversLimit),
        )),
    )

    SectionTitle(t("sc.ground"))
    Ground.entries.forEach { ground ->
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clickable(role = Role.RadioButton) { model.setConditions(c.copy(ground = ground)) },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            RadioButton(selected = c.ground == ground, onClick = null)
            Column(Modifier.padding(start = 8.dp)) {
                Text(ground.label, style = MaterialTheme.typography.bodyLarge)
                Footnote(ground.blurb)
            }
        }
    }

    SectionTitle(t("sc.fielding_restrictions"))
    Stepper(
        t("sc.fielders_out_powerplay"), c.fieldersOutsidePowerplay.toString(),
        onMinus = { model.setConditions(c.copy(fieldersOutsidePowerplay = c.fieldersOutsidePowerplay - 1)) },
        onPlus = { model.setConditions(c.copy(fieldersOutsidePowerplay = c.fieldersOutsidePowerplay + 1)) },
        canMinus = c.fieldersOutsidePowerplay > 0, canPlus = c.fieldersOutsidePowerplay < 11,
    )
    Stepper(
        t("sc.fielders_out_after"), c.fieldersOutsideNormal.toString(),
        onMinus = { model.setConditions(c.copy(fieldersOutsideNormal = c.fieldersOutsideNormal - 1)) },
        onPlus = { model.setConditions(c.copy(fieldersOutsideNormal = c.fieldersOutsideNormal + 1)) },
        canMinus = c.fieldersOutsideNormal > 0, canPlus = c.fieldersOutsideNormal < 11,
    )
    Footnote(t("sc.two_and_five_standard"))

    SectionTitle(t("sc.ball"))
    Choices(Ball.entries, c.ball, { it.label }, { model.setConditions(c.copy(ball = it)) })

    ErrorLine(state.error)
    BigButton(t("la.propose_these_terms"), onClick = model::propose, enabled = state.canPropose, busy = state.isBusy)
    Footnote(t("sc.both_captains_must_agree"))
}

// MARK: Step 2 — both captains agree

@Composable
private fun AgreementStep(state: MatchSetupState, model: MatchSetupViewModel) {
    var agreeing by remember { mutableStateOf<Side?>(null) }
    val book = state.book

    SectionTitle(t("sc.on_the_table"))
    Text((book.conditions ?: state.conditions).summary, style = MaterialTheme.typography.titleMedium)
    Footnote(t("sc.change_means_agree_again"))

    SectionTitle(t("lp.captains"))
    Side.entries.forEach { side ->
        Row(Modifier.fillMaxWidth().heightIn(min = 56.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(book.name(side), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                val agreed = book.agreed(side)
                if (agreed != null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Text(agreed, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(start = 4.dp))
                    }
                } else {
                    Footnote(t("sc.not_agreed_yet"))
                }
            }
            if (book.agreed(side) == null) {
                OutlinedButton(onClick = { agreeing = side }, enabled = !state.isBusy,
                    modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.agree")) }
            }
        }
        HorizontalDivider()
    }

    ErrorLine(state.error)
    BigButton(t("sc.continue_to_the_toss"), onClick = model::continueToToss, enabled = book.bothAgreed, busy = state.isBusy)
    TextButton(onClick = model::changeTerms, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.change_the_terms")) }
    if (!book.bothAgreed) {
        val waiting = Side.entries.filter { book.agreed(it) == null }.joinToString(", ") { book.name(it) }
        Footnote(t("sc.waiting_on_names", vars = mapOf("names" to waiting)))
    }

    agreeing?.let { side ->
        CaptainDialog(
            teamName = book.name(side),
            candidates = state.pool(side),
            initial = model.suggestedCaptain(side),
            onAgree = { name -> agreeing = null; model.agree(side, name) },
            onCancel = { agreeing = null },
        )
    }
}

/** Naming the captain who agreed: picked from their squad where we can read it, typed where we cannot. */
@Composable
private fun CaptainDialog(
    teamName: String,
    candidates: List<MatchPlayer>,
    initial: String,
    onAgree: (String) -> Unit,
    onCancel: () -> Unit,
) {
    var name by rememberSaveable { mutableStateOf(initial) }
    val matches = remember(name, candidates) {
        val term = name.trim().lowercase()
        if (term.isEmpty()) candidates.take(8)
        else (candidates.filter { it.name.lowercase().startsWith(term) } +
            candidates.filter { !it.name.lowercase().startsWith(term) && it.name.lowercase().contains(term) }).take(8)
    }
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(t("sc.captain_of", vars = mapOf("team" to teamName))) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(t("cl.name")) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    modifier = Modifier.fillMaxWidth(),
                )
                if (candidates.isNotEmpty()) {
                    Text(t("cl.their_squad"), style = MaterialTheme.typography.labelLarge)
                    matches.forEach { player ->
                        Text(
                            player.name,
                            style = MaterialTheme.typography.bodyLarge,
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(min = 44.dp)
                                .clickable { name = player.name }
                                .padding(vertical = 10.dp),
                        )
                    }
                }
                Footnote(t("sc.recorded_against_agreement"))
            }
        },
        confirmButton = {
            Button(onClick = { onAgree(name) }, enabled = name.isNotBlank()) { Text(t("sc.agree")) }
        },
        dismissButton = { TextButton(onClick = onCancel) { Text(t("sc.cancel")) } },
    )
}

// MARK: Step 3 — the toss

@Composable
private fun TossStep(state: MatchSetupState, model: MatchSetupViewModel) {
    val book = state.book
    Footnote((book.conditions ?: state.conditions).summary)
    val home = book.agreedHome
    val away = book.agreedAway
    if (home != null && away != null) {
        Footnote(t("sc.agreed_by_both", vars = mapOf("home" to home, "away" to away)))
    }
    SectionTitle(t("sc.who_won_the_toss"))
    Choices(Side.entries, state.tossWinner, { book.name(it) }, model::setToss)
    SectionTitle(t("sc.and_chose_to"))
    Choices(TossCall.entries, state.tossDecision, { it.label }, model::setTossDecision)
    Text(t("sc.team_bat_first_dot", vars = mapOf("team" to book.name(state.battingFirst))),
        style = MaterialTheme.typography.titleMedium)
    ErrorLine(state.error)
    BigButton(t("sc.record_toss"), onClick = model::recordToss, busy = state.isBusy)
}

// MARK: Step 4 — the team sheets

@Composable
private fun SheetsStep(state: MatchSetupState, model: MatchSetupViewModel) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val book = state.book
    TabRow(selectedTabIndex = tab) {
        Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text(book.name(Side.Home), maxLines = 1) })
        Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text(book.name(Side.Away), maxLines = 1) })
        Tab(selected = tab == 2, onClick = { tab = 2 }, text = { Text(t("sc.officials"), maxLines = 1) })
    }
    when (tab) {
        0 -> SheetEditor(state, Side.Home, model)
        1 -> SheetEditor(state, Side.Away, model)
        else -> OfficialsEditor(state, model)
    }

    HorizontalDivider()
    Footnote(t("sc.n_umpires_appointed", count = state.umpires.size, vars = mapOf("n" to state.umpires.size)))
    ErrorLine(state.error)
    Side.entries.forEach { side ->
        val named = state.named(side)
        BigButton(
            if (named) "${book.name(side)} — ${t("sc.named")}"
            else t("ms.confirm_side", vars = mapOf("team" to book.name(side), "n" to state.sheet(side).size)),
            onClick = { model.confirmSheet(side) },
            enabled = !named && state.sheet(side).size >= 2,
            busy = state.isBusy && !named,
        )
    }
    if (state.named(Side.Home) && state.named(Side.Away)) {
        BigButton(t("le.continue"), onClick = model::continueToOpeners, busy = state.isBusy)
    }
}

/** One side's sheet: pick from the club, add a guest, set the batting order. */
@Composable
private fun SheetEditor(state: MatchSetupState, side: Side, model: MatchSetupViewModel) {
    val sheet = state.sheet(side)
    val named = state.named(side)
    SectionTitle(t("sc.batting_order_count", vars = mapOf("team" to state.book.name(side), "n" to sheet.size)))
    if (sheet.isEmpty()) Footnote(t("sc.nobody_picked_yet"))
    sheet.forEachIndexed { index, player ->
        SheetRow(
            index = index,
            player = player,
            isCaptain = state.captain(side) == player.id,
            isKeeper = state.keeper(side) == player.id,
            isFirst = index == 0,
            isLast = index == sheet.lastIndex,
            locked = named,
            onCaptain = { model.setCaptain(side, if (state.captain(side) == player.id) null else player.id) },
            onKeeper = { model.setKeeper(side, if (state.keeper(side) == player.id) null else player.id) },
            onMove = { up -> model.movePlayer(side, player.id, up) },
            onRemove = { model.removePlayer(side, player.id) },
        )
    }
    if (named) return

    SectionTitle(t("sc.add_guest_or_opposition"))
    AddByName { model.addGuest(side, it) }

    val available = state.available(side)
    if (available.isNotEmpty()) {
        SectionTitle(t("cl.from_the_club"))
        available.forEach { player ->
            PoolRow(player, isCaptain = player.id in state.captains) { model.addPlayer(side, player) }
        }
    }
}

@Composable
private fun SheetRow(
    index: Int,
    player: MatchPlayer,
    isCaptain: Boolean,
    isKeeper: Boolean,
    isFirst: Boolean,
    isLast: Boolean,
    locked: Boolean,
    onCaptain: () -> Unit,
    onKeeper: () -> Unit,
    onMove: (up: Boolean) -> Unit,
    onRemove: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("${index + 1}", style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(28.dp))
        Text(player.name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        if (isCaptain) Badge("C")
        if (isKeeper) Badge(t("sc.wk"))
        if (!locked) {
            Box {
                IconButton(onClick = { menu = true }) {
                    Icon(Icons.Filled.MoreVert, contentDescription = t("ms.options_for", vars = mapOf("name" to player.name)))
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text(t("sc.captain")) }, onClick = { menu = false; onCaptain() })
                    DropdownMenuItem(text = { Text(t("sc.wicketkeeper")) }, onClick = { menu = false; onKeeper() })
                    if (!isFirst) DropdownMenuItem(text = { Text(t("ms.move_up")) }, onClick = { menu = false; onMove(true) })
                    if (!isLast) DropdownMenuItem(text = { Text(t("ms.move_down")) }, onClick = { menu = false; onMove(false) })
                    DropdownMenuItem(text = { Text(t("sr.remove")) }, onClick = { menu = false; onRemove() })
                }
            }
        }
    }
}

@Composable
private fun Badge(text: String) {
    Text(text, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold,
        color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(horizontal = 4.dp))
}

/** Someone to pick: tap the row. */
@Composable
private fun PoolRow(player: MatchPlayer, isCaptain: Boolean, onAdd: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClick = onAdd),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(player.name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        if (isCaptain) Badge("C")
        Icon(Icons.Filled.AddCircleOutline, contentDescription = t("sc.add"), tint = MaterialTheme.colorScheme.primary)
    }
}

@Composable
private fun AddByName(onAdd: (String) -> Unit) {
    var name by rememberSaveable { mutableStateOf("") }
    val add = { if (name.isNotBlank()) { onAdd(name); name = "" } }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            label = { Text(t("cl.name")) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { add() }),
            modifier = Modifier.weight(1f),
        )
        Button(onClick = add, enabled = name.isNotBlank(), modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.add")) }
    }
}

/** Who is standing and who keeps the book. A member named here may score. */
@Composable
private fun OfficialsEditor(state: MatchSetupState, model: MatchSetupViewModel) {
    val brand = stringResource(R.string.brand_name)
    var umpire by rememberSaveable { mutableStateOf(true) }

    SectionTitle(t("sc.umpires"))
    if (state.umpires.isEmpty()) Footnote(t("sc.nobody_standing_yet"))
    state.umpires.forEach { OfficialRow(it) { model.removeOfficial(it.id) } }
    Footnote(t("sc.umpire_member_can_score", vars = mapOf("brand" to brand)))

    SectionTitle(t("ms.scorers"))
    if (state.scorers.isEmpty()) Footnote(t("sc.only_who_started_the_match"))
    state.scorers.forEach { OfficialRow(it) { model.removeOfficial(it.id) } }

    SectionTitle(t("sc.add"))
    Choices(listOf(true, false), umpire, { if (it) t("sc.umpire_one") else t("la.scorer") }, { umpire = it })
    AddByName { model.addOfficialGuest(umpire, it) }
    val taken = (state.umpires + state.scorers).map { it.id }.toSet()
    state.clubPlayers.filter { it.id !in taken }.forEach { player ->
        PoolRow(player, isCaptain = false) { model.addOfficial(umpire, player) }
    }
}

@Composable
private fun OfficialRow(player: MatchPlayer, onRemove: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(player.name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        TextButton(onClick = onRemove, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sr.remove")) }
    }
}

// MARK: Step 5 — the openers

@Composable
private fun OpenersStep(state: MatchSetupState, model: MatchSetupViewModel) {
    val batting = state.battingFirst
    val bat = state.book.players(batting)
    val bowl = state.book.players(batting.opposite)
    fun nameOf(id: String) = (bat + bowl).firstOrNull { it.id == id }?.name ?: "—"

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(t("sc.team_opening_pair", vars = mapOf("team" to state.book.name(batting))),
                style = MaterialTheme.typography.titleMedium)
            Picker(t("sc.striker_pick"), bat.map { it.id }, state.strikerId, ::nameOf, model::setStriker)
            Picker(t("sc.non_striker_pick"), bat.map { it.id }, state.nonStrikerId, ::nameOf, model::setNonStriker)
        }
    }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(t("sc.opening_bowler"), style = MaterialTheme.typography.titleMedium)
            Picker(t("sc.bowler_pick"), bowl.map { it.id }, state.bowlerId, ::nameOf, model::setBowler)
        }
    }
    ErrorLine(state.error)
    BigButton(t("sc.start_innings"), onClick = model::startInnings, busy = state.isBusy)
}
