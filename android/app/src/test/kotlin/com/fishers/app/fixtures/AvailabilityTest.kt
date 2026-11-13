package com.fishers.app.fixtures

import com.fishers.app.EnglishStrings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.io.IOException
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

@OptIn(ExperimentalCoroutinesApi::class)
class AvailabilityTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val london = ZoneId.of("Europe/London")
    private val today = LocalDate.of(2026, 9, 10)

    private open inner class Calendar : FakeFixturesApi() {
        var asked: Pair<String, String>? = null
        var fixturesAsked: Pair<String?, String?>? = null
        override suspend fun availability(from: String, to: String): List<DayAvailability> {
            asked = from to to
            return listOf(DayAvailability("2026-09-12", AvailabilityStatus.Available))
        }
        override suspend fun myFixtures(from: String?, to: String?): List<MyFixture> {
            fixturesAsked = from to to
            return listOf(
                // 23:30 UTC on the 26th is half past midnight on the 27th in London.
                MyFixture(id = "late", clubId = "c", title = "Late one", startAt = "2026-09-26T23:30:00Z"),
            )
        }
    }

    @Test
    fun `the month is a Monday-first grid of whole weeks`() {
        // September 2026 starts on a Tuesday and has 30 days.
        val grid = AvailabilityViewModel.grid(YearMonth.of(2026, 9))
        assertNull(grid[0])
        assertEquals(LocalDate.of(2026, 9, 1), grid[1])
        assertEquals(0, grid.size % 7)
        assertEquals(30, grid.count { it != null })
    }

    @Test
    fun `every Saturday means every Saturday in the month shown`() {
        assertEquals(
            listOf(5, 12, 19, 26).map { LocalDate.of(2026, 9, it) },
            AvailabilityViewModel.datesIn(YearMonth.of(2026, 9), DayOfWeek.SATURDAY),
        )
    }

    @Test
    fun `a month asks for its own days, and fixtures sit on the reader's day`() = runTest(dispatcher.scheduler) {
        val api = Calendar()
        val model = AvailabilityViewModel(api, london, today)
        model.load()
        advanceUntilIdle()

        assertEquals("2026-09-01" to "2026-09-30", api.asked)
        assertEquals("from London's first midnight", "2026-08-31T23:00:00Z", api.fixturesAsked!!.first)
        assertEquals(AvailabilityStatus.Available, model.state.value.days[LocalDate.of(2026, 9, 12)])
        assertEquals(listOf("late"), model.fixturesOn(LocalDate.of(2026, 9, 27)).map { it.id })
        assertTrue(model.fixturesOn(LocalDate.of(2026, 9, 26)).isEmpty())
    }

    @Test
    fun `setting every Saturday sends them in one go`() = runTest(dispatcher.scheduler) {
        var sent: SetDaysAvailability? = null
        val model = AvailabilityViewModel(object : Calendar() {
            override suspend fun setAvailability(body: SetDaysAvailability): List<DayAvailability> {
                sent = body
                return body.dates.map { DayAvailability(it, body.status) }
            }
        }, london, today)
        model.load()
        advanceUntilIdle()

        model.setEvery(DayOfWeek.SATURDAY, AvailabilityStatus.Maybe)
        advanceUntilIdle()

        assertEquals(listOf("2026-09-05", "2026-09-12", "2026-09-19", "2026-09-26"), sent!!.dates)
        assertEquals(AvailabilityStatus.Maybe, model.state.value.days[LocalDate.of(2026, 9, 12)])
    }

    @Test
    fun `a day that did not save is put back`() = runTest(dispatcher.scheduler) {
        val model = AvailabilityViewModel(object : Calendar() {
            override suspend fun setAvailability(body: SetDayAvailability): DayAvailability = throw IOException("offline")
        }, london, today)
        model.load()
        advanceUntilIdle()

        model.setDay(LocalDate.of(2026, 9, 12), AvailabilityStatus.Unavailable)
        model.setDay(LocalDate.of(2026, 9, 13), AvailabilityStatus.Available)
        advanceUntilIdle()

        assertEquals(AvailabilityStatus.Available, model.state.value.days[LocalDate.of(2026, 9, 12)])
        assertNull("a day that had nothing has nothing again", model.state.value.days[LocalDate.of(2026, 9, 13)])
        assertTrue(model.state.value.error!!.isNotEmpty())
    }
}
