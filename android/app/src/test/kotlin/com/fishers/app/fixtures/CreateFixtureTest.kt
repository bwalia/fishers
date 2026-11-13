package com.fishers.app.fixtures

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.Team
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
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

@OptIn(ExperimentalCoroutinesApi::class)
class CreateFixtureTest {
    @get:Rule val english = EnglishStrings()

    // One scheduler for runTest and Main — see ClubsTest for why.
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val now = Instant.parse("2026-09-23T12:00:00Z")
    private val london = ZoneId.of("Europe/London")

    private val lords = Club("lords", "Lords CC", sportTypes = listOf("cricket"))
    private val ashford = Club("ashford", "Ashford CC")
    private val nowhere = Club("nowhere", "Nowhere CC")

    /** A secretary of Lords and Ashford, and a plain member of Nowhere. */
    private open inner class Secretary : FakeFixturesApi() {
        var sent: CreateEventBody? = null
        override suspend fun clubs() = listOf(nowhere, lords, ashford)
        override suspend fun myRole(clubId: String) = ClubRole(
            permissions = if (clubId == "nowhere") listOf("respond_as_player")
            else listOf("manage_events", "manage_club_ops"),
        )
        override suspend fun teams(clubId: String) = listOf(Team("t1", clubId, "1st XI"))
        override suspend fun venues(clubId: String) = listOf(Venue("v1", clubId, "The Rec"), Venue("v2", clubId, "Lord's"))
        override suspend fun createEvent(body: CreateEventBody): FishersEvent {
            sent = body
            return FishersEvent(id = "new", clubId = body.clubId, title = body.title, startAt = body.startAt)
        }
    }

    private fun model(api: FakeFixturesApi, clubId: String? = null) =
        CreateFixtureViewModel(api, clubId, london) { now }

    @Test
    fun `only clubs where you may schedule are offered, the one you came from first`() = runTest(dispatcher.scheduler) {
        val model = model(Secretary(), clubId = "lords")
        model.load()
        advanceUntilIdle()

        val state = model.state.value
        assertEquals("a club where you are only a member is not offered", listOf("Ashford CC", "Lords CC"), state.clubs.map { it.name })
        assertEquals("lords", state.clubId)
        assertEquals("its one team is the side, unasked", "t1", state.teamId)
        assertEquals(listOf("The Rec", "Lord's"), state.venues.map { it.name })
        assertNull("two grounds means the secretary says which", state.venueId)
        assertTrue(state.canAddGround)
    }

    /** What the server gets is what the form showed — the time in the secretary's own zone. */
    @Test
    fun `the form sends what the secretary chose`() = runTest(dispatcher.scheduler) {
        val api = Secretary()
        val model = model(api, clubId = "lords")
        model.load()
        advanceUntilIdle()

        model.setOppositionName("  Hemel CC ")
        model.setKind(EventSubtype.Friendly)
        model.selectVenue("v2")
        model.setDate(LocalDate.of(2026, 10, 3))
        model.setTime(LocalTime.of(13, 30))
        model.save()
        advanceUntilIdle()

        val body = api.sent!!
        assertEquals("lords", body.clubId)
        assertEquals("t1", body.teamId)
        assertEquals("Lords CC v Hemel CC", body.title)
        assertEquals("cricket", body.sport)
        assertEquals(EventSubtype.Friendly, body.subtype)
        assertEquals("v2", body.venueId)
        assertNull("a typed side is not a club on the app", body.opponentClubId)
        assertEquals("13:30 in London in October is 12:30 UTC", "2026-10-03T12:30:00Z", body.startAt)
        assertEquals("most of an afternoon", "2026-10-03T17:30:00Z", body.endAt)
        assertEquals("the form becomes the fixture it made", "new", model.state.value.createdEventId)
    }

    @Test
    fun `an opposition found by name has its players asked too`() = runTest(dispatcher.scheduler) {
        var searched: String? = null
        val them = Opponent(id = "h2", name = "2nd XI", kind = "team", clubId = "hemel", clubName = "Hemel CC")
        val api = object : Secretary() {
            override suspend fun searchOpponents(query: String): List<Opponent> {
                searched = query
                // Your own club comes back from the search too; it is not an opposition.
                return listOf(Opponent("lords", "Lords CC", clubId = "lords"), them)
            }
        }
        val model = model(api, clubId = "lords")
        model.load()
        advanceUntilIdle()

        model.setOppositionName("H")
        advanceUntilIdle()
        assertNull("one letter is not worth asking about", searched)

        model.setOppositionName("Hem")
        advanceUntilIdle()
        assertEquals("Hem", searched)
        assertEquals(listOf(them), model.state.value.searchResults)

        model.pickOpponent(them)
        model.save()
        advanceUntilIdle()

        assertEquals("hemel", api.sent!!.opponentClubId)
        assertEquals("Lords CC v Hemel CC — 2nd XI", api.sent!!.title)
    }

    /** A dead button with no explanation reads as a broken app. */
    @Test
    fun `nothing is sent while something is missing, and the form says what`() = runTest(dispatcher.scheduler) {
        val api = Secretary()
        val model = model(api, clubId = "lords")
        model.load()
        advanceUntilIdle()

        model.setDate(LocalDate.of(2026, 9, 22))
        assertEquals(listOf("who you are playing", "when"), model.missing())

        model.save()
        advanceUntilIdle()
        assertNull(api.sent)
    }

    @Test
    fun `a refusal is said in words and the form stays open`() = runTest(dispatcher.scheduler) {
        val model = model(object : Secretary() {
            override suspend fun createEvent(body: CreateEventBody): FishersEvent = throw httpError(403)
        }, clubId = "lords")
        model.load()
        advanceUntilIdle()

        model.setOppositionName("Hemel CC")
        model.save()
        advanceUntilIdle()

        assertEquals("You do not have permission to do that.", model.state.value.error)
        assertNull(model.state.value.createdEventId)
        assertTrue(!model.state.value.isSaving)
    }

    /** "end_at must be after start_at" tells the secretary which box; "HTTP 400" does not. */
    @Test
    fun `what the server explained is passed on`() = runTest(dispatcher.scheduler) {
        val model = model(object : Secretary() {
            override suspend fun createEvent(body: CreateEventBody): FishersEvent =
                throw httpError(404, "that opposition club does not exist")
        }, clubId = "lords")
        model.load()
        advanceUntilIdle()
        model.setOppositionName("Hemel CC")
        model.save()
        advanceUntilIdle()

        assertEquals("That opposition club does not exist", model.state.value.error)
    }

    @Test
    fun `a new ground is saved to the club and chosen for the match`() = runTest(dispatcher.scheduler) {
        var saved: NewVenue? = null
        val model = model(object : Secretary() {
            override suspend fun createVenue(clubId: String, body: NewVenue): Venue {
                saved = body
                return Venue("v3", clubId, body.name)
            }
        }, clubId = "lords")
        model.load()
        advanceUntilIdle()

        model.addGround("  Ashby Road ")
        advanceUntilIdle()

        assertEquals(NewVenue("Ashby Road"), saved)
        assertEquals("v3", model.state.value.venueId)
        assertTrue(model.state.value.venues.any { it.name == "Ashby Road" })
    }

    @Test
    fun `somebody who can schedule nowhere is told so rather than shown an empty form`() = runTest(dispatcher.scheduler) {
        val model = model(object : FakeFixturesApi() {
            override suspend fun clubs() = listOf(nowhere)
            override suspend fun myRole(clubId: String) = ClubRole(permissions = listOf("respond_as_player"))
        })
        model.load()
        advanceUntilIdle()

        assertTrue(model.state.value.clubs.isEmpty())
        assertTrue(!model.state.value.isLoadingClubs)
        assertNull(model.state.value.error)
    }

    @Test
    fun `changing club lets go of its ground and team`() = runTest(dispatcher.scheduler) {
        val model = model(object : Secretary() {
            override suspend fun teams(clubId: String) =
                if (clubId == "lords") listOf(Team("t1", clubId, "1st XI")) else emptyList()
            override suspend fun venues(clubId: String) =
                if (clubId == "lords") listOf(Venue("v1", clubId, "The Rec")) else emptyList()
        }, clubId = "lords")
        model.load()
        advanceUntilIdle()
        assertEquals("v1", model.state.value.venueId)

        model.selectClub("ashford")
        advanceUntilIdle()

        assertNull(model.state.value.venueId)
        assertNull(model.state.value.teamId)
        assertTrue(model.state.value.venues.isEmpty())
    }
}
