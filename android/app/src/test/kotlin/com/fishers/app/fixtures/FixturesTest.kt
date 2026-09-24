package com.fishers.app.fixtures

import com.fishers.app.FakeFishersApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.IOException
import java.time.Instant
import java.time.ZoneId

@OptIn(ExperimentalCoroutinesApi::class)
class FixturesTest {

    // `runTest` builds its own TestCoroutineScheduler unless it is handed
    // one, and a bare StandardTestDispatcher() builds a second. Work launched
    // on viewModelScope then sits on the dispatcher's scheduler while
    // advanceUntilIdle() drains runTest's, so the assertions run before the
    // view model has done anything — sometimes. It passed on every machine
    // here and failed in CI, which is the worst way to find out.
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val now = Instant.parse("2026-09-23T12:00:00Z")

    private fun event(
        id: String,
        startAt: String,
        status: EventStatus = EventStatus.Scheduled,
        myRsvp: RsvpStatus? = null,
    ) = FishersEvent(
        id = id, clubId = "c", title = "Fixture $id",
        startAt = startAt, status = status, myRsvp = myRsvp,
    )

    // ---- what goes where ----

    @Test
    fun `coming up is soonest first, played is most recent first`() = runTest(dispatcher.scheduler) {
        val model = FixturesViewModel(object : FakeFishersApi() {
            override suspend fun myFixtures() = listOf(
                event("far", "2026-10-30T12:00:00Z"),
                event("soon", "2026-09-24T12:00:00Z"),
                event("old", "2026-08-01T12:00:00Z"),
                event("recent", "2026-09-20T12:00:00Z"),
            )
        })

        model.load(now)
        advanceUntilIdle()

        assertEquals(
            "the one being decided about comes first",
            listOf("soon", "far"), model.state.value.upcoming.map { it.id },
        )
        assertEquals(
            "and looking back starts with the last game",
            listOf("recent", "old"), model.state.value.past.map { it.id },
        )
    }

    /**
     * A captain would rather see a fixture with a wrong-looking date than not
     * see it at all — a hidden fixture is a side that does not turn up.
     */
    @Test
    fun `a fixture with an unreadable date is shown rather than dropped`() = runTest(dispatcher.scheduler) {
        val model = FixturesViewModel(object : FakeFishersApi() {
            override suspend fun myFixtures() = listOf(event("odd", "whenever"))
        })

        model.load(now)
        advanceUntilIdle()

        assertEquals(listOf("odd"), model.state.value.upcoming.map { it.id })
    }

    @Test
    fun `a called-off fixture is marked as off`() {
        assertTrue(event("1", "2026-09-24T12:00:00Z", EventStatus.Cancelled).isOff)
        assertTrue(event("2", "2026-09-24T12:00:00Z", EventStatus.Postponed).isOff)
        assertFalse(event("3", "2026-09-24T12:00:00Z").isOff)
    }

    // ---- answering ----

    /**
     * The one place optimism is right: the answer is this person's own and
     * they already know what they tapped. A captain picking a side needs the
     * list to keep up.
     */
    @Test
    fun `an answer shows immediately`() = runTest(dispatcher.scheduler) {
        val model = FixturesViewModel(object : FakeFishersApi() {
            override suspend fun myFixtures() = listOf(event("1", "2026-09-24T12:00:00Z"))
            override suspend fun rsvp(id: String, body: RsvpRequest) = Unit
        })
        model.load(now)
        advanceUntilIdle()

        model.answer("1", RsvpStatus.Going)

        assertEquals(
            "before the server has even answered",
            RsvpStatus.Going, model.state.value.upcoming.first().myRsvp,
        )
        advanceUntilIdle()
        assertNull(model.state.value.answering)
    }

    /**
     * And the one place it has to be undone. An answer the server never took
     * is worse than no answer: the captain counts them and is wrong, and picks
     * a side around somebody who is not coming.
     */
    @Test
    fun `an answer the server refused is taken back off the screen`() = runTest(dispatcher.scheduler) {
        val model = FixturesViewModel(object : FakeFishersApi() {
            override suspend fun myFixtures() =
                listOf(event("1", "2026-09-24T12:00:00Z", myRsvp = RsvpStatus.Maybe))
            override suspend fun rsvp(id: String, body: RsvpRequest): Unit =
                throw IOException("offline")
        })
        model.load(now)
        advanceUntilIdle()

        model.answer("1", RsvpStatus.Going)
        advanceUntilIdle()

        assertEquals(
            "back to what the server actually has",
            RsvpStatus.Maybe, model.state.value.upcoming.first().myRsvp,
        )
        assertTrue(model.state.value.error!!.contains("connection"))
        assertNull(model.state.value.answering)
    }

    @Test
    fun `only one answer is in flight at a time`() = runTest(dispatcher.scheduler) {
        var calls = 0
        val model = FixturesViewModel(object : FakeFishersApi() {
            override suspend fun myFixtures() = listOf(
                event("1", "2026-09-24T12:00:00Z"),
                event("2", "2026-09-25T12:00:00Z"),
            )
            override suspend fun rsvp(id: String, body: RsvpRequest) { calls++ }
        })
        model.load(now)
        advanceUntilIdle()

        model.answer("1", RsvpStatus.Going)
        model.answer("2", RsvpStatus.Going)
        advanceUntilIdle()

        assertEquals("the second was ignored while the first was in flight", 1, calls)
    }

    @Test
    fun `a failed load says why rather than looking empty`() = runTest(dispatcher.scheduler) {
        val model = FixturesViewModel(object : FakeFishersApi() {
            override suspend fun myFixtures(): List<FishersEvent> = throw IOException("down")
        })

        model.load(now)
        advanceUntilIdle()

        assertTrue(model.state.value.error!!.contains("connection"))
        assertFalse(model.state.value.isFirstLoad)
    }

    // ---- formatting ----

    @Test
    fun `the time is shown in the reader's own zone`() {
        val text = formatWhen("2026-09-27T13:30:00Z", ZoneId.of("Europe/London"))
        assertTrue(text, text.contains("14:30"))
        assertTrue(text, text.contains("27 Sep"))
    }

    @Test
    fun `a date nobody can parse is shown as it came rather than as a crash`() {
        assertEquals("whenever", formatWhen("whenever"))
    }
}
