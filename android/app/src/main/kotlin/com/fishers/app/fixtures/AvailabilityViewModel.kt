package com.fishers.app.fixtures

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.net.FixturesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

data class AvailabilityState(
    val month: YearMonth,
    /** Your standing calendar: a colour per day you have said something about. */
    val days: Map<LocalDate, AvailabilityStatus> = emptyMap(),
    /** Your fixtures this month, each with your answer — the marks on a day. */
    val fixtures: List<MyFixture> = emptyList(),
    val selectedDay: LocalDate? = null,
    val isLoading: Boolean = true,
    val bulkBusy: Boolean = false,
    /** Which fixture is mid-answer. */
    val answering: String? = null,
    val error: String? = null,
)

/**
 * When you can play — `CalendarViewModel.swift`. Two things a captain reads on
 * one calendar: the colour of a day is your general availability; the marks
 * on it are that day's fixtures, each in the colour of your answer.
 */
class AvailabilityViewModel(
    private val api: FixturesApi,
    private val zone: ZoneId = ZoneId.systemDefault(),
    today: LocalDate = LocalDate.now(zone),
) : ViewModel() {

    private val _state = MutableStateFlow(AvailabilityState(month = YearMonth.from(today), selectedDay = today))
    val state: StateFlow<AvailabilityState> = _state.asStateFlow()

    fun load() {
        val month = _state.value.month
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            val first = month.atDay(1)
            // Fixtures are instants: from the first midnight of the month to the first of the next.
            val fixtures = async {
                runCatching {
                    api.myFixtures(
                        from = first.atStartOfDay(zone).toInstant().toString(),
                        to = month.plusMonths(1).atDay(1).atStartOfDay(zone).toInstant().toString(),
                    )
                }.getOrDefault(emptyList())
            }
            runCatching { api.availability(first.toString(), month.atEndOfMonth().toString()) }
                .onSuccess { days ->
                    val found = fixtures.await()
                    if (_state.value.month != month) return@onSuccess
                    _state.value = _state.value.copy(
                        days = days.mapNotNull { d -> parseDay(d.date)?.let { it to d.status } }.toMap(),
                        fixtures = found.sortedBy { it.startsAt },
                        isLoading = false,
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(isLoading = false, error = fixtureError(it))
                }
        }
    }

    fun previousMonth() = showMonth(_state.value.month.minusMonths(1))

    fun nextMonth() = showMonth(_state.value.month.plusMonths(1))

    private fun showMonth(month: YearMonth) {
        _state.value = _state.value.copy(
            month = month, days = emptyMap(), fixtures = emptyList(), selectedDay = null,
        )
        load()
    }

    fun select(day: LocalDate) {
        _state.value = _state.value.copy(selectedDay = day)
    }

    /** One day. Shown at once, put back if it does not save. */
    fun setDay(day: LocalDate, status: AvailabilityStatus) {
        val before = _state.value.days
        if (before[day] == status) return
        _state.value = _state.value.copy(days = before + (day to status), error = null)
        viewModelScope.launch {
            runCatching { api.setAvailability(SetDayAvailability(day.toString(), status)) }
                .onFailure {
                    val now = _state.value.days
                    val restored = before[day]?.let { was -> now + (day to was) } ?: (now - day)
                    _state.value = _state.value.copy(days = restored, error = fixtureError(it))
                }
        }
    }

    /**
     * Every one of a weekday in the month shown, at once — the way people
     * actually think about it: "Saturdays I play". Then fix the odd day.
     */
    fun setEvery(weekday: DayOfWeek, status: AvailabilityStatus) {
        val dates = datesIn(_state.value.month, weekday)
        if (dates.isEmpty() || _state.value.bulkBusy) return
        viewModelScope.launch {
            _state.value = _state.value.copy(bulkBusy = true, error = null)
            runCatching { api.setAvailability(SetDaysAvailability(dates.map(LocalDate::toString), status)) }
                .onSuccess { saved ->
                    _state.value = _state.value.copy(
                        days = _state.value.days + saved.mapNotNull { d -> parseDay(d.date)?.let { it to d.status } },
                        bulkBusy = false,
                    )
                }
                .onFailure { _state.value = _state.value.copy(bulkBusy = false, error = fixtureError(it)) }
        }
    }

    /** Answer a fixture from its day — the same optimistic rule as the list. */
    fun answer(eventId: String, status: RsvpStatus) {
        val before = _state.value
        if (before.answering != null) return
        _state.value = before.copy(
            answering = eventId,
            fixtures = before.fixtures.map { if (it.id == eventId) it.copy(myRsvp = status) else it },
            error = null,
        )
        viewModelScope.launch {
            runCatching { api.rsvp(eventId, RsvpRequest(status)) }
                .onSuccess { _state.value = _state.value.copy(answering = null) }
                .onFailure {
                    _state.value = _state.value.copy(
                        answering = null,
                        fixtures = _state.value.fixtures.map { f ->
                            if (f.id == eventId) f.copy(myRsvp = before.fixtures.firstOrNull { it.id == eventId }?.myRsvp) else f
                        },
                        error = fixtureError(it),
                    )
                }
        }
    }

    fun fixturesOn(day: LocalDate, state: AvailabilityState = _state.value): List<MyFixture> =
        state.fixtures.filter { it.startsAt?.atZone(zone)?.toLocalDate() == day }

    private fun parseDay(raw: String): LocalDate? = runCatching { LocalDate.parse(raw.take(10)) }.getOrNull()

    companion object {
        /** Every date in [month] that falls on [weekday]. */
        fun datesIn(month: YearMonth, weekday: DayOfWeek): List<LocalDate> =
            (1..month.lengthOfMonth()).map(month::atDay).filter { it.dayOfWeek == weekday }

        /**
         * The month as a Monday-first grid: blanks before the 1st and after
         * the last, so every row is a whole week.
         */
        fun grid(month: YearMonth): List<LocalDate?> {
            val lead = month.atDay(1).dayOfWeek.value - 1
            val days = (1..month.lengthOfMonth()).map(month::atDay)
            val cells: List<LocalDate?> = List(lead) { null } + days
            return cells + List((7 - cells.size % 7) % 7) { null }
        }
    }
}
