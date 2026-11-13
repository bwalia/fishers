package com.fishers.app.match

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.Team
import com.fishers.app.match.start.ClubIdentity
import com.fishers.app.match.start.ConfirmCode
import com.fishers.app.match.start.CreatedFixture
import com.fishers.app.match.start.MatchKind
import com.fishers.app.match.start.NewClub
import com.fishers.app.match.start.NewFixture
import com.fishers.app.match.start.StartMatchViewModel
import com.fishers.app.net.PublicUser
import com.fishers.app.season.MyClubRole
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class StartMatchTest {
    @get:Rule val english = EnglishStrings()

    // One scheduler for runTest and Dispatchers.Main — see ClubsTest.
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val noon = Instant.parse("2026-11-14T12:00:00Z")

    private val hemel = ClubIdentity(id = "hemel", name = "Hemel CC", clubId = "hemel", clubName = "Hemel CC")

    /** A server with clubs, roles and teams; records what was made. */
    private open inner class Server(
        val clubs: List<Club> = emptyList(),
        val perms: Map<String, List<String>> = emptyMap(),
        val teams: Map<String, List<Team>> = emptyMap(),
    ) : FakeMatchStartApi() {
        val fixtures = mutableListOf<NewFixture>()
        val madeClubs = mutableListOf<NewClub>()
        override suspend fun myClubs() = clubs
        override suspend fun myClubRole(clubId: String) = MyClubRole(permissions = perms[clubId].orEmpty())
        override suspend fun clubTeams(clubId: String) = teams[clubId].orEmpty()
        override suspend fun createEvent(body: NewFixture): CreatedFixture {
            fixtures += body
            return CreatedFixture(id = "event-${fixtures.size}", clubId = body.clubId, title = body.title)
        }
        override suspend fun createClub(body: NewClub): Club {
            madeClubs += body
            return Club(id = "new-club", name = body.name)
        }
    }

    @Test
    fun `only clubs where you may make a fixture are offered, as iOS decides`() = runTest(dispatcher.scheduler) {
        val server = Server(
            clubs = listOf(Club("a", "Ashford CC"), Club("l", "Lords CC")),
            perms = mapOf("a" to listOf("view_club"), "l" to listOf("view_club", "manage_events")),
        )
        val model = StartMatchViewModel(server)
        model.load()
        advanceUntilIdle()

        assertEquals(listOf("Lords CC"), model.state.value.clubs.map { it.name })
        assertEquals("l", model.state.value.clubId)
        assertTrue("a captain with a club is not asked for a team name", !model.state.value.needsATeam)
    }

    /** `QuickMatchSheet.start()`: the same body iOS posts, field for field. */
    @Test
    fun `the quick start makes the fixture iOS makes`() = runTest(dispatcher.scheduler) {
        val server = Server(
            clubs = listOf(Club("l", "Lords CC")),
            perms = mapOf("l" to listOf("manage_events")),
            teams = mapOf("l" to listOf(Team("t2", "l", "2nd XI"))),
        )
        val model = StartMatchViewModel(server, now = { noon })
        model.load()
        advanceUntilIdle()
        model.selectTeam("t2")
        model.setOpposition("Hemel CC", hemel)
        model.setKind(MatchKind.League)
        model.start()
        advanceUntilIdle()

        val sent = server.fixtures.single()
        assertEquals("l", sent.clubId)
        assertEquals("hemel", sent.opponentClubId)
        assertEquals("t2", sent.teamId)
        assertEquals("cricket", sent.sport)
        assertEquals("league_match", sent.eventSubtype)
        assertEquals("Lords CC 2nd XI v Hemel CC", sent.title)
        assertEquals("2026-11-14T12:00:00Z", sent.startAt)
        assertEquals("2026-11-14T16:00:00Z", sent.endAt)
        assertEquals(22, sent.capacity)
        assertEquals(mapOf("opposition" to "Hemel CC", "home_name" to "Lords CC 2nd XI"), sent.metadata)
        assertEquals("event-1", model.state.value.startedEventId)
    }

    @Test
    fun `you cannot play your own club, and you must say who you are playing`() = runTest(dispatcher.scheduler) {
        val server = Server(clubs = listOf(Club("l", "Lords CC")), perms = mapOf("l" to listOf("manage_events")))
        val model = StartMatchViewModel(server)
        model.load()
        advanceUntilIdle()

        assertEquals("who you are playing", model.state.value.missing)
        model.setOpposition("Lords CC", ClubIdentity(id = "l", name = "Lords CC", clubId = "l"))
        assertEquals("an opposition that is not your own club", model.state.value.missing)
        model.start()
        advanceUntilIdle()
        assertTrue("nothing is made while something is missing", server.fixtures.isEmpty())
    }

    /**
     * The owner's case: somebody who registered a minute ago, with no club,
     * types their team's name and is scoring — no detour through a club form.
     */
    @Test
    fun `a player with no club names their team and the club, then the fixture, is made`() = runTest(dispatcher.scheduler) {
        val server = Server(clubs = emptyList())
        val model = StartMatchViewModel(server, now = { noon })
        model.load()
        advanceUntilIdle()

        assertTrue(model.state.value.needsATeam)
        assertEquals("your team's name", model.state.value.missing)

        model.setNewTeamName("  Gully Kings ")
        model.setOpposition("Southall Strikers", null)
        model.start()
        advanceUntilIdle()

        val club = server.madeClubs.single()
        assertEquals("Gully Kings", club.name)
        assertEquals(listOf("cricket"), club.sportTypes)
        assertTrue(club.isInformalGroup)
        assertEquals("invite_only", club.visibility)

        val fixture = server.fixtures.single()
        assertEquals("new-club", fixture.clubId)
        assertNull(fixture.teamId)
        assertNull(fixture.opponentClubId)
        assertEquals("Gully Kings v Southall Strikers", fixture.title)
        assertEquals("event-1", model.state.value.startedEventId)
    }

    /** Clubs where you are only a member count as none: you cannot put a fixture in them. */
    @Test
    fun `clubs you cannot make a fixture in count as no club`() = runTest(dispatcher.scheduler) {
        val server = Server(clubs = listOf(Club("a", "Ashford CC")), perms = mapOf("a" to listOf("view_club")))
        val model = StartMatchViewModel(server)
        model.load()
        advanceUntilIdle()
        assertTrue(model.state.value.needsATeam)
    }

    @Test
    fun `a fixture that fails does not make a second club on the retry`() = runTest(dispatcher.scheduler) {
        var failNext = true
        val server = object : Server() {
            override suspend fun createEvent(body: NewFixture): CreatedFixture {
                if (failNext) {
                    failNext = false
                    throw java.io.IOException("no signal")
                }
                return super.createEvent(body)
            }
        }
        val model = StartMatchViewModel(server)
        model.load()
        advanceUntilIdle()
        model.setNewTeamName("Gully Kings")
        model.setOpposition("Southall", null)
        model.start()
        advanceUntilIdle()
        assertNotNull(model.state.value.error)
        assertNull(model.state.value.startedEventId)

        model.start()
        advanceUntilIdle()
        assertEquals(1, server.madeClubs.size)
        assertEquals("new-club", server.fixtures.single().clubId)
        assertEquals("event-1", model.state.value.startedEventId)
    }

    /**
     * A server that asks for a confirmed contact refuses the club. The player
     * sees the server's words and confirms in place, and the match carries on.
     */
    @Test
    fun `an unverified account confirms in place and carries straight on`() = runTest(dispatcher.scheduler) {
        var verified = false
        var handedBack: PublicUser? = null
        val sentCodes = mutableListOf<String>()
        val server = object : Server() {
            override suspend fun createClub(body: NewClub): Club {
                if (!verified) {
                    throw refused(403, "confirm your email or phone number first — it takes a minute", "unverified")
                }
                return super.createClub(body)
            }
            override suspend fun sendCode(channel: String): JsonElement {
                sentCodes += channel
                return buildJsonObject { put("sent_to", "s•••@example.com"); put("expires_in", 600) }
            }
            override suspend fun confirmCode(channel: String, body: ConfirmCode): PublicUser {
                assertEquals("123456", body.code)
                verified = true
                return PublicUser(id = "u1", name = "Sunny")
            }
        }
        val model = StartMatchViewModel(server, verifyChannel = "email", onVerified = { handedBack = it })
        model.load()
        advanceUntilIdle()
        model.setNewTeamName("Gully Kings")
        model.setOpposition("Southall", null)
        model.start()
        advanceUntilIdle()

        val v = model.state.value.verification
        assertNotNull("the refusal is shown, not swallowed", v)
        assertEquals("Confirm your email or phone number first — it takes a minute", v!!.message)
        assertEquals("POST /clubs", v.refusedBy)
        assertEquals("email", v.channel)
        assertTrue(server.fixtures.isEmpty())

        model.sendCode()
        advanceUntilIdle()
        assertEquals(listOf("email"), sentCodes)
        assertEquals("s•••@example.com", model.state.value.verification?.sentTo)

        model.setCode("12 34 56")
        model.confirmCode()
        advanceUntilIdle()

        assertEquals("u1", handedBack?.id)
        assertNull(model.state.value.verification)
        assertEquals("Gully Kings", server.madeClubs.single().name)
        assertEquals("event-1", model.state.value.startedEventId)
    }

    /**
     * The app's JSON leaves out a field equal to its default. A request body
     * with a default would never send it — `is_informal_group: true` included.
     */
    @Test
    fun `the club body carries every field through the app's own encoder`() {
        val appJson = Json { ignoreUnknownKeys = true; explicitNulls = false }
        val encoded = appJson.encodeToJsonElement(
            NewClub.serializer(),
            NewClub("Gully Kings", listOf("cricket"), isInformalGroup = true, visibility = "invite_only"),
        ).jsonObject
        assertEquals(JsonPrimitive(true), encoded["is_informal_group"])
        assertEquals(JsonPrimitive("invite_only"), encoded["visibility"])
    }
}
