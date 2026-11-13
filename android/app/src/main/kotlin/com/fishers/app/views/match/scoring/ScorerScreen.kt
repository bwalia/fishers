@file:OptIn(ExperimentalMaterial3Api::class)

package com.fishers.app.views.match.scoring

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.fishers.app.cricket.Commentary
import com.fishers.app.cricket.DeviceId
import com.fishers.app.cricket.FileBallStore
import com.fishers.app.cricket.InningsView
import com.fishers.app.cricket.LiveScorerViewModel
import com.fishers.app.cricket.MatchView
import com.fishers.app.cricket.ScorerState
import com.fishers.app.cricket.ShareLink
import com.fishers.app.cricket.SyncStatus
import com.fishers.app.cricket.WheelMode
import com.fishers.app.cricket.rate
import com.fishers.app.i18n.t
import com.fishers.app.net.ScoringApi
import com.fishers.app.views.match.MatchSetupRoute
import com.fishers.app.views.match.ScorecardRoute
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator

/** The sheets the scorer opens over the buttons. */
internal enum class ScorerSheet { Extras, Wicket, Bowler, Innings, EndInnings, Award, Handover, CallOff }

/**
 * Ball-by-ball scoring. `LiveScorerView.swift`.
 *
 * Built to be used standing at a ground, one-handed, in sunlight: the score
 * big enough to read at arm's length, the run buttons where a thumb lands and
 * never behind a scroll, and the screen kept on for as long as it is open.
 */
@Composable
internal fun ScoreMatchContent(eventId: String) {
    val deps = LocalAppDeps.current
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val model = remember(eventId) {
        LiveScorerViewModel(
            api = deps.service<ScoringApi>(),
            eventId = eventId,
            deviceId = DeviceId.get(context),
            store = FileBallStore.forApp(context),
            myUserId = deps.user()?.id,
        )
    }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(model) { model.load() }

    // Anything waiting goes up the moment the app is in front again, and is
    // tried again every few seconds while it waits — which is how "when the
    // network comes back" is noticed without asking for a permission.
    val lifecycle = LocalLifecycleOwner.current
    LaunchedEffect(model, lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { model.keepSending() }
    }

    KeepScreenOn()
    ShareWhenReady(state.share, onShown = model::shareShown)

    var wheel by remember { mutableStateOf(WheelSetting.read(context)) }
    ScorerScreen(
        state = state,
        model = model,
        wheel = wheel,
        onWheel = {
            wheel = it
            WheelSetting.write(context, it)
        },
        onBack = navigator::pop,
        onFollow = { navigator.replace(ScorecardRoute(eventId)) },
        onSetUp = { navigator.push(MatchSetupRoute(eventId)) },
    )
}

/** A scorer's screen must not go dark between balls. Only while it is open. */
@Composable
internal fun KeepScreenOn() {
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }
}

/** The system share sheet — WhatsApp, Mail, Messages — with the live link. */
@Composable
internal fun ShareWhenReady(link: ShareLink?, onShown: () -> Unit) {
    val context = LocalContext.current
    LaunchedEffect(link) {
        val ready = link ?: return@LaunchedEffect
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, ready.headline)
            putExtra(Intent.EXTRA_TEXT, "${ready.headline}\n${ready.url}")
        }
        context.startActivity(Intent.createChooser(send, t("sc.share_live_scoreboard")))
        onShown()
    }
}

@Composable
private fun ScorerScreen(
    state: ScorerState,
    model: LiveScorerViewModel,
    wheel: WheelMode,
    onWheel: (WheelMode) -> Unit,
    onBack: () -> Unit,
    onFollow: () -> Unit,
    onSetUp: () -> Unit,
) {
    var sheet by remember { mutableStateOf<ScorerSheet?>(null) }
    var fullCard by remember { mutableStateOf(false) }
    /** Runs waiting on "where did it go?" before they are written. */
    var placing by remember { mutableStateOf<Int?>(null) }
    val view = state.view
    val haptics = LocalHapticFeedback.current
    val score: (Int) -> Unit = { n ->
        if (wheel.asks(n)) {
            placing = n
        } else if (model.runs(n)) {
            haptics.performHapticFeedback(if (n >= 4) HapticFeedbackType.LongPress else HapticFeedbackType.TextHandleMove)
        }
    }

    // The over is done: ask who bowls next, once per over, rather than let
    // the next tap meet the engine's refusal.
    LaunchedEffect(state.needsNewBowler, view?.current?.legalBalls, view?.innings?.size) {
        if (state.needsNewBowler) sheet = ScorerSheet.Bowler
    }

    if (fullCard && view != null) {
        BackHandler { fullCard = false }
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(t("ld.scorecard")) },
                    navigationIcon = {
                        IconButton(onClick = { fullCard = false }) {
                            Icon(Icons.Filled.Close, contentDescription = t("sc.close"))
                        }
                    },
                )
            },
        ) { inner -> ScorecardContent(view, Modifier.padding(inner)) }
        return
    }

    Scaffold(
        topBar = {
            ScorerTopBar(
                title = view?.let { "${it.homeName} v ${it.awayName}" } ?: t("sc.loading_match"),
                state = state,
                wheel = wheel,
                onWheel = onWheel,
                onBack = onBack,
                onShare = model::share,
                onCard = { fullCard = true },
                onSheet = { sheet = it },
            )
        },
        bottomBar = { SyncBar(state) },
    ) { inner ->
        Box(Modifier.padding(inner).fillMaxSize()) {
            when {
                state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
                view == null -> Column(
                    Modifier.fillMaxSize().padding(24.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(state.error ?: t("sc.no_scorecard_loaded"), style = MaterialTheme.typography.bodyLarge)
                    Spacer(Modifier.size(12.dp))
                    OutlinedButton(onClick = model::load) { Text(t("sc.refresh")) }
                }
                else -> Column(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
                    Column(
                        Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        ScoreHeader(view)
                        Messages(state, model, onFollow)
                        Phase(state, view, onSheet = { sheet = it }, onCard = { fullCard = true }, onBack = onBack, onSetUp = onSetUp)
                        RecentBalls(view)
                    }
                    if (state.canScore && view.current != null && !view.isFinished && !view.isInningsBreak) {
                        Controls(state, model, onScore = score, onSheet = { sheet = it })
                    }
                }
            }
            MomentBanner(state.moment, state.momentCount, Modifier.align(Alignment.TopCenter))
        }
    }

    if (view != null) {
        ScorerSheets(sheet, state, view, model, onClose = { sheet = null })
    }

    val runs = placing
    val striker = view?.current?.strikerId
    if (runs != null && view != null && striker != null) {
        WheelPicker(
            batterName = view.name(striker),
            batsLeft = view.batsLeft(striker),
            runs = runs,
            onSave = { shot ->
                placing = null
                if (model.runs(runs, shot)) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            },
            onSkip = {
                placing = null
                if (model.runs(runs)) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            },
            onCancel = { placing = null },
        )
    }
}

@Composable
private fun ScorerTopBar(
    title: String,
    state: ScorerState,
    wheel: WheelMode,
    onWheel: (WheelMode) -> Unit,
    onBack: () -> Unit,
    onShare: (Boolean) -> Unit,
    onCard: () -> Unit,
    onSheet: (ScorerSheet) -> Unit,
) {
    var shareMenu by remember { mutableStateOf(false) }
    var more by remember { mutableStateOf(false) }
    val view = state.view
    TopAppBar(
        title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = t("sc.back"))
            }
        },
        actions = {
            Box {
                IconButton(onClick = { shareMenu = true }, enabled = !state.isWorking && view != null) {
                    Icon(Icons.Filled.Share, contentDescription = t("sc.share_live_scoreboard"))
                }
                DropdownMenu(expanded = shareMenu, onDismissRequest = { shareMenu = false }) {
                    DropdownMenuItem(
                        text = { Text(t("sc.share_via_whatsapp_mail")) },
                        onClick = { shareMenu = false; onShare(false) },
                    )
                    DropdownMenuItem(
                        text = { Text(t("sc.share_and_post_to_club_chat")) },
                        onClick = { shareMenu = false; onShare(true) },
                    )
                }
            }
            Box {
                IconButton(onClick = { more = true }) {
                    Icon(Icons.Filled.MoreVert, contentDescription = t("sc.match_options"))
                }
                DropdownMenu(expanded = more, onDismissRequest = { more = false }) {
                    DropdownMenuItem(text = { Text(t("ev.full_scorecard")) }, onClick = { more = false; onCard() })
                    HorizontalDivider()
                    Text(
                        t("sr.wagon_wheel").uppercase(),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                    )
                    WheelMode.entries.forEach { mode ->
                        DropdownMenuItem(
                            text = { Text(mode.label) },
                            leadingIcon = {
                                if (mode == wheel) Icon(Icons.Filled.Check, contentDescription = null)
                            },
                            onClick = { more = false; onWheel(mode) },
                        )
                    }
                    HorizontalDivider()
                    if (state.isLive) {
                        DropdownMenuItem(
                            text = { Text(t("sc.change_bowler")) },
                            onClick = { more = false; onSheet(ScorerSheet.Bowler) },
                        )
                        DropdownMenuItem(
                            text = { Text(t("sc.end_innings")) },
                            onClick = { more = false; onSheet(ScorerSheet.EndInnings) },
                        )
                    }
                    if (state.canScore) {
                        DropdownMenuItem(
                            text = { Text(t("sc.hand_the_book_over")) },
                            onClick = { more = false; onSheet(ScorerSheet.Handover) },
                        )
                    }
                    if (state.canScore && view != null && view.innings.isNotEmpty() && !view.isFinished) {
                        DropdownMenuItem(
                            text = { Text(t("la.call_this_match_off"), color = MaterialTheme.colorScheme.error) },
                            onClick = { more = false; onSheet(ScorerSheet.CallOff) },
                        )
                    }
                }
            }
        },
    )
}

// ---- the score ----

@Composable
private fun ScoreHeader(view: MatchView) {
    val inn = view.current
    if (inn == null) {
        Text(
            "${view.homeName} v ${view.awayName}",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
        )
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            view.sideName(inn.batting),
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            verticalAlignment = Alignment.Bottom,
            modifier = Modifier.semantics {
                contentDescription = t("sc.innings_score_aria", vars = mapOf("innings" to view.sideName(inn.batting), "score" to "${inn.score} (${inn.overs})"))
            },
        ) {
            Text(inn.score, fontSize = 56.sp, fontWeight = FontWeight.Black, lineHeight = 56.sp)
            Spacer(Modifier.width(10.dp))
            Text(
                "(${inn.overs}${if (inn.oversAvailable > 0) "/${inn.oversAvailable}" else ""})",
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.padding(bottom = 6.dp),
            )
        }
        val rates = buildString {
            append(t("sc.crr", vars = mapOf("rate" to rate(inn.runRate))))
            view.requiredRunRate?.let { append(t("sc.rrr", vars = mapOf("rate" to rate(it)))) }
            append(" · ")
            append(t("sc.partnership_short", vars = mapOf("runs" to inn.partnershipRuns, "balls" to inn.partnershipBalls)))
        }
        Text(rates, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        view.chaseLine?.let {
            Text(it, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
        }

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            BatterCell(view, inn, inn.strikerId, onStrike = true, Modifier.weight(1f))
            BatterCell(view, inn, inn.nonStrikerId, onStrike = false, Modifier.weight(1f))
        }
        inn.bowlerId?.let { id ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    t("sc.bowler").uppercase(),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.width(76.dp),
                )
                Text(view.name(id), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                Text(inn.bowler(id)?.figures ?: "0.0-0-0-0", style = MaterialTheme.typography.titleMedium)
            }
        }

        OverStrip(inn)

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (inn.freeHit && !inn.complete) Banner(t("sc.free_hit_banner"), BallColours.extra)
            if (inn.superOver) {
                Banner(t("sc.super_over_n", vars = mapOf("n" to view.superOvers)), BallColours.wicket)
            } else if (inn.inPowerplay && !inn.complete) {
                Banner(
                    t("sc.powerplay_n_overs_banner", count = inn.powerplayOversLeft, vars = mapOf("n" to inn.powerplayOversLeft)),
                    MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

@Composable
private fun BatterCell(view: MatchView, inn: InningsView, id: String?, onStrike: Boolean, modifier: Modifier) {
    val batter = inn.batter(id)
    Column(
        modifier
            .background(
                if (onStrike) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh,
                RoundedCornerShape(12.dp),
            )
            .padding(10.dp),
    ) {
        Text(
            if (onStrike) t("sc.striker_caps") else t("sc.non_striker_caps"),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            if (id == null) "—" else view.name(id) + if (onStrike) " *" else "",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = if (onStrike) FontWeight.Bold else FontWeight.Normal,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (batter != null) {
            Text("${batter.runs} (${batter.balls})", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun OverStrip(inn: InningsView) {
    val current = inn.thisOver
    val showingLast = current.isEmpty() && inn.lastOver.isNotEmpty()
    val balls = if (showingLast) inn.lastOver else current
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            (if (showingLast) t("sc.last_over") else t("rest.this_over")).uppercase(),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(76.dp),
        )
        if (balls.isEmpty()) {
            Text("—", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        balls.forEach { BallChip(it, dim = showingLast) }
    }
}

/** The last three balls in words — what a scorer glances at to check the book. */
@Composable
private fun RecentBalls(view: MatchView) {
    val inn = view.current ?: return
    if (inn.deliveries.isEmpty()) return
    val lines = remember(inn) { Commentary.lines(view, inn, limit = 3) }
    Surface(color = MaterialTheme.colorScheme.surfaceContainerLow, shape = RoundedCornerShape(12.dp)) {
        Column(Modifier.fillMaxWidth().padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            lines.forEach { line ->
                Row {
                    Text(line.marker, style = MaterialTheme.typography.labelMedium, modifier = Modifier.width(40.dp))
                    Text(
                        line.text,
                        style = MaterialTheme.typography.bodySmall,
                        color = if (line.isWicket) BallColours.wicket else MaterialTheme.colorScheme.onSurface,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

// ---- what is going on, and what to do about it ----

@Composable
private fun Messages(state: ScorerState, model: LiveScorerViewModel, onFollow: () -> Unit) {
    state.error?.let { Note(it, MaterialTheme.colorScheme.error, onDismiss = model::dismissError) }
    state.notice?.let { Note(it, MaterialTheme.colorScheme.primary, onDismiss = model::dismissNotice) }
    when {
        state.handedOver -> Panel {
            Text(t("sc.handed_the_book_over"), style = MaterialTheme.typography.bodyLarge)
            OutlinedButton(onClick = onFollow) { Text(t("sc.open_live_scoreboard")) }
        }
        state.bookElsewhere -> Panel {
            Text(t("sc.someone_else_is_scoring_this_match_onl"), style = MaterialTheme.typography.bodyLarge)
            Button(onClick = model::takeOver, enabled = !state.isWorking, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(t("sc.take_it_over_captain_or_secretary_only"))
            }
            OutlinedButton(onClick = onFollow) { Text(t("sc.open_live_scoreboard")) }
        }
        state.match != null && !state.match.canScore -> Panel {
            Text(t("sc.need_scoring_permission"), style = MaterialTheme.typography.bodyLarge)
            OutlinedButton(onClick = onFollow) { Text(t("sc.open_live_scoreboard")) }
        }
    }
}

@Composable
private fun Phase(
    state: ScorerState,
    view: MatchView,
    onSheet: (ScorerSheet) -> Unit,
    onCard: () -> Unit,
    onBack: () -> Unit,
    onSetUp: () -> Unit,
) {
    if (!state.canScore && !view.isFinished) return
    when {
        view.needsASuperOver -> Panel {
            Text(t("sc.scores_level_super_over"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            BigButton(t("la.start_the_super_over")) { onSheet(ScorerSheet.Innings) }
            ResultActions(state, view, onSheet, onCard, onBack)
        }
        view.isFinished -> Panel {
            Text(
                view.margin ?: t("sc.match_complete"),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
            )
            view.playerOfTheMatch?.let {
                Text(t("sc.player_of_the_match_is", vars = mapOf("name" to view.name(it))), fontWeight = FontWeight.SemiBold)
            }
            ResultActions(state, view, onSheet, onCard, onBack)
        }
        view.isInningsBreak -> Panel {
            Text(t("sc.innings_break"), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            val next = view.nextBatting
            if (view.nextIsSuperOver) {
                Text(t("sc.one_over_each"))
            } else if (view.target != null && next != null) {
                Text(
                    t("sc.team_need_to_win", vars = mapOf("team" to view.sideName(next), "runs" to view.target)),
                    style = MaterialTheme.typography.titleMedium,
                )
            }
            if (state.match?.opponentClubId != null) {
                Text(t("sc.the_side_batting_normally_keeps_their"), style = MaterialTheme.typography.bodySmall)
                OutlinedButton(onClick = { onSheet(ScorerSheet.Handover) }) { Text(t("sc.hand_the_book_over")) }
            }
            BigButton(
                when {
                    view.nextIsSuperOver -> t("la.start_the_reply")
                    view.innings.size == 1 -> t("sc.start_second_innings")
                    else -> t("sc.start_innings")
                },
            ) { onSheet(ScorerSheet.Innings) }
        }
        view.isReadyToStart -> Panel {
            Text(
                t("sc.team_bat_first_dot", vars = mapOf("team" to view.sideName(view.firstBatting))),
                style = MaterialTheme.typography.titleMedium,
            )
            BigButton(t("la.start_the_innings")) { onSheet(ScorerSheet.Innings) }
        }
        view.innings.isEmpty() -> Panel {
            Text(t("sc.not_set_up_yet"), style = MaterialTheme.typography.bodyLarge)
            BigButton(t("sc.match_setup"), onClick = onSetUp)
        }
    }
}

@Composable
private fun ResultActions(
    state: ScorerState,
    view: MatchView,
    onSheet: (ScorerSheet) -> Unit,
    onCard: () -> Unit,
    onBack: () -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (state.canScore && !view.abandoned) {
            OutlinedButton(onClick = { onSheet(ScorerSheet.Award) }, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(if (view.playerOfTheMatch == null) t("sh.award") else t("sc.change_award"))
            }
        }
        OutlinedButton(onClick = onCard, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("ld.scorecard")) }
        Button(onClick = onBack, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("ev.done")) }
    }
}

@Composable
private fun Panel(content: @Composable () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { content() }
    }
}

@Composable
private fun Note(text: String, colour: Color, onDismiss: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().background(colour.copy(alpha = 0.1f), RoundedCornerShape(10.dp)).padding(start = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text, color = colour, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f).padding(vertical = 10.dp))
        IconButton(onClick = onDismiss) { Icon(Icons.Filled.Close, contentDescription = t("sc.close"), tint = colour) }
    }
}

@Composable
internal fun BigButton(text: String, enabled: Boolean = true, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
        Text(text, style = MaterialTheme.typography.titleMedium)
    }
}

// ---- the buttons ----

@Composable
private fun Controls(
    state: ScorerState,
    model: LiveScorerViewModel,
    onScore: (Int) -> Unit,
    onSheet: (ScorerSheet) -> Unit,
) {
    val enabled = state.isLive && !state.needsNewBowler
    val inn = state.view?.current
    Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (state.needsNewBowler && inn != null) {
            val last = inn.lastOverBowler?.let { state.view.name(it) } ?: t("sc.that_bowler")
            Surface(
                onClick = { onSheet(ScorerSheet.Bowler) },
                color = BallColours.extra.copy(alpha = 0.16f),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(Modifier.padding(12.dp)) {
                    Text(
                        t("sc.over_n_done_who_next", vars = mapOf("n" to inn.legalBalls / 6)),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(t("sc.bowled_it_nobody_two_in_row", vars = mapOf("name" to last)), style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(0, 1, 2, 3).forEach { RunButton(it, enabled, Modifier.weight(1f), onScore) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(4, 5, 6).forEach { RunButton(it, enabled, Modifier.weight(1f), onScore) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(
                onClick = { onSheet(ScorerSheet.Extras) },
                enabled = enabled,
                modifier = Modifier.weight(1f).heightIn(min = 56.dp),
            ) { Text(t("la.extras"), style = MaterialTheme.typography.titleMedium) }
            Button(
                onClick = { onSheet(ScorerSheet.Wicket) },
                enabled = enabled,
                colors = ButtonDefaults.buttonColors(containerColor = BallColours.wicket, contentColor = Color.White),
                modifier = Modifier.weight(1f).heightIn(min = 56.dp),
            ) { Text(t("sc.wicket"), style = MaterialTheme.typography.titleMedium) }
            OutlinedButton(
                onClick = { model.undo() },
                enabled = state.canUndo,
                modifier = Modifier.weight(1f).heightIn(min = 56.dp),
            ) {
                Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = null)
                Spacer(Modifier.width(4.dp))
                Text(t("sc.undo"), style = MaterialTheme.typography.titleMedium)
            }
        }
    }
}

@Composable
private fun RunButton(runs: Int, enabled: Boolean, modifier: Modifier, onScore: (Int) -> Unit) {
    val colours = when (runs) {
        4 -> ButtonDefaults.buttonColors(containerColor = BallColours.four, contentColor = Color.White)
        6 -> ButtonDefaults.buttonColors(containerColor = BallColours.six, contentColor = Color.White)
        else -> ButtonDefaults.buttonColors()
    }
    Button(
        onClick = { onScore(runs) },
        enabled = enabled,
        colors = colours,
        shape = RoundedCornerShape(14.dp),
        modifier = modifier.heightIn(min = 64.dp).semantics {
            contentDescription = t("la.over_runs", count = runs, vars = mapOf("n" to runs))
        },
    ) {
        Text("$runs", fontSize = 28.sp, fontWeight = FontWeight.Bold)
    }
}

// ---- whether it has gone up ----

@Composable
private fun SyncBar(state: ScorerState) {
    val (icon, colour) = when {
        state.sync == SyncStatus.Offline -> Icons.Filled.CloudOff to MaterialTheme.colorScheme.error
        state.sync == SyncStatus.Syncing || state.unsent > 0 -> Icons.Filled.Sync to BallColours.extra
        else -> Icons.Filled.CheckCircle to MaterialTheme.colorScheme.primary
    }
    val label = when {
        state.sync == SyncStatus.Offline && state.unsent > 0 ->
            t("sync.offline_balls", count = state.unsent, vars = mapOf("n" to state.unsent))
        state.sync == SyncStatus.Offline -> t("rest.offline_saved_on_this_phone")
        state.unsent > 0 -> t("sc.n_balls_waiting_to_send", count = state.unsent, vars = mapOf("n" to state.unsent))
        state.sync == SyncStatus.Syncing -> t("le.syncing")
        else -> t("sync.saved")
    }
    Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, contentDescription = null, tint = colour, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(label, style = MaterialTheme.typography.bodyMedium)
            }
            state.syncProblem?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

/** Kept for the scorer's own "who is coming in" lists: the side's players not out and not in. */
internal fun nextIn(view: MatchView, inn: InningsView) = view.players(inn.batting).filter { p ->
    val b = inn.batter(p.id)
    p.id != inn.strikerId && p.id != inn.nonStrikerId && b?.out != true && b?.retiredHurt != true
}

/** Batters who retired hurt and may come back. */
internal fun resuming(view: MatchView, inn: InningsView) = inn.batters
    .filter { it.canResume && it.playerId != inn.strikerId && it.playerId != inn.nonStrikerId }
    .map { com.fishers.app.cricket.Player(it.playerId, view.name(it.playerId)) }
