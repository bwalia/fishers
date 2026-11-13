package com.fishers.app.views.clubs

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.EventRepeat
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.SportsCricket
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.clubs.ClubFixture
import com.fishers.app.clubs.ClubPageState
import com.fishers.app.clubs.ClubPageViewModel
import com.fishers.app.clubs.RoleChoice
import com.fishers.app.clubs.SetupStep
import com.fishers.app.clubs.Team
import com.fishers.app.clubs.Venue
import com.fishers.app.clubs.sportLabel
import com.fishers.app.i18n.t
import com.fishers.app.net.ClubsApi
import com.fishers.app.views.fixtures.CreateFixtureRoute
import com.fishers.app.views.fixtures.FixtureRoute
import com.fishers.app.views.match.StartMatchRoute
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator

/**
 * One club — `ClubDetailView` in `ClubsTeamsView.swift`. What it is, the
 * buttons this person's role allows (start a match, schedule one, add a team
 * or a ground), and the way into the roster, the season and the fixtures.
 */
@Composable
internal fun ClubPage(clubId: String, name: String, welcome: Boolean) {
    val nav = LocalNavigator.current
    val deps = LocalAppDeps.current
    val context = LocalContext.current
    val model = remember(clubId) { ClubPageViewModel(deps.service<ClubsApi>(), clubId) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(clubId) { model.load() }

    val prefs = remember { clubPrefs(context) }
    var setupHidden by remember { mutableStateOf(prefs.getBoolean("setup-hidden:$clubId", false)) }
    // Shown once per club, straight after it is made — not again on the way
    // back from the roster, which draws this page afresh.
    var showWelcome by remember {
        mutableStateOf(welcome && !prefs.getBoolean("welcomed:$clubId", false))
    }
    var addingTeam by rememberSaveable { mutableStateOf(false) }
    var addingGround by rememberSaveable { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    // A save went through: the form that asked closes.
    LaunchedEffect(state.saved) {
        addingTeam = false
        addingGround = false
    }

    val title = state.club?.name ?: name
    val openRoster = { adding: Boolean -> nav.push(ManageClubRoute(clubId, title, startAdding = adding)) }
    val hideSetup = { hidden: Boolean ->
        setupHidden = hidden
        prefs.edit().putBoolean("setup-hidden:$clubId", hidden).apply()
    }

    ClubScreen(
        title = title,
        actions = {
            IconButton(onClick = { menuOpen = true }) {
                Icon(Icons.Filled.MoreVert, contentDescription = t("sc.more"))
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                DropdownMenuItem(
                    text = { Text(t("cl.manage_club")) },
                    onClick = { menuOpen = false; openRoster(false) },
                )
                if (setupHidden && state.setupLeft) {
                    DropdownMenuItem(
                        text = { Text(t("cl.show_club_setup")) },
                        onClick = { menuOpen = false; hideSetup(false) },
                    )
                }
            }
        },
    ) {
        if (state.isFirstLoad && state.isLoading) {
            Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            return@ClubScreen
        }
        ClubPageBody(
            state = state,
            myId = deps.user()?.id,
            setupShown = !setupHidden && state.setupLeft,
            onRetry = model::load,
            onStartMatch = { nav.push(StartMatchRoute(clubId)) },
            onSchedule = { nav.push(CreateFixtureRoute(clubId)) },
            onScheduleNets = { nav.push(CreateFixtureRoute(clubId, nets = true)) },
            onSeason = { nav.push(ClubSeasonRoute(clubId, title)) },
            onRoster = { openRoster(false) },
            onTeam = { nav.push(TeamRoute(it.id, it.name)) },
            onAddTeam = { addingTeam = true },
            onAddGround = { addingGround = true },
            onFixture = { nav.push(FixtureRoute(it.id)) },
            onStep = { step ->
                when (step) {
                    SetupStep.Kind.Players -> openRoster(true)
                    SetupStep.Kind.Captain -> openRoster(false)
                    SetupStep.Kind.Team -> addingTeam = true
                    SetupStep.Kind.Ground -> addingGround = true
                }
            },
            onHideSetup = { hideSetup(true) },
        )
    }

    if (showWelcome) {
        val done = {
            showWelcome = false
            prefs.edit().putBoolean("welcomed:$clubId", true).apply()
        }
        ClubWelcome(
            clubName = title,
            onAddPlayers = { done(); openRoster(true) },
            onLater = done,
        )
    }
    if (addingTeam) {
        AddTeamDialog(
            sports = state.sports,
            saving = state.isSaving,
            error = state.formError,
            onSave = model::addTeam,
            onDismiss = { addingTeam = false; model.clearFormError() },
        )
    }
    if (addingGround) {
        AddGroundDialog(
            saving = state.isSaving,
            error = state.formError,
            onSave = model::addGround,
            onDismiss = { addingGround = false; model.clearFormError() },
        )
    }
}

@Composable
private fun ClubPageBody(
    state: ClubPageState,
    myId: String?,
    setupShown: Boolean,
    onRetry: () -> Unit,
    onStartMatch: () -> Unit,
    onSchedule: () -> Unit,
    onScheduleNets: () -> Unit,
    onSeason: () -> Unit,
    onRoster: () -> Unit,
    onTeam: (Team) -> Unit,
    onAddTeam: () -> Unit,
    onAddGround: () -> Unit,
    onFixture: (ClubFixture) -> Unit,
    onStep: (SetupStep.Kind) -> Unit,
    onHideSetup: () -> Unit,
) {
    val context = LocalContext.current
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        item { Header(state, myId) }

        state.error?.let { error ->
            item {
                Column {
                    ErrorLine(error)
                    TextButton(onClick = onRetry) { Text(t("rest.try_again")) }
                }
            }
        }
        // Not a member, or no signal: nothing below would load either.
        if (state.club == null) return@LazyColumn

        if (state.canStartMatch) {
            item {
                Button(onClick = onStartMatch, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(top = 8.dp)) {
                    Icon(Icons.Filled.SportsCricket, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(t("cl.start_a_match"), modifier = Modifier.padding(start = 8.dp))
                }
                Hint(t("cl.name_the_opposition_and_start_scoring"), Modifier.padding(top = 4.dp))
            }
        }

        if (setupShown) {
            item { SetupCard(state, onStep, onHideSetup) }
        }

        if (state.club.playsCricket) {
            item {
                SectionHeading(t("cl.season_stats"))
                LinkRow(Icons.Filled.BarChart, t("ss.club_season"), onClick = onSeason)
            }
        }

        item {
            SectionHeading(t("cl.members"))
            val n = state.members.size
            LinkRow(
                Icons.Filled.Groups,
                t("cl.n_members", count = n, vars = mapOf("n" to n)),
                trailing = t("cl.manage_club"),
                onClick = onRoster,
            )
        }

        item { SectionHeading(t("cl.teams")) }
        if (state.teams.isEmpty()) {
            item { Hint(t("cl.no_teams_yet_explainer")) }
        }
        items(state.teams, key = { "team-${it.id}" }) { team ->
            LinkRow(
                Icons.Filled.Groups,
                team.name,
                trailing = team.sport?.let(::sportLabel),
                onClick = { onTeam(team) },
            )
        }
        if (state.runsClubOps) {
            item { AddButton(t("lb.add_a_team"), onAddTeam) }
        }

        item { SectionHeading(t("cl.grounds")) }
        if (state.venues.isEmpty()) {
            item { Hint(t("cl.no_grounds_yet_add_the_ones_you_play_a")) }
        }
        items(state.venues, key = { "venue-${it.id}" }) { venue -> GroundRow(venue) { openMap(context, venue) } }
        if (state.runsClubOps) {
            item { AddButton(t("cl.add_a_ground"), onAddGround) }
        }

        item { SectionHeading(t("ev.fixtures_and_nets")) }
        if (state.fixtures.isEmpty()) {
            item { Hint(t("ev.no_fixtures_yet")) }
        }
        items(state.fixtures, key = { "fixture-${it.id}" }) { fixture -> FixtureRow(fixture) { onFixture(fixture) } }
        if (state.managesEvents) {
            item {
                OutlinedButton(onClick = onSchedule, modifier = Modifier.padding(top = 8.dp).heightIn(min = 48.dp)) {
                    Icon(Icons.Filled.DateRange, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(t("ev.schedule_a_match"), modifier = Modifier.padding(start = 8.dp))
                }
            }
            item {
                OutlinedButton(onClick = onScheduleNets, modifier = Modifier.heightIn(min = 48.dp)) {
                    Icon(Icons.Filled.EventRepeat, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(t("np.schedule_nets_or_practice"), modifier = Modifier.padding(start = 8.dp))
                }
            }
        }
    }
}

@Composable
private fun Header(state: ClubPageState, myId: String?) {
    val club = state.club
    Row(Modifier.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        ClubCrest(club?.name ?: "", club?.id ?: "00", size = 56.dp)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (club != null) {
                Text(
                    club.description?.takeIf { it.isNotBlank() } ?: t("lc.no_description_yet"),
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (club.description.isNullOrBlank()) MaterialTheme.colorScheme.onSurfaceVariant
                    else MaterialTheme.colorScheme.onSurface,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        if (club.isPublic) Icons.Filled.Groups else Icons.Filled.Lock,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Hint(if (club.isPublic) t("lc.anyone_can_find_it") else t("lc.invite_only"), Modifier.padding(start = 4.dp))
                }
            }
            state.role?.let { role ->
                val captains = state.members.firstOrNull { it.userId == myId }?.isCaptain == true
                Row { RolePill(RoleChoice(role.role, captains).label) }
            }
        }
    }
}

/**
 * The checklist a new club works down, until it is done or hidden. Ticked off
 * from what exists — members, teams, a captain, a ground — never from what was
 * tapped. Making the club counts as the first step done.
 */
@Composable
private fun SetupCard(state: ClubPageState, onStep: (SetupStep.Kind) -> Unit, onHide: () -> Unit) {
    val steps = state.setup
    val done = steps.count { it.done } + 1
    val total = steps.size + 1
    Card(
        Modifier.fillMaxWidth().padding(top = 12.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text(t("rest.club_setup"), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(start = 8.dp).weight(1f))
                TextButton(onClick = onHide) { Text(t("rest.hide")) }
            }
            Text(
                t("cl.get_ready_for_first_match", vars = mapOf("club" to (state.club?.name ?: ""))),
                style = MaterialTheme.typography.titleMedium,
            )
            Hint(t("cl.n_of_m_done", vars = mapOf("done" to done, "total" to total, "left" to total - done)))
            LinearProgressIndicator(progress = { done.toFloat() / total }, modifier = Modifier.fillMaxWidth())
            steps.forEach { step ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .clickable(enabled = !step.done, role = Role.Button) { onStep(step.kind) }
                        .semantics { stateDescription = if (step.done) t("ev.done") else t("ld.to_do") }
                        .padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(
                        if (step.done) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                        contentDescription = null,
                        tint = if (step.done) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.secondary,
                    )
                    Column(Modifier.weight(1f)) {
                        Text(
                            step.title,
                            color = if (step.done) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
                            textDecoration = if (step.done) TextDecoration.LineThrough else null,
                        )
                        if (!step.done) Hint(step.detail)
                    }
                }
            }
        }
    }
}

@Composable
private fun LinkRow(icon: ImageVector, text: String, trailing: String? = null, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Text(text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        trailing?.let { Hint(it) }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    HorizontalDivider()
}

@Composable
private fun AddButton(text: String, onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.heightIn(min = 48.dp)) {
        Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp))
        Text(text, modifier = Modifier.padding(start = 6.dp))
    }
}

/** Somebody standing in a car park wants the map, not the address as text. */
@Composable
private fun GroundRow(venue: Venue, onMap: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Filled.Place, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f)) {
            Text(venue.name, style = MaterialTheme.typography.bodyLarge)
            venue.address?.let { Hint(it) }
        }
        IconButton(onClick = onMap) {
            Icon(Icons.Filled.Map, contentDescription = t("cl.open_in_maps", vars = mapOf("name" to venue.name)))
        }
    }
    HorizontalDivider()
}

private fun openMap(context: android.content.Context, venue: Venue) {
    val query = listOfNotNull(venue.name, venue.address).joinToString(", ")
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=${Uri.encode(query)}"))
    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        // No maps app: the browser has one.
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encode(query)}")),
        )
    }
}

@Composable
private fun FixtureRow(fixture: ClubFixture, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(fixture.title, style = MaterialTheme.typography.bodyLarge)
            Hint(fixture.whenText())
        }
        if (fixture.isOff) {
            Text(
                if (fixture.status == "cancelled") t("ld.cancelled") else t("ld.postponed"),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.error,
            )
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    HorizontalDivider()
}

/** "Boom Blast is ready" — straight after the club is made, what comes next. */
@Composable
private fun ClubWelcome(clubName: String, onAddPlayers: () -> Unit, onLater: () -> Unit) {
    AlertDialog(
        onDismissRequest = onLater,
        icon = { Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
        title = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Text(t("cl.club_created"), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                Text(t("cl.club_is_ready", vars = mapOf("club" to clubName)), textAlign = TextAlign.Center)
            }
        },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(t("cl.you_are_its_secretary"), textAlign = TextAlign.Center)
                WelcomeStep(null, t("rest.create_your_club"), null, current = false)
                WelcomeStep(2, t("ld.add_your_players"), t("ld.by_email_or_mobile_number_or_from_a_pr"), current = true)
                WelcomeStep(3, t("lb.add_a_team"), null, current = false)
                WelcomeStep(4, t("cl.add_a_ground"), null, current = false)
                WelcomeStep(5, t("rest.start_your_first_match"), null, current = false)
            }
        },
        confirmButton = { Button(onClick = onAddPlayers) { Text(t("lb.add_players")) } },
        dismissButton = { TextButton(onClick = onLater) { Text(t("cl.ill_do_it_later")) } },
    )
}

@Composable
private fun WelcomeStep(number: Int?, title: String, detail: String?, current: Boolean) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.semantics(mergeDescendants = true) {}) {
        Box(Modifier.size(26.dp), contentAlignment = Alignment.Center) {
            if (number == null) {
                Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            } else {
                Text(
                    "$number",
                    style = MaterialTheme.typography.labelLarge,
                    color = if (current) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = if (current) FontWeight.Bold else FontWeight.Normal,
                )
            }
        }
        Column {
            Text(
                title,
                style = if (current) MaterialTheme.typography.titleSmall else MaterialTheme.typography.bodyMedium,
                color = if (current || number == null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            detail?.let { Hint(it) }
        }
    }
}

@Composable
private fun AddTeamDialog(
    sports: List<String>,
    saving: Boolean,
    error: String?,
    onSave: (name: String, sport: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var name by rememberSaveable { mutableStateOf("") }
    var sport by rememberSaveable { mutableStateOf(sports.first()) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(t("lb.add_a_team")) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    singleLine = true,
                    label = { Text(t("cl.team")) },
                    placeholder = { Text(t("cl.1st_xi")) },
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    modifier = Modifier.fillMaxWidth(),
                )
                // One sport, the usual case, needs no choosing.
                if (sports.size > 1) {
                    Text(t("cl.sport"), style = MaterialTheme.typography.labelLarge)
                    sports.forEach { option ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .heightIn(min = 48.dp)
                                .selectable(selected = sport == option, role = Role.RadioButton) { sport = option },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = sport == option, onClick = null)
                            Text(sportLabel(option), modifier = Modifier.padding(start = 12.dp))
                        }
                    }
                }
                Hint(t("cl.each_team_own_squad"))
                error?.let { ErrorLine(it) }
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(name, sport) }, enabled = !saving && name.isNotBlank()) { Text(t("cl.create")) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(t("sc.cancel")) } },
    )
}

@Composable
private fun AddGroundDialog(
    saving: Boolean,
    error: String?,
    onSave: (name: String, address: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var name by rememberSaveable { mutableStateOf("") }
    var address by rememberSaveable { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(t("cl.add_a_ground")) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    singleLine = true,
                    placeholder = { Text(t("cl.highbury_fields")) },
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = address,
                    onValueChange = { address = it },
                    minLines = 2,
                    placeholder = { Text(t("cl.highbury_fields_london_n5_1ar")) },
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    modifier = Modifier.fillMaxWidth(),
                )
                Hint(t("cl.ground_picked_per_fixture"))
                error?.let { ErrorLine(it) }
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(name, address) }, enabled = !saving && name.isNotBlank()) { Text(t("sc.add")) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(t("sc.cancel")) } },
    )
}
