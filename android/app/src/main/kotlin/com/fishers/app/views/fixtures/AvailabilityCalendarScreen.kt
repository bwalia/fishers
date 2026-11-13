package com.fishers.app.views.fixtures

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.fixtures.AvailabilityState
import com.fishers.app.fixtures.AvailabilityStatus
import com.fishers.app.fixtures.AvailabilityViewModel
import com.fishers.app.fixtures.MyFixture
import com.fishers.app.fixtures.RsvpStatus
import com.fishers.app.fixtures.appLocale
import com.fishers.app.fixtures.formatTime
import com.fishers.app.i18n.t
import com.fishers.app.net.FixturesApi
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle

/**
 * When you can play — and what you said to each fixture. `AvailabilityCalendarView.swift`.
 *
 * The colour of a day is your general availability; the dots on it are that
 * day's fixtures, each in the colour of your answer. Tap a day to set it and
 * answer its fixtures there.
 */
@Composable
internal fun AvailabilityCalendarScreen() {
    val deps = LocalAppDeps.current
    val model = remember { AvailabilityViewModel(deps.service<FixturesApi>()) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { model.load() }

    PushedScreen(title = t("ev.your_calendar")) { padding ->
        Column(
            Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                t("ev.your_usual_days_and_every_fixture_with"),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            MonthHeader(state, onPrevious = model::previousMonth, onNext = model::nextMonth)
            MonthGrid(state, fixturesOn = { model.fixturesOn(it, state) }, onSelect = model::select)
            Legend()
            state.error?.let { ErrorText(it) }
            state.selectedDay?.let { day ->
                DayCard(
                    day = day,
                    status = state.days[day],
                    fixtures = model.fixturesOn(day, state),
                    answering = state.answering,
                    onSet = { model.setDay(day, it) },
                    onAnswer = model::answer,
                )
            }
            UsualDays(state, onSet = model::setEvery)
        }
    }
}

@Composable
private fun MonthHeader(state: AvailabilityState, onPrevious: () -> Unit, onNext: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onPrevious) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = t("ev.previous_month"))
        }
        Text(
            DateTimeFormatter.ofPattern("MMMM yyyy", appLocale()).format(state.month),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.weight(1f).semantics { heading() },
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        IconButton(onClick = onNext) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = t("ev.next_month"))
        }
    }
}

@Composable
private fun MonthGrid(
    state: AvailabilityState,
    fixturesOn: (LocalDate) -> List<MyFixture>,
    onSelect: (LocalDate) -> Unit,
) {
    val today = remember { LocalDate.now() }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            DayOfWeek.entries.forEach {
                Text(
                    it.getDisplayName(TextStyle.NARROW, appLocale()),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    modifier = Modifier.weight(1f),
                )
            }
        }
        AvailabilityViewModel.grid(state.month).chunked(7).forEach { week ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                week.forEach { day ->
                    if (day == null) {
                        Spacer(Modifier.weight(1f).height(48.dp))
                    } else {
                        DayCell(
                            day = day,
                            status = state.days[day],
                            marks = fixturesOn(day),
                            selected = day == state.selectedDay,
                            today = day == today,
                            onClick = { onSelect(day) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DayCell(
    day: LocalDate,
    status: AvailabilityStatus?,
    marks: List<MyFixture>,
    selected: Boolean,
    today: Boolean,
    onClick: () -> Unit,
    modifier: Modifier,
) {
    val shape = RoundedCornerShape(10.dp)
    val fill = status?.let { availabilityColour(it) } ?: MaterialTheme.colorScheme.surfaceContainerHigh
    val ink = if (status != null) Color.White else MaterialTheme.colorScheme.onSurface
    val said = status?.label ?: t("ev.not_said")
    val described = buildString {
        append(DateTimeFormatter.ofPattern("EEEE d MMMM", appLocale()).format(day))
        append(", ").append(said)
        marks.forEach { append("; ").append(it.title).append(": ").append(it.myRsvp?.label ?: t("ev.not_answered")) }
    }
    Box(
        modifier
            .heightIn(min = 48.dp)
            .background(fill, shape)
            .then(
                if (selected) Modifier.border(2.dp, MaterialTheme.colorScheme.onSurface, shape)
                else if (today) Modifier.border(1.dp, MaterialTheme.colorScheme.primary, shape)
                else Modifier,
            )
            .clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) {
                contentDescription = described
                this.selected = selected
            },
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text("${day.dayOfMonth}", style = MaterialTheme.typography.bodyMedium, color = ink)
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.height(6.dp)) {
                marks.take(3).forEach { f ->
                    Box(Modifier.size(6.dp).background(markColour(f.myRsvp, onColour = status != null), CircleShape))
                }
            }
        }
    }
}

/** A fixture's dot: your answer, readable on a coloured day as well as a blank one. */
@Composable
private fun markColour(answer: RsvpStatus?, onColour: Boolean): Color = when (answer) {
    RsvpStatus.Going -> if (onColour) Color.White else availabilityColour(AvailabilityStatus.Available)
    RsvpStatus.Maybe -> if (onColour) Color(0xFFFFE082) else availabilityColour(AvailabilityStatus.Maybe)
    RsvpStatus.NotGoing -> if (onColour) Color.Black.copy(alpha = 0.5f) else availabilityColour(AvailabilityStatus.Unavailable)
    else -> if (onColour) Color.White.copy(alpha = 0.6f) else MaterialTheme.colorScheme.onSurfaceVariant
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Legend() {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        AvailabilityStatus.entries.forEach {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.size(12.dp).background(availabilityColour(it), RoundedCornerShape(3.dp)))
                Text(it.label, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

/** The day you tapped: your availability for it, and each of its fixtures to answer. */
@Composable
private fun DayCard(
    day: LocalDate,
    status: AvailabilityStatus?,
    fixtures: List<MyFixture>,
    answering: String?,
    onSet: (AvailabilityStatus) -> Unit,
    onAnswer: (String, RsvpStatus) -> Unit,
) {
    val nav = LocalNavigator.current
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                DateTimeFormatter.ofPattern("EEEE d MMMM yyyy", appLocale()).format(day),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(t("ev.your_availability_this_day"), style = MaterialTheme.typography.labelLarge)
            StatusChips(selected = status, onSet = onSet)
            if (fixtures.isEmpty()) {
                Text(
                    t("ev.no_fixtures_this_day"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            fixtures.forEach { fixture ->
                Column(
                    Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surfaceContainerHighest, RoundedCornerShape(12.dp))
                        .padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .clickable(role = Role.Button) { nav.push(FixtureRoute(fixture.id)) },
                    ) {
                        Text(fixture.title, style = MaterialTheme.typography.titleSmall)
                        Text(
                            listOfNotNull(
                                fixture.startsAt?.atZone(ZoneId.systemDefault())?.toLocalTime()?.let(::formatTime),
                                fixture.venueName,
                            ).joinToString(" · "),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (!fixture.isOff && fixture.isUpcoming()) {
                        AnswerChips(
                            answer = fixture.myRsvp,
                            enabled = answering == null,
                            onAnswer = { onAnswer(fixture.id, it) },
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StatusChips(selected: AvailabilityStatus?, onSet: (AvailabilityStatus) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        AvailabilityStatus.entries.forEach {
            FilterChip(
                selected = selected == it,
                onClick = { onSet(it) },
                label = { Text(it.label) },
                modifier = Modifier.heightIn(min = 48.dp),
            )
        }
    }
}

/** A whole weekday for the month at once, then fix the odd day. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun UsualDays(state: AvailabilityState, onSet: (DayOfWeek, AvailabilityStatus) -> Unit) {
    var weekday by rememberSaveable { mutableStateOf(DayOfWeek.SATURDAY) }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            SectionHeading(t("ev.your_usual_days"))
            Text(
                t("ev.set_every_weekday_in", vars = mapOf("month" to DateTimeFormatter.ofPattern("MMMM", appLocale()).format(state.month))),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                DayOfWeek.entries.forEach {
                    FilterChip(
                        selected = weekday == it,
                        onClick = { weekday = it },
                        label = { Text(t(WEEKDAY_KEYS.getValue(it))) },
                        modifier = Modifier.heightIn(min = 48.dp),
                    )
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AvailabilityStatus.entries.forEach {
                    OutlinedButton(
                        onClick = { onSet(weekday, it) },
                        enabled = !state.bulkBusy,
                        modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                    ) { Text(it.label, color = availabilityColour(it)) }
                }
            }
        }
    }
}

private val WEEKDAY_KEYS = mapOf(
    DayOfWeek.MONDAY to "ev.mondays",
    DayOfWeek.TUESDAY to "ev.tuesdays",
    DayOfWeek.WEDNESDAY to "ev.wednesdays",
    DayOfWeek.THURSDAY to "ev.thursdays",
    DayOfWeek.FRIDAY to "ev.fridays",
    DayOfWeek.SATURDAY to "ev.saturdays",
    DayOfWeek.SUNDAY to "ev.sundays",
)
