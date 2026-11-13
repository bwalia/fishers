package com.fishers.app.fixtures

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.Team
import com.fishers.app.motm.MotmPollView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID

/** Scheduling nets and training — one session or a weekly series — and how one reads afterwards. */
@OptIn(ExperimentalCoroutinesApi::class)
class NetsAndPracticeTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val now = Instant.parse("2026-09-23T12:00:00Z")
    private val london = ZoneId.of("Europe/London")

    /** What `Network` sends with: nulls left out, defaults kept. */
    private val wire = Json {
        explicitNulls = false
        encodeDefaults = true
    }

    private val lords = Club("lords", "Lords CC", sportTypes = listOf("cricket"))

    /** A secretary of Lords. Every body it is sent is kept, in order; [refuse] says which calls fail. */
    private open inner class Secretary : FakeFixturesApi() {
        val sent = mutableListOf<CreateEventBody>()
        var refuse: (call: Int) -> Boolean = { false }

        override suspend fun clubs() = listOf(lords)
        override suspend fun myRole(clubId: String) = ClubRole(permissions = listOf("manage_events"))
        override suspend fun teams(clubId: String) = listOf(Team("t1", clubId, "1st XI"))
        override suspend fun venues(clubId: String) = listOf(Venue("v1", clubId, "The Rec"), Venue("v2", clubId, "Indoor school"))
        override suspend fun createEvent(body: CreateEventBody): FishersEvent {
            sent += body
            if (refuse(sent.size)) throw httpError(400, "the indoor school is closed that week")
            return FishersEvent(id = "e${sent.size}", clubId = body.clubId, title = body.title, startAt = body.startAt)
        }
    }

    /** As the screen opens it from "Schedule nets or practice". */
    private fun TestScope.netsForm(api: Secretary): CreateFixtureViewModel {
        val model = CreateFixtureViewModel(api, "lords", london) { now }
        model.setWhat(EventSubtype.Nets)
        model.load()
        advanceUntilIdle()
        return model
    }

    // ---- the form ----

    @Test
    fun `nets are named and timed for themselves until somebody changes them`() = runTest(dispatcher.scheduler) {
        val model = netsForm(Secretary())
        assertEquals("Nets", model.state.value.name)
        assertEquals(120, model.state.value.minutes)

        model.setWhat(EventSubtype.Training)
        assertEquals("Training", model.state.value.name)
        assertEquals(90, model.state.value.minutes)

        model.setName("Wednesday nets")
        model.setMinutes(60)
        model.setWhat(EventSubtype.Nets)
        assertEquals("what was typed stays", "Wednesday nets", model.state.value.name)
        assertEquals("what was chosen stays", 60, model.state.value.minutes)

        assertTrue("no opposition is asked for", model.missing().isEmpty())
        model.setWeeks(40)
        assertEquals(12, model.state.value.weeks)
        model.setWeeks(1)
        assertEquals(2, model.state.value.weeks)
    }

    // ---- what is sent ----

    @Test
    fun `one nets session sends one event and no opposition or series`() = runTest(dispatcher.scheduler) {
        val api = Secretary()
        val model = netsForm(api)
        model.setName("  Wednesday nets ")
        model.selectVenue("v2")
        model.setNote("  Bring your own bat. ")
        model.setDate(LocalDate.of(2026, 9, 30))
        model.setTime(LocalTime.of(19, 0))
        model.save()
        advanceUntilIdle()

        val body = api.sent.single()
        assertEquals("lords", body.clubId)
        assertEquals("t1", body.teamId)
        assertEquals("cricket", body.sport)
        assertEquals(EventSubtype.Nets, body.subtype)
        assertEquals("Wednesday nets", body.title)
        assertEquals("v2", body.venueId)
        assertNull(body.opponentClubId)
        assertEquals("19:00 in London in September is 18:00 UTC", "2026-09-30T18:00:00Z", body.startAt)
        assertEquals("two hours of nets", "2026-09-30T20:00:00Z", body.endAt)
        assertEquals(SessionMetadata(note = "Bring your own bat."), body.metadata)

        val json = wire.encodeToJsonElement(CreateEventBody.serializer(), body).jsonObject
        assertEquals("nets", json["event_subtype"]!!.jsonPrimitive.content)
        assertFalse(json.containsKey("opponent_club_id"))
        assertFalse(json.containsKey("recurrence_rule"))
        assertEquals(setOf("note"), json["metadata"]!!.jsonObject.keys)

        assertEquals("the form becomes the session", "e1", model.state.value.createdEventId)
        assertEquals(1, model.state.value.sessionsMade)
    }

    /** The clocks go back on 25 October 2026. Seven o'clock nets stay at seven. */
    @Test
    fun `a weekly series shares one id, counts its weeks and keeps its local time across the clock change`() =
        runTest(dispatcher.scheduler) {
            val api = Secretary()
            val model = netsForm(api)
            model.setWhat(EventSubtype.Training)
            model.setDate(LocalDate.of(2026, 10, 14))
            model.setTime(LocalTime.of(19, 0))
            model.setRepeatWeekly(true)
            model.setWeeks(3)
            model.save()
            advanceUntilIdle()

            val weeks = api.sent
            assertEquals(3, weeks.size)
            assertEquals(
                "19:00 BST, 19:00 BST, then 19:00 GMT",
                listOf("2026-10-14T18:00:00Z", "2026-10-21T18:00:00Z", "2026-10-28T19:00:00Z"),
                weeks.map { it.startAt },
            )
            assertEquals(
                "each ends an hour and a half after it starts",
                listOf("2026-10-14T19:30:00Z", "2026-10-21T19:30:00Z", "2026-10-28T20:30:00Z"),
                weeks.map { it.endAt },
            )
            val ids = weeks.map { it.metadata!!.seriesId }.toSet()
            assertEquals("one series id for every week", 1, ids.size)
            UUID.fromString(ids.single()!!)
            assertEquals(listOf(0, 1, 2), weeks.map { it.metadata!!.seriesIndex })
            assertEquals(listOf(3, 3, 3), weeks.map { it.metadata!!.seriesCount })
            assertTrue(weeks.all { it.subtype == EventSubtype.Training && it.title == "Training" })
            assertTrue("no note, none sent", weeks.all { it.metadata!!.note == null })

            assertEquals("the form becomes the first week", "e1", model.state.value.createdEventId)
            assertEquals(3, model.state.value.sessionsMade)
        }

    @Test
    fun `a week that fails stops the series, and trying again never sends a made week twice`() =
        runTest(dispatcher.scheduler) {
            val api = Secretary()
            api.refuse = { call -> call == 2 }
            val model = netsForm(api)
            model.setDate(LocalDate.of(2026, 10, 7))
            model.setTime(LocalTime.of(18, 30))
            model.setRepeatWeekly(true)
            model.setWeeks(3)
            model.save()
            advanceUntilIdle()

            assertEquals("week 3 is not tried once week 2 fails", listOf(0, 1), api.sent.map { it.metadata!!.seriesIndex })
            val state = model.state.value
            assertEquals("one week is made, and the form says so", 1, state.sessionsMade)
            assertEquals("The indoor school is closed that week", state.error)
            assertNull("the form stays open", state.createdEventId)
            assertFalse(state.isSaving)

            api.refuse = { false }
            model.save()
            advanceUntilIdle()

            assertEquals(
                "week 1 is sent once; weeks 2 and 3 follow",
                listOf(0, 1, 1, 2),
                api.sent.map { it.metadata!!.seriesIndex },
            )
            assertEquals(1, api.sent.count { it.metadata!!.seriesIndex == 0 })
            assertEquals("still one series", 1, api.sent.map { it.metadata!!.seriesId }.toSet().size)
            assertEquals("e1", model.state.value.createdEventId)
            assertEquals(3, model.state.value.sessionsMade)
            assertNull(model.state.value.error)
        }

    @Test
    fun `a match is sent as it always was`() = runTest(dispatcher.scheduler) {
        val api = Secretary()
        val model = CreateFixtureViewModel(api, "lords", london) { now }
        model.load()
        advanceUntilIdle()

        assertEquals("the form opens on a match", null, model.state.value.practice)
        assertEquals(listOf("who you are playing"), model.missing())

        // Through nets and back: nothing of the session leaks into the match.
        model.setWhat(EventSubtype.Nets)
        model.setNote("Bring your own bat.")
        model.setRepeatWeekly(true)
        model.setWhat(null)

        model.setOppositionName("Hemel CC")
        model.setDate(LocalDate.of(2026, 10, 3))
        model.setTime(LocalTime.of(13, 30))
        model.save()
        advanceUntilIdle()

        val body = api.sent.single()
        assertEquals(EventSubtype.LeagueMatch, body.subtype)
        assertEquals("Lords CC v Hemel CC", body.title)
        assertEquals("2026-10-03T12:30:00Z", body.startAt)
        assertEquals("2026-10-03T17:30:00Z", body.endAt)
        assertNull(body.metadata)
        assertEquals(
            setOf("club_id", "team_id", "sport", "event_subtype", "title", "start_at", "end_at"),
            wire.encodeToJsonElement(CreateEventBody.serializer(), body).jsonObject.keys,
        )
    }

    // ---- reading one ----

    private val nets = FishersEvent(
        id = "n1", clubId = "lords", title = "Wednesday nets",
        subtype = EventSubtype.Nets, startAt = "2099-10-14T18:00:00Z", endAt = "2099-10-14T20:00:00Z",
        metadata = buildJsonObject {
            put("note", " Bring your own bat. ")
            put("series_id", "4b1c7d0e-1111-4c2d-9a3e-000000000001")
            put("series_index", 2)
            put("series_count", 8)
        },
    )

    /** Nets ask about nothing a match would: no scorebook, no side. */
    private open inner class Page(private val event: FishersEvent) : FakeFixturesApi() {
        val asked = mutableListOf<String>()
        override suspend fun event(id: String) = event
        override suspend fun attendees(id: String) = emptyList<Attendee>()
        override suspend fun myRole(clubId: String) =
            ClubRole(permissions = listOf("manage_selection", "score_match"), isCaptain = true)
        override suspend fun selectionBoard(id: String): SelectionBoard {
            asked += "selection"
            return SelectionBoard(eventId = id, title = event.title, startsAt = event.startAt, candidates = emptyList())
        }
        override suspend fun cricketMatch(eventId: String): FixtureMatch {
            asked += "match"
            throw httpError(404)
        }
        override suspend fun motm(eventId: String): MotmPollView = throw httpError(404)
    }

    @Test
    fun `a nets page has no match card or side, and asks whether you are coming`() = runTest(dispatcher.scheduler) {
        val api = Page(nets)
        val model = FixtureDetailViewModel(api, "n1", "me")
        model.load()
        advanceUntilIdle()

        val state = model.state.value
        assertFalse(state.hasMatchCard)
        assertEquals("even for a scorer", emptyList<MatchAction>(), state.matchActions())
        assertNull(state.board)
        assertEquals("neither the scorebook nor the side is asked for", emptyList<String>(), api.asked)
        assertEquals("Are you coming?", state.question)

        val practice = state.event!!.practice!!
        assertEquals("Bring your own bat.", practice.note)
        assertEquals("Week 3 of 8", practice.weekOf)
        assertEquals("Nets", state.event!!.subtype.label)
    }

    @Test
    fun `a match page is as it was`() = runTest(dispatcher.scheduler) {
        val league = nets.copy(title = "Lords CC v Hemel CC", subtype = EventSubtype.LeagueMatch)
        val model = FixtureDetailViewModel(Page(league), "e1", "me")
        model.load()
        advanceUntilIdle()

        val state = model.state.value
        assertTrue(state.hasMatchCard)
        assertEquals(listOf(MatchAction.SetUp), state.matchActions())
        assertEquals("Are you playing?", state.question)
        assertNull("a match's metadata is not read as a session's", state.event!!.practice)
    }

    @Test
    fun `a session on its own has no week, and odd metadata is shrugged off`() {
        val single = nets.copy(metadata = buildJsonObject { put("note", "") })
        assertNull(single.practice!!.weekOf)
        assertNull("a blank note is no note", single.practice!!.note)

        val odd = nets.copy(metadata = buildJsonObject { put("series_index", "soon") })
        assertEquals(PracticeDetails(), odd.practice)
        assertEquals(PracticeDetails(), nets.copy(metadata = null).practice)

        val fromTheList = MyFixture(
            id = "n1", clubId = "lords", title = "Training", subtype = EventSubtype.Training,
            startAt = "2099-10-14T18:00:00Z",
            metadata = buildJsonObject { put("series_index", 0); put("series_count", 4) },
        )
        assertEquals("Week 1 of 4", fromTheList.practice!!.weekOf)
    }
}
