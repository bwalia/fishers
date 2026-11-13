package com.fishers.app.clubs

import com.fishers.app.EnglishStrings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.io.IOException
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class ClubPageTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

    private val secretary = ClubRoleInfo(
        role = UserRole.ClubAdmin,
        isSecretary = true,
        isCaptain = true,
        canScoreMatch = true,
        permissions = listOf("manage_club_ops", "manage_events", "invite_to_club", "score_match"),
    )
    private val member = ClubRoleInfo(role = UserRole.Member, permissions = listOf("view_club", "respond_as_player"))

    /** A club that answers everything, with what each test wants to vary. */
    private open inner class ClubApi(
        val role: ClubRoleInfo? = secretary,
        val sports: List<String> = listOf("cricket"),
        val people: List<ClubMemberDetail> = listOf(ClubMemberDetail("me", "Ravi", role = UserRole.ClubAdmin)),
        val sides: List<Team> = emptyList(),
        val grounds: List<Venue> = emptyList(),
    ) : FakeClubsApi() {
        var fixturesFrom: String? = null
        var teamsAsked = 0
        override suspend fun club(clubId: String) = Club(clubId, "Lords CC", sports)
        override suspend fun myRole(clubId: String) = role ?: throw IOException("down")
        override suspend fun members(clubId: String) = people
        override suspend fun teams(clubId: String): List<Team> {
            teamsAsked++
            return sides
        }
        override suspend fun venues(clubId: String) = grounds
        override suspend fun clubFixtures(clubId: String, from: String?, perPage: Int): ClubFixturePage {
            fixturesFrom = from
            return ClubFixturePage(
                listOf(
                    ClubFixture("e2", "Sunday social", "2026-11-15T11:00:00Z"),
                    ClubFixture("e1", "Saturday league", "2026-11-14T13:00:00Z"),
                ),
            )
        }
    }

    private val now = Instant.parse("2026-11-13T12:00:00Z")

    @Test
    fun `a page that loads has the club, its sides and its fixtures in date order`() = runTest(dispatcher.scheduler) {
        val api = ClubApi(sides = listOf(Team("t2", "c1", "Sunday XI"), Team("t1", "c1", "1st XI")))
        val model = ClubPageViewModel(api, "c1") { now }
        model.load()
        advanceUntilIdle()

        val state = model.state.value
        assertEquals("Lords CC", state.club?.name)
        assertEquals(listOf("1st XI", "Sunday XI"), state.teams.map { it.name })
        assertEquals(listOf("Saturday league", "Sunday social"), state.fixtures.map { it.title })
        // From yesterday: this morning's match is still the one people look for.
        assertEquals("2026-11-12T12:00:00Z", api.fixturesFrom)
        assertNull(state.error)
    }

    @Test
    fun `the buttons follow what the server says this person may do`() = runTest(dispatcher.scheduler) {
        val asSecretary = ClubPageViewModel(ClubApi(role = secretary), "c1") { now }
        asSecretary.load()
        val asMember = ClubPageViewModel(ClubApi(role = member), "c1") { now }
        asMember.load()
        val asFootballSecretary = ClubPageViewModel(ClubApi(role = secretary, sports = listOf("football")), "c1") { now }
        asFootballSecretary.load()
        advanceUntilIdle()

        with(asSecretary.state.value) {
            assertTrue(canStartMatch)
            assertTrue(runsClubOps)
            assertTrue(managesEvents)
        }
        with(asMember.state.value) {
            assertFalse(canStartMatch)
            assertFalse(runsClubOps)
            assertFalse(managesEvents)
            assertFalse("a member is never shown the checklist", setupLeft)
        }
        assertFalse("the scorer is cricket's", asFootballSecretary.state.value.canStartMatch)
    }

    @Test
    fun `a club that cannot be read says why, and a section that cannot is just empty`() = runTest(dispatcher.scheduler) {
        val refusedClub = ClubPageViewModel(object : ClubApi() {
            override suspend fun club(clubId: String): Club = throw refused(403, "you are not a member of this club")
        }, "c1") { now }
        refusedClub.load()

        val noGrounds = ClubPageViewModel(object : ClubApi() {
            override suspend fun venues(clubId: String): List<Venue> = throw IOException("down")
        }, "c1") { now }
        noGrounds.load()
        advanceUntilIdle()

        assertEquals("you are not a member of this club", refusedClub.state.value.error)
        assertNull(refusedClub.state.value.club)
        assertFalse(refusedClub.state.value.isFirstLoad)

        assertNull(noGrounds.state.value.error)
        assertEquals("Lords CC", noGrounds.state.value.club?.name)
        assertTrue(noGrounds.state.value.venues.isEmpty())
    }

    /**
     * Ticked from what exists, never from what was tapped. Somebody invited
     * and not yet in does not make the club two people.
     */
    @Test
    fun `the setup checklist ticks itself off from what the club has`() = runTest(dispatcher.scheduler) {
        val model = ClubPageViewModel(ClubApi(
            people = listOf(
                ClubMemberDetail("me", "Ravi", role = UserRole.ClubAdmin),
                ClubMemberDetail("h", "Hopeful Hannah", status = MembershipStatus.Invited),
            ),
            grounds = listOf(Venue("v1", "Highbury Fields")),
        ), "c1") { now }
        model.load()
        advanceUntilIdle()

        val done = model.state.value.setup.associate { it.kind to it.done }
        assertEquals(1, model.state.value.members.size)
        assertEquals(false, done[SetupStep.Kind.Players])
        assertEquals(false, done[SetupStep.Kind.Team])
        assertEquals(false, done[SetupStep.Kind.Captain])
        assertEquals(true, done[SetupStep.Kind.Ground])
        assertTrue(model.state.value.setupLeft)
    }

    @Test
    fun `a secretary who captains counts as the club having a captain`() = runTest(dispatcher.scheduler) {
        val model = ClubPageViewModel(ClubApi(
            people = listOf(
                ClubMemberDetail("me", "Ravi", role = UserRole.ClubAdmin, isCaptain = true),
                ClubMemberDetail("2", "Tom"),
            ),
            sides = listOf(Team("t1", "c1", "1st XI")),
            grounds = listOf(Venue("v1", "Highbury Fields")),
        ), "c1") { now }
        model.load()
        advanceUntilIdle()

        assertTrue(model.state.value.setup.all { it.done })
        assertFalse("nothing left, so nothing shown", model.state.value.setupLeft)
    }

    @Test
    fun `adding a team sends it tidied, then reads the club again`() = runTest(dispatcher.scheduler) {
        var sent: CreateTeamBody? = null
        val api = object : ClubApi() {
            override suspend fun createTeam(clubId: String, body: CreateTeamBody): Team {
                sent = body
                return Team("t1", clubId, body.name, body.sport)
            }
        }
        val model = ClubPageViewModel(api, "c1") { now }
        model.load()
        advanceUntilIdle()

        model.addTeam("  1st XI ", "cricket")
        advanceUntilIdle()

        assertEquals(CreateTeamBody("1st XI", "cricket"), sent)
        assertEquals("the form that asked can close", 1, model.state.value.saved)
        assertEquals("and the list is read again", 2, api.teamsAsked)
        assertFalse(model.state.value.isSaving)
    }

    @Test
    fun `a refused ground stays on the form with the server's words`() = runTest(dispatcher.scheduler) {
        val model = ClubPageViewModel(object : ClubApi() {
            override suspend fun createVenue(clubId: String, body: CreateVenueBody): Venue =
                throw refused(403, "you need manage_club_ops for that")
        }, "c1") { now }

        model.addGround("Highbury Fields", "  ")
        advanceUntilIdle()

        assertEquals("you need manage_club_ops for that", model.state.value.formError)
        assertEquals(0, model.state.value.saved)
        model.clearFormError()
        assertNull(model.state.value.formError)
    }

    @Test
    fun `a ground's blank address is left out`() = runTest(dispatcher.scheduler) {
        var sent: CreateVenueBody? = null
        val model = ClubPageViewModel(object : ClubApi() {
            override suspend fun createVenue(clubId: String, body: CreateVenueBody): Venue {
                sent = body
                return Venue("v1", body.name, body.address)
            }
        }, "c1") { now }
        model.addGround(" Highbury Fields ", "   ")
        advanceUntilIdle()
        assertEquals(CreateVenueBody("Highbury Fields", null), sent)
    }

    @Test
    fun `my-role decodes with the fields the page reads`() {
        val role = json.decodeFromString<ClubRoleInfo>(
            """{"role":"team_captain","display_name":"Team captain","is_secretary":false,
               "is_captain":true,"can_invite_to_play":true,"can_score_match":true,
               "permissions":["view_club","manage_events","score_match"],
               "is_owner":false,"is_treasurer":false,"can_open_accounts":false}""",
        )
        assertEquals(UserRole.TeamCaptain, role.role)
        assertTrue(role.scores)
        assertTrue(role.managesEvents)
        assertFalse(role.runsClubOps)
        assertFalse(role.invitesToClub)
    }

    /** `GET /clubs` sends the club flattened with what the asker is in it. */
    @Test
    fun `a club from the list carries the role and the counts`() {
        val club = json.decodeFromString<Club>(
            """{"id":"c1","name":"Lords CC","sport_types":["cricket"],"visibility":"public",
               "owner_id":"u1","description":null,"is_informal_group":false,
               "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z",
               "role":"club_admin","is_captain":true,"is_treasurer":false,
               "member_count":18,"team_count":2,"public_slug":null}""",
        )
        assertEquals(UserRole.ClubAdmin, club.role)
        assertEquals("Secretary & captain", club.roleLabel)
        assertEquals(18, club.memberCount)
        assertTrue(club.isPublic)
        assertTrue(club.playsCricket)
    }

    @Test
    fun `a page of fixtures decodes, and one called off says so`() {
        val page = json.decodeFromString<ClubFixturePage>(
            """{"items":[{"id":"e1","club_id":"c1","title":"Saturday league","event_subtype":"league_match",
               "start_at":"2026-11-14T13:00:00Z","end_at":"2026-11-14T18:00:00Z","status":"cancelled",
               "metadata":{}}],"total":1,"page":1,"per_page":50,"has_more":false}""",
        )
        val fixture = page.items.single()
        assertTrue(fixture.isOff)
        assertEquals("Sat 14 Nov, 13:00", fixture.whenText(java.time.ZoneOffset.UTC))
    }
}
