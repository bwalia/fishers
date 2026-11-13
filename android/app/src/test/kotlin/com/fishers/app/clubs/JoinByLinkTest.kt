package com.fishers.app.clubs

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.JoinByLinkState.Stage
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

/**
 * An invite link opened in the app says what the website's invite page says,
 * refusal for refusal — `web/src/app/invite/[token]/page.tsx`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class JoinByLinkTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val json = Json { ignoreUnknownKeys = true }

    private val clubLink = InvitePreview(
        targetType = "club", targetId = "c1", clubId = "c1", clubName = "Southall Strikers",
        invitedByName = "Ravi", open = true, usable = true,
    )

    private fun api(
        preview: InvitePreview? = clubLink,
        accept: () -> ClubInvite = { ClubInvite("i1", "club", "c1", "tok") },
    ) = object : FakeClubsApi() {
        var accepted = 0
        override suspend fun invitePreview(token: String) = preview ?: throw refused(404, "invite not found")
        override suspend fun acceptInvite(token: String): ClubInvite {
            accepted++
            return accept()
        }
    }

    @Test
    fun `a live link says what it is to and waits for Join`() = runTest(dispatcher.scheduler) {
        val api = api()
        val model = JoinByLinkViewModel(api, "tok")
        model.load()
        advanceUntilIdle()

        assertEquals(Stage.Ready, model.state.value.stage)
        assertEquals("Southall Strikers", model.state.value.preview?.joining)
        assertEquals("nothing is joined until somebody taps", 0, api.accepted)
    }

    @Test
    fun `an invite to a team names the team and the club`() {
        val preview = clubLink.copy(targetType = "team", targetId = "t1", teamName = "1st XI", open = false)
        assertEquals("1st XI · Southall Strikers", preview.joining)
    }

    @Test
    fun `a spent invite is dead before anybody taps anything`() = runTest(dispatcher.scheduler) {
        val model = JoinByLinkViewModel(api(clubLink.copy(open = false, usable = false)), "tok")
        model.load()
        advanceUntilIdle()

        with(model.state.value) {
            assertEquals(Stage.Failed, stage)
            assertEquals("This invite has already been used.", error)
            assertEquals("An invite can only be used once. Ask whoever sent it for a fresh one.", advice)
        }
    }

    @Test
    fun `a club link that was turned off says so, and to ask for the current one`() = runTest(dispatcher.scheduler) {
        val model = JoinByLinkViewModel(api(clubLink.copy(usable = false)), "tok")
        model.load()
        advanceUntilIdle()

        with(model.state.value) {
            assertEquals(Stage.Failed, stage)
            assertEquals("The club has turned this link off.", error)
            assertEquals("Ask the club for its current link.", advice)
        }
    }

    @Test
    fun `a token that leads nowhere could not be used`() = runTest(dispatcher.scheduler) {
        val model = JoinByLinkViewModel(api(preview = null), "nope")
        model.load()
        advanceUntilIdle()
        assertEquals(Stage.Failed, model.state.value.stage)
        assertEquals("That invite could not be used.", model.state.value.error)
    }

    @Test
    fun `joining through a club link lands in that club`() = runTest(dispatcher.scheduler) {
        val model = JoinByLinkViewModel(api(), "tok")
        model.load()
        advanceUntilIdle()
        model.join()
        advanceUntilIdle()

        assertEquals(Stage.Joined, model.state.value.stage)
        assertEquals(JoinByLinkState.Joined("c1", "Southall Strikers", null), model.state.value.joined)
    }

    @Test
    fun `joining a team lands in its club, and a fixture invite in the fixture`() = runTest(dispatcher.scheduler) {
        val team = JoinByLinkViewModel(
            api(clubLink.copy(targetType = "team", targetId = "t1")) { ClubInvite("i1", "team", "t1", "tok") },
            "tok",
        )
        val fixture = JoinByLinkViewModel(
            api(clubLink.copy(targetType = "event", targetId = "e1")) { ClubInvite("i2", "event", "e1", "tok") },
            "tok",
        )
        team.load()
        fixture.load()
        advanceUntilIdle()
        team.join()
        fixture.join()
        advanceUntilIdle()

        assertEquals("c1", team.state.value.joined?.clubId)
        assertNull(team.state.value.joined?.eventId)
        assertEquals("e1", fixture.state.value.joined?.eventId)
    }

    @Test
    fun `somebody the club removed is told why the open link will not let them back`() =
        runTest(dispatcher.scheduler) {
            val model = JoinByLinkViewModel(api(accept = {
                throw refused(403, "The club removed you, so its open link can't let you back in.", "removed_from_club")
            }), "tok")
            model.load()
            advanceUntilIdle()
            model.join()
            advanceUntilIdle()

            assertEquals(Stage.Failed, model.state.value.stage)
            assertEquals(
                "The club removed you, so its open link can't let you back in. Ask the secretary to invite you.",
                model.state.value.error,
            )
        }

    /** Confirming is a step, not a dead link: the same Join works afterwards. */
    @Test
    fun `an unconfirmed account is asked to confirm and keeps the Join button`() = runTest(dispatcher.scheduler) {
        val model = JoinByLinkViewModel(api(accept = {
            throw refused(403, "confirm your email or phone number first — it takes a minute", "unverified")
        }), "tok")
        model.load()
        advanceUntilIdle()
        model.join()
        advanceUntilIdle()

        with(model.state.value) {
            assertEquals(Stage.Ready, stage)
            assertTrue(needsVerifying)
            assertEquals("confirm your email or phone number first — it takes a minute", error)
        }
    }

    @Test
    fun `a link spent between opening and joining says so in the server's words`() = runTest(dispatcher.scheduler) {
        val model = JoinByLinkViewModel(api(accept = {
            throw refused(404, "This invite has already been used or was turned off")
        }), "tok")
        model.load()
        advanceUntilIdle()
        model.join()
        advanceUntilIdle()

        assertEquals(Stage.Failed, model.state.value.stage)
        assertEquals("This invite has already been used or was turned off", model.state.value.error)
    }

    @Test
    fun `no signal is not a dead link — Join can be tapped again`() = runTest(dispatcher.scheduler) {
        val model = JoinByLinkViewModel(api(accept = { throw IOException("offline") }), "tok")
        model.load()
        advanceUntilIdle()
        model.join()
        advanceUntilIdle()

        with(model.state.value) {
            assertEquals(Stage.Ready, stage)
            assertFalse(needsVerifying)
            assertTrue(error!!.contains("connection"))
        }
    }

    @Test
    fun `the preview decodes as the server sends it`() {
        val preview = json.decodeFromString<InvitePreview>(
            """{"target_type":"club","target_id":"c1","club_id":"c1","club_name":"Southall Strikers",
               "team_name":null,"event_title":null,"invited_by_name":"Ravi","open":true,"usable":false}""",
        )
        assertEquals("Southall Strikers", preview.joining)
        assertTrue(preview.open)
        assertFalse(preview.usable)
    }

    @Test
    fun `a refusal is read for its words and its code, and only once`() {
        val error = refused(403, "nope", "removed_from_club")
        val refusal = refusalOf(error)!!
        assertEquals(403, refusal.status)
        assertEquals("removed_from_club", refusal.code)
        assertEquals("nope", refusal.message)
        assertEquals("the words already read are passed on", "nope", saidWhy(error, refusal))
        assertNull("not a refusal at all", refusalOf(IOException("offline")))
    }
}
