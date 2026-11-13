@file:OptIn(ExperimentalMaterial3Api::class)

package com.fishers.app.views.match.scoring

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fishers.app.cricket.Dismissals
import com.fishers.app.cricket.Events
import com.fishers.app.cricket.LiveScorerViewModel
import com.fishers.app.cricket.MatchView
import com.fishers.app.cricket.ScorerState
import com.fishers.app.i18n.t

/** Whichever sheet is open, over the scorer. Each closes only on something the engine took. */
@Composable
internal fun ScorerSheets(
    sheet: ScorerSheet?,
    state: ScorerState,
    view: MatchView,
    model: LiveScorerViewModel,
    onClose: () -> Unit,
) {
    sheet ?: return
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onClose, sheetState = sheetState) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            when (sheet) {
                ScorerSheet.Extras -> ExtrasSheet(model, onClose)
                ScorerSheet.Wicket -> WicketSheet(view, model, onClose)
                ScorerSheet.Bowler -> BowlerSheet(view, model, onClose)
                ScorerSheet.Innings -> InningsSheet(view, model, onClose)
                ScorerSheet.EndInnings -> EndInningsSheet(view, model, onClose)
                ScorerSheet.Award -> AwardSheet(view, model, onClose)
                ScorerSheet.Handover -> HandoverSheet(state, model, onClose)
                ScorerSheet.CallOff -> CallOffSheet(state, model, onClose)
            }
        }
    }
}

@Composable
private fun Title(text: String) {
    Text(text, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
}

@Composable
private fun Hint(text: String, colour: Color = MaterialTheme.colorScheme.onSurfaceVariant) {
    Text(text, style = MaterialTheme.typography.bodyMedium, color = colour)
}

/**
 * The button that does it — greyed out, with the engine's reason against it
 * above, when the engine would refuse. A blank reason greys it out silently.
 */
@Composable
private fun Commit(label: String, refusal: String?, danger: Boolean = false, onClick: () -> Unit) {
    refusal?.takeIf { it.isNotBlank() }?.let { Hint(it, MaterialTheme.colorScheme.error) }
    Button(
        onClick = onClick,
        enabled = refusal == null,
        colors = if (danger) {
            ButtonDefaults.buttonColors(containerColor = BallColours.wicket, contentColor = Color.White)
        } else {
            ButtonDefaults.buttonColors()
        },
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
    ) { Text(label, style = MaterialTheme.typography.titleMedium) }
}

// ---- extras ----

/**
 * A wide they ran one off is two; a no ball hit for four is five and four of
 * them are the batter's. The sheet says which, rather than leave the scorer
 * to do the arithmetic.
 */
@Composable
private fun ExtrasSheet(model: LiveScorerViewModel, onClose: () -> Unit) {
    var kind by remember { mutableStateOf("wide") }
    var runs by remember { mutableIntStateOf(0) }
    var boundary by remember { mutableStateOf(false) }
    var offTheBat by remember { mutableStateOf(true) }

    Title(t("la.extras"))
    WordChoice(
        options = listOf(
            "wide" to t("extra.wide"),
            "no_ball" to t("extra.no_ball"),
            "bye" to t("extra.bye"),
            "leg_bye" to t("extra.leg_bye"),
            "penalty" to t("extra.penalty"),
        ),
        selected = kind,
        onSelect = {
            kind = it
            runs = when (it) {
                "penalty" -> 5
                "bye", "leg_bye" -> 1
                else -> 0
            }
            boundary = false
            offTheBat = true
        },
    )
    val ranOff = kind == "bye" || kind == "leg_bye"
    if (kind != "penalty") {
        Stepper(
            label = if (ranOff) t("sc.runs_run") else t("sc.runs_on_top"),
            value = runs,
            range = if (ranOff) 1..6 else 0..6,
            onChange = {
                runs = it
                if (it < 4) boundary = false
            },
        )
        if (runs >= 4) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(t("sc.went_to_the_boundary"), modifier = Modifier.weight(1f))
                Switch(checked = boundary, onCheckedChange = { boundary = it })
            }
        }
        if (kind == "no_ball" && runs > 0) {
            SectionLabel(t("sc.those_runs_came"))
            WordChoice(listOf(true to t("sc.off_the_bat"), false to t("sc.as_byes")), offTheBat) { offTheBat = it }
        }
    }
    Hint(
        when {
            kind == "wide" && runs == 0 -> t("sc.one_run_for_the_wide")
            kind == "wide" -> t("sc.wide_plus_runs", vars = mapOf("n" to runs, "total" to runs + 1))
            kind == "no_ball" && runs == 0 -> t("sc.one_run_for_the_no_ball")
            kind == "no_ball" && offTheBat -> t("sc.no_ball_plus_bat", vars = mapOf("n" to runs))
            kind == "no_ball" -> t("sc.no_ball_plus_byes", vars = mapOf("n" to runs))
            kind == "penalty" -> t("sc.five_penalty_runs_sentence")
            else -> t("sc.a_legal_ball_nothing_against")
        },
    )
    val total = (if (kind == "wide" || kind == "no_ball") 1 else 0) + runs
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(t("sc.total_to_the_side"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        Text("$total", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
    }
    val refusal = remember(kind, runs, boundary, offTheBat) {
        model.check(Events.extra(kind, runs, boundary && runs >= 4, kind == "no_ball" && offTheBat))
    }
    Commit(t("sc.add"), refusal) {
        if (model.extra(kind, runs, boundary && runs >= 4, offTheBat = kind == "no_ball" && offTheBat)) onClose()
    }
}

// ---- wicket ----

/** Who is out, how, who did it, and who is coming in. */
@Composable
private fun WicketSheet(view: MatchView, model: LiveScorerViewModel, onClose: () -> Unit) {
    val inn = view.current ?: return
    val freeHit = inn.freeHit
    val kinds = Dismissals.all.filter { !freeHit || Dismissals.allowedOnAFreeHit(it) }
    val incoming = remember(inn) { nextIn(view, inn) }
    val back = remember(inn) { resuming(view, inn) }
    val fielders = remember(view) { view.players(inn.bowling) }

    var kind by remember { mutableStateOf(kinds.first()) }
    var outIsStriker by remember { mutableStateOf(true) }
    var fielder by remember { mutableStateOf<String?>(null) }
    var newBatter by remember { mutableStateOf((incoming + back).firstOrNull()?.id) }
    var completed by remember { mutableIntStateOf(0) }
    var onExtra by remember { mutableStateOf(false) }

    Title(t("sc.wicket"))
    if (freeHit) Hint(t("sc.free_hit_sentence"), BallColours.extra)

    SectionLabel(t("sc.how_label"))
    WordChoice(kinds.map { it to dismissalLabel(it) }, kind) {
        kind = it
        if (!Dismissals.canDismissNonStriker(it)) outIsStriker = true
        if (!Dismissals.allowsCompletedRuns(it)) completed = 0
        if (!Dismissals.needsFielder(it)) fielder = null
        if (!Dismissals.canFollowAnExtra(it)) onExtra = false
    }

    if (Dismissals.canFollowAnExtra(kind)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(t("sc.off_a_wide_or_no_ball"), modifier = Modifier.weight(1f))
            Switch(checked = onExtra, onCheckedChange = { onExtra = it })
        }
        if (onExtra) Hint(t("sc.already_in_the_book_as_extra"))
    }

    if (Dismissals.canDismissNonStriker(kind)) {
        SectionLabel(t("sc.who_is_out"))
        WordChoice(
            listOf(true to view.name(inn.strikerId), false to view.name(inn.nonStrikerId)),
            outIsStriker,
        ) { outIsStriker = it }
    }

    if (Dismissals.allowsCompletedRuns(kind)) {
        Stepper(t("sc.runs_completed_first"), completed, 0..4) { completed = it }
        Hint(t("sc.runs_finished_before_throw"))
    }

    if (Dismissals.needsFielder(kind)) {
        SectionLabel(
            when (kind) {
                "caught" -> t("sc.caught_by")
                "stumped" -> t("sc.stumped_by")
                else -> t("sc.fielder")
            },
        )
        PlayerChoice(fielders, fielder, onSelect = { fielder = if (fielder == it) null else it })
    }

    SectionLabel(t("sc.new_batter"))
    if (incoming.isEmpty() && back.isEmpty()) {
        Hint(t("sc.that_is_all_out"))
    } else {
        PlayerChoice(
            incoming + back,
            newBatter,
            onSelect = { newBatter = it },
            notes = back.associate { it.id to t("sc.back_from_retired_hurt") },
        )
        if (back.isNotEmpty()) Hint(t("sc.retired_hurt_can_return"))
    }

    val outId = if (outIsStriker) inn.strikerId else inn.nonStrikerId
    val event = outId?.let {
        Events.wicket(
            batterId = it,
            kind = kind,
            fielderId = fielder.takeIf { Dismissals.needsFielder(kind) },
            newBatterId = newBatter,
            runs = completed,
            onExtra = onExtra,
        )
    }
    val refusal = remember(event) { if (event == null) t("sc.no_striker") else model.check(event) }
    Commit(t("sc.out"), refusal, danger = true) {
        if (outId != null && model.wicket(
                outId, kind, fielder.takeIf { Dismissals.needsFielder(kind) }, newBatter, completed, onExtra,
            )
        ) {
            onClose()
        }
    }
}

internal fun dismissalLabel(kind: String) = when (kind) {
    "bowled" -> t("sc.bowled_out")
    "caught" -> t("sc.caught")
    "lbw" -> t("sc.lbw")
    "run_out" -> t("sc.run_out_label")
    "stumped" -> t("sc.stumped")
    "hit_wicket" -> t("sc.hit_wicket")
    "retired" -> t("sc.retired_out")
    "retired_hurt" -> t("sc.retired_hurt")
    "obstructing_the_field" -> t("sc.obstructing_the_field")
    "hit_the_ball_twice" -> t("sc.hit_the_ball_twice")
    "timed_out" -> t("rest.timed_out")
    else -> t("shot.other")
}

// ---- bowler ----

/**
 * Everybody in the field, and whether the engine would let them bowl now —
 * with its reason against each who may not. Nobody bowls two in a row, and
 * nobody past the allocation the captains agreed.
 */
@Composable
private fun BowlerSheet(view: MatchView, model: LiveScorerViewModel, onClose: () -> Unit) {
    val choices = remember(view) { model.bowlerChoices() }
    Title(t("sc.bowler"))
    val perBowler = view.conditions.oversPerBowler
    Hint(
        if (perBowler > 0) {
            t("sc.overs_each_no_two_in_row", count = perBowler, vars = mapOf("n" to perBowler))
        } else {
            t("sc.no_allocation_agreed")
        },
    )
    val (can, cannot) = choices.partition { it.refusal == null }
    SectionLabel(t("sc.can_bowl"))
    can.forEach { choice ->
        BowlerRow(choice.player.name, choice.figures, null, choice.isBowling) {
            if (model.changeBowler(choice.player.id)) onClose()
        }
    }
    if (cannot.isNotEmpty()) {
        SectionLabel(t("sc.cannot_bowl_this_over"))
        cannot.forEach { choice ->
            BowlerRow(choice.player.name, choice.figures, choice.refusal, choice.isBowling, onClick = null)
        }
    }
}

@Composable
private fun BowlerRow(name: String, figures: String?, refusal: String?, current: Boolean, onClick: (() -> Unit)?) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                name,
                style = MaterialTheme.typography.titleMedium,
                color = if (refusal == null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            refusal?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error) }
        }
        figures?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        if (current) {
            Spacer(Modifier.size(8.dp))
            Icon(Icons.Filled.Check, contentDescription = t("sc.bowling_now"), tint = MaterialTheme.colorScheme.primary)
        }
    }
    HorizontalDivider()
}

// ---- an innings starting ----

/** Openers and a bowler: the first innings, the second, or a super over. */
@Composable
private fun InningsSheet(view: MatchView, model: LiveScorerViewModel, onClose: () -> Unit) {
    val batting = (if (view.innings.isEmpty()) view.firstBatting else view.nextBatting) ?: return
    val batters = remember(view) { view.players(batting) }
    val bowlers = remember(view) { view.players(MatchView.opposite(batting)) }
    var striker by remember { mutableStateOf(batters.getOrNull(0)?.id) }
    var nonStriker by remember { mutableStateOf(batters.getOrNull(1)?.id) }
    var bowler by remember { mutableStateOf(bowlers.firstOrNull()?.id) }

    Title(if (view.nextIsSuperOver) t("la.super_over") else t("sc.team_opening_pair", vars = mapOf("team" to view.sideName(batting))))
    if (view.nextIsSuperOver) {
        Hint(t("sc.one_over_each"))
    } else if (view.innings.isNotEmpty() && view.target != null) {
        Text(
            t("sc.team_need_to_win", vars = mapOf("team" to view.sideName(batting), "runs" to view.target)),
            style = MaterialTheme.typography.titleMedium,
        )
    }

    SectionLabel(t("sc.striker_pick"))
    PlayerChoice(batters, striker, onSelect = { striker = it }, notes = nonStriker?.let { mapOf(it to t("sc.other_end")) }.orEmpty())
    OutlinedButton(
        onClick = { val s = striker; striker = nonStriker; nonStriker = s },
        enabled = striker != null && nonStriker != null,
        modifier = Modifier.heightIn(min = 48.dp),
    ) {
        Icon(Icons.Filled.SwapVert, contentDescription = null)
        Spacer(Modifier.size(6.dp))
        Text(t("sc.swap_the_batters_over"))
    }
    SectionLabel(t("sc.non_striker_pick"))
    PlayerChoice(batters, nonStriker, onSelect = { nonStriker = it }, notes = striker?.let { mapOf(it to t("sc.on_strike_lower")) }.orEmpty())
    SectionLabel(t("sc.opening_bowler"))
    PlayerChoice(bowlers, bowler, onSelect = { bowler = it })

    val s = striker
    val ns = nonStriker
    val b = bowler
    val refusal = remember(s, ns, b) {
        if (s == null || ns == null || b == null) {
            t("sc.pick_two_batters_and_bowler")
        } else {
            model.check(Events.inningsStarted(view.innings.size, batting, s, ns, b, view.nextIsSuperOver))
        }
    }
    Commit(t("sc.start"), refusal) {
        if (s != null && ns != null && b != null && model.startInnings(s, ns, b)) onClose()
    }
}

// ---- ending an innings early ----

@Composable
private fun EndInningsSheet(view: MatchView, model: LiveScorerViewModel, onClose: () -> Unit) {
    Title(t("sc.end_the_innings_here"))
    Hint(t("sc.declarations_and_rain"))
    Button(
        onClick = { if (model.endInnings()) onClose() },
        colors = ButtonDefaults.buttonColors(containerColor = BallColours.wicket, contentColor = Color.White),
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
    ) { Text(t("sc.end_innings")) }
    // Only a declaration game has these, and only there do they mean anything.
    if (view.conditions.twoInnings) {
        OutlinedButton(onClick = { if (model.endInnings(declared = true)) onClose() }, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
            Text(t("sc.declare"))
        }
        OutlinedButton(onClick = { if (model.endInnings(forfeited = true)) onClose() }, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
            Text(t("sc.forfeit_the_innings"))
        }
        OutlinedButton(onClick = { if (model.drawn()) onClose() }, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
            Text(t("sc.match_drawn"))
        }
    }
    TextButton(onClick = onClose, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text(t("sc.keep_scoring")) }
}

// ---- the award ----

@Composable
private fun AwardSheet(view: MatchView, model: LiveScorerViewModel, onClose: () -> Unit) {
    Title(t("sc.player_of_the_match"))
    listOf("home", "away").forEach { side ->
        SectionLabel(view.sideName(side))
        view.players(side).forEach { player ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 52.dp)
                    .clickable { if (model.award(player.id)) onClose() },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(player.name, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                if (view.playerOfTheMatch == player.id) {
                    Icon(Icons.Filled.Check, contentDescription = t("sc.player_of_the_match"), tint = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}

// ---- handing the book over ----

/**
 * While one person is scoring, nobody else can alter the match. That changes
 * when they pass it on — and everything scored so far goes up first.
 */
@Composable
private fun HandoverSheet(state: ScorerState, model: LiveScorerViewModel, onClose: () -> Unit) {
    LaunchedEffect(Unit) { model.loadCandidates() }
    var chosen by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(state.handedOver) { if (state.handedOver) onClose() }

    Title(t("sc.the_book"))
    Hint(t("sc.you_hold_the_book"))
    SectionLabel(t("sc.hand_over_to"))
    if (state.candidates.isEmpty()) {
        Hint(t("sc.nobody_else_named_yet"))
    }
    state.candidates.groupBy { it.group }.forEach { (group, people) ->
        Text(group, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        PlayerChoice(
            people.map { com.fishers.app.cricket.Player(it.userId, it.name) },
            chosen,
            onSelect = { chosen = it },
        )
    }
    Hint(t("sc.anyone_playing_can_take_it"))
    Commit(t("la.hand_it_over"), if (chosen == null || state.isWorking) "" else null) {
        chosen?.let(model::handOver)
    }
}

// ---- calling it off ----

/** Rain, bad light, ground unfit. The card survives and the match is no result. */
@Composable
private fun CallOffSheet(state: ScorerState, model: LiveScorerViewModel, onClose: () -> Unit) {
    var reason by remember { mutableStateOf("") }
    Title(t("ld.call_it_off"))
    OutlinedTextField(
        value = reason,
        onValueChange = { reason = it },
        label = { Text(t("ev.why")) },
        placeholder = { Text(t("sc.rain_bad_light_ground_unfit")) },
        modifier = Modifier.fillMaxWidth(),
    )
    Hint(t("sc.no_result_explainer"))
    Commit(t("la.abandon_no_result"), if (state.isWorking) "" else null, danger = true) {
        model.abandon(reason)
        onClose()
    }
    TextButton(onClick = onClose, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text(t("sc.keep_playing")) }
}
