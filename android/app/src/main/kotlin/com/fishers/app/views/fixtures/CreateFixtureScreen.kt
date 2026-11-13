package com.fishers.app.views.fixtures

import android.text.format.DateFormat
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.R
import com.fishers.app.fixtures.CreateFixtureState
import com.fishers.app.fixtures.CreateFixtureViewModel
import com.fishers.app.fixtures.MATCH_KINDS
import com.fishers.app.fixtures.formatDay
import com.fishers.app.fixtures.formatTime
import com.fishers.app.i18n.t
import com.fishers.app.net.FixturesApi
import com.fishers.app.views.clubs.CreateClubRoute
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset

/**
 * Schedule a match — `ScheduleMatchSheet` in `FixturesView.swift`. Saving it
 * asks everyone who might play, and the form becomes the fixture it made.
 */
@Composable
internal fun CreateFixtureScreen(clubId: String?) {
    val deps = LocalAppDeps.current
    val nav = LocalNavigator.current
    val model = remember { CreateFixtureViewModel(deps.service<FixturesApi>(), clubId) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { model.load() }
    LaunchedEffect(state.createdEventId) {
        state.createdEventId?.let { nav.replace(FixtureRoute(it)) }
    }

    PushedScreen(title = t("ev.schedule_a_match")) { padding ->
        when {
            state.isLoadingClubs -> Loading(Modifier.padding(padding))
            state.clubs.isEmpty() -> NowhereToSchedule(
                error = state.error,
                onStartClub = { nav.replace(CreateClubRoute()) },
                modifier = Modifier.padding(padding),
            )
            else -> Form(state, model, Modifier.padding(padding))
        }
    }
}

/** Somebody who opened the form with no club they may schedule for. */
@Composable
private fun NowhereToSchedule(error: String?, onStartClub: () -> Unit, modifier: Modifier) {
    Column(
        modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (error != null) {
            // The clubs would not load — not the same as having none.
            ErrorText(error)
        } else {
            Text(t("fix.cannot_schedule"), style = MaterialTheme.typography.bodyLarge)
            Button(onClick = onStartClub, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("cl.start_a_club")) }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Form(state: CreateFixtureState, model: CreateFixtureViewModel, modifier: Modifier) {
    val brand = stringResource(R.string.brand_name)
    var pickingDate by rememberSaveable { mutableStateOf(false) }
    var pickingTime by rememberSaveable { mutableStateOf(false) }
    val missing = model.missing(state)

    Column(
        modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .imePadding()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        // ---- your side ----
        Section(t("ev.your_side")) {
            if (state.clubs.size > 1) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    state.clubs.forEach { club ->
                        FilterChip(
                            selected = club.id == state.clubId,
                            onClick = { model.selectClub(club.id) },
                            label = { Text(club.name) },
                            modifier = Modifier.heightIn(min = 48.dp),
                        )
                    }
                }
            } else {
                Text(state.club?.name.orEmpty(), style = MaterialTheme.typography.titleMedium)
            }
            // A club with several sides says which one is playing; tap again for none in particular.
            if (state.teams.size > 1) {
                Text(t("cl.team"), style = MaterialTheme.typography.labelLarge)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    state.teams.forEach { team ->
                        val on = team.id == state.teamId
                        FilterChip(
                            selected = on,
                            onClick = { model.selectTeam(if (on) null else team.id) },
                            label = { Text(team.name) },
                            modifier = Modifier.heightIn(min = 48.dp),
                        )
                    }
                }
            }
        }

        // ---- the opposition ----
        Section(t("ev.the_opposition")) {
            val opponent = state.opponent
            if (opponent != null) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        t("opp.playing", vars = mapOf("name" to opponent.displayName)),
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = model::clearOpponent, modifier = Modifier.heightIn(min = 48.dp)) {
                        Text(t("opp.change"))
                    }
                }
                Hint(t("opp.on_brand_too", vars = mapOf("brand" to brand)))
            } else {
                OutlinedTextField(
                    value = state.oppositionName,
                    onValueChange = model::setOppositionName,
                    label = { Text(t("sc.opposition_name")) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Words,
                        imeAction = ImeAction.Done,
                    ),
                    trailingIcon = if (state.isSearching) {
                        { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) }
                    } else null,
                    modifier = Modifier.fillMaxWidth(),
                )
                if (state.searchResults.isNotEmpty()) {
                    Card(Modifier.fillMaxWidth()) {
                        Text(
                            t("fix.on_brand", vars = mapOf("brand" to brand)),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(start = 16.dp, top = 12.dp),
                        )
                        state.searchResults.forEachIndexed { i, found ->
                            if (i > 0) HorizontalDivider()
                            ListItem(
                                headlineContent = { Text(found.displayName) },
                                supportingContent = found.sport?.let { { Text(it.replaceFirstChar(Char::uppercase)) } },
                                modifier = Modifier.clickable(role = Role.Button) { model.pickOpponent(found) },
                            )
                        }
                    }
                }
                Hint(t("ev.club_on_brand_gets_asked", vars = mapOf("brand" to brand)))
            }
        }

        // ---- when ----
        Section(t("ev.when")) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { pickingDate = true },
                    modifier = Modifier.weight(3f).heightIn(min = 48.dp),
                ) {
                    Icon(Icons.Filled.Event, contentDescription = null)
                    Text(formatDay(state.date), Modifier.padding(start = 8.dp))
                }
                OutlinedButton(
                    onClick = { pickingTime = true },
                    modifier = Modifier.weight(2f).heightIn(min = 48.dp),
                ) {
                    Icon(Icons.Filled.Schedule, contentDescription = null)
                    Text(formatTime(state.time), Modifier.padding(start = 8.dp))
                }
            }
        }

        // ---- where ----
        Section(t("ev.where")) {
            if (state.venues.isEmpty() && !state.canAddGround) {
                Hint(t("ev.no_grounds_saved_plain"))
            }
            if (state.venues.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = state.venueId == null,
                        onClick = { model.selectVenue(null) },
                        label = { Text(t("ev.not_decided_yet")) },
                        modifier = Modifier.heightIn(min = 48.dp),
                    )
                    state.venues.forEach { venue ->
                        FilterChip(
                            selected = venue.id == state.venueId,
                            onClick = { model.selectVenue(venue.id) },
                            label = { Text(venue.name) },
                            modifier = Modifier.heightIn(min = 48.dp),
                        )
                    }
                }
            }
            if (state.canAddGround) NewGround(busy = state.isAddingGround, onAdd = model::addGround)
        }

        // ---- the kind of match ----
        Section(t("fix.kind_of_match")) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MATCH_KINDS.forEach { kind ->
                    FilterChip(
                        selected = kind == state.kind,
                        onClick = { model.setKind(kind) },
                        label = { Text(kind.label) },
                        modifier = Modifier.heightIn(min = 48.dp),
                    )
                }
            }
        }

        state.error?.let { ErrorText(it) }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = model::save,
                enabled = !state.isSaving && missing.isEmpty(),
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            ) {
                Text(if (state.isSaving) t("ld.scheduling") else t("ld.schedule_and_ask_who_is_available"))
            }
            Hint(
                if (missing.isNotEmpty()) t("ev.still_needed", vars = mapOf("what" to missing.joinToString(", ")))
                else t(
                    "ev.everyone_in_is_asked",
                    vars = mapOf("who" to if (state.opponent != null) t("ev.both_clubs") else t("ev.your_club")),
                ),
            )
        }
    }

    if (pickingDate) DayPicker(state.date, onPick = { model.setDate(it); pickingDate = false }, onDismiss = { pickingDate = false })
    if (pickingTime) TimeOfDayPicker(state.time, onPick = { model.setTime(it); pickingTime = false }, onDismiss = { pickingTime = false })
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHeading(title)
        content()
    }
}

@Composable
private fun Hint(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/** A ground the club has never saved, added without leaving the form. */
@Composable
private fun NewGround(busy: Boolean, onAdd: (String) -> Unit) {
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
            onValueChange = { name = it },
            label = { Text(t("cl.add_a_ground")) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { add() }),
            modifier = Modifier.weight(1f),
        )
        TextButton(onClick = add, enabled = !busy && name.isNotBlank(), modifier = Modifier.heightIn(min = 48.dp)) {
            Text(t("sc.add"))
        }
    }
}

/**
 * The calendar, from today on. The picker speaks UTC midnights, so a day is
 * read back as a UTC date — reading it in the phone's zone puts a match a day
 * early for anyone west of Greenwich.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DayPicker(initial: LocalDate, onPick: (LocalDate) -> Unit, onDismiss: () -> Unit) {
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
                onClick = {
                    state.selectedDateMillis?.let {
                        onPick(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate())
                    } ?: onDismiss()
                },
            ) { Text(t("rest.ok")) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(t("sc.cancel")) } },
    ) {
        DatePicker(state = state)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimeOfDayPicker(initial: LocalTime, onPick: (LocalTime) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val state = rememberTimePickerState(
        initialHour = initial.hour,
        initialMinute = initial.minute,
        is24Hour = DateFormat.is24HourFormat(context),
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = { onPick(LocalTime.of(state.hour, state.minute)) }) { Text(t("rest.ok")) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(t("sc.cancel")) } },
        text = { TimePicker(state = state) },
    )
}
