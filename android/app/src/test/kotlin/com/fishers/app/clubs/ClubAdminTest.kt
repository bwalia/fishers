package com.fishers.app.clubs

import com.fishers.app.EnglishStrings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
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
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ClubAdminTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val policy = ClubSettings("suggest", confirmLeadHours = 48, dropLeadHours = 24, feeChaseAfterHours = 24, feeChaseMaxReminders = 3)

    private open class Admin : FakeClubsApi() {
        val calls = mutableListOf<String>()
        var added: AddMemberBody? = null
        var role: RoleBody? = null
        var invited: CreateInviteBody? = null
        val saved = mutableListOf<ClubSettings>()
        override suspend fun addMember(clubId: String, body: AddMemberBody) {
            calls += "add"
            added = body
        }
        override suspend fun setRole(clubId: String, userId: String, body: RoleBody) {
            calls += "role:$userId"
            role = body
        }
        override suspend fun removeMember(clubId: String, userId: String) {
            calls += "remove:$userId"
        }
        override suspend fun createInvite(body: CreateInviteBody): ClubInvite {
            invited = body
            return ClubInvite("i1", "club", body.targetId, "tok123")
        }
        override suspend fun updateSettings(clubId: String, body: ClubSettings): ClubSettings {
            saved += body
            return body
        }
    }

    @Test
    fun `adding somebody sends what they signed up with and the role, then the roster is re-read`() =
        runTest(dispatcher.scheduler) {
            val api = Admin()
            val model = ClubAdminViewModel(api, "c1", "https://x")

            model.addMember("  +44 7700 900123 ", UserRole.TeamCaptain)
            advanceUntilIdle()

            assertEquals(AddMemberBody("+44 7700 900123", "team_captain"), api.added)
            assertEquals(1, model.state.value.changed)
            assertNull(model.state.value.error)
        }

    @Test
    fun `nothing typed is nothing sent`() = runTest(dispatcher.scheduler) {
        val api = Admin()
        val model = ClubAdminViewModel(api, "c1", "https://x")
        model.addMember("   ", UserRole.Member)
        advanceUntilIdle()
        assertTrue(api.calls.isEmpty())
    }

    /** The API's words are the whole answer here, and "HTTP 409" is not. */
    @Test
    fun `standing down the last secretary is refused in the server's words`() = runTest(dispatcher.scheduler) {
        val model = ClubAdminViewModel(object : Admin() {
            override suspend fun setRole(clubId: String, userId: String, body: RoleBody) =
                throw refused(409, "this is the club's last secretary — appoint another one first")
        }, "c1", "https://x")
        val ravi = ClubMemberDetail("u1", "Ravi", role = UserRole.ClubAdmin)

        model.setRole(ravi, RoleChoice(UserRole.Member))
        advanceUntilIdle()

        assertEquals("this is the club's last secretary — appoint another one first", model.state.value.error)
        assertEquals("the roster did not change, so it is not re-read", 0, model.state.value.changed)
        model.dismissError()
        assertNull(model.state.value.error)
    }

    @Test
    fun `nobody but a stranger to the club is told it could not find them`() = runTest(dispatcher.scheduler) {
        val model = ClubAdminViewModel(object : Admin() {
            override suspend fun addMember(clubId: String, body: AddMemberBody) =
                throw refused(404, "nobody with that email or number has a Fishers account yet")
        }, "c1", "https://x")
        model.addMember("someone@example.com", UserRole.Member)
        advanceUntilIdle()
        assertEquals("nobody with that email or number has a Fishers account yet", model.state.value.error)
    }

    @Test
    fun `a secretary who captains is sent as one, and a captain flag means nothing on anyone else`() =
        runTest(dispatcher.scheduler) {
            val api = Admin()
            val model = ClubAdminViewModel(api, "c1", "https://x")
            val tom = ClubMemberDetail("u2", "Tom")

            model.setRole(tom, RoleChoice(UserRole.ClubAdmin, isCaptain = true))
            advanceUntilIdle()
            assertEquals(RoleBody("club_admin", captain = true), api.role)

            model.setRole(tom, RoleChoice(UserRole.TeamViceCaptain, isCaptain = true))
            advanceUntilIdle()
            assertEquals(RoleBody("team_vice_captain", captain = false), api.role)
            assertEquals(2, model.state.value.changed)
        }

    @Test
    fun `choosing the role somebody already has sends nothing`() = runTest(dispatcher.scheduler) {
        val api = Admin()
        val model = ClubAdminViewModel(api, "c1", "https://x")
        val ravi = ClubMemberDetail("u1", "Ravi", role = UserRole.ClubAdmin, isCaptain = true)
        model.setRole(ravi, RoleChoice(UserRole.ClubAdmin, isCaptain = true))
        advanceUntilIdle()
        assertTrue(api.calls.isEmpty())
    }

    @Test
    fun `removing somebody re-reads the roster`() = runTest(dispatcher.scheduler) {
        val api = Admin()
        val model = ClubAdminViewModel(api, "c1", "https://x")
        model.remove(ClubMemberDetail("u9", "Gone Gary"))
        advanceUntilIdle()
        assertEquals(listOf("remove:u9"), api.calls)
        assertEquals(1, model.state.value.changed)
    }

    /**
     * A one-person link opens on the website, which is where the App Link
     * lands too. An address goes with it only when it is one: a mobile number
     * typed in the same box is not an email to look somebody up by.
     */
    @Test
    fun `a one-person invite makes a link on the site, with an address only when there is one`() =
        runTest(dispatcher.scheduler) {
            val api = Admin()
            val model = ClubAdminViewModel(api, "c1", "https://www.gullycricket.app/")

            model.makeInvite(" new@player.com ")
            advanceUntilIdle()
            assertEquals(CreateInviteBody("club", "c1", "new@player.com"), api.invited)
            assertEquals("https://www.gullycricket.app/invite/tok123", model.state.value.inviteUrl)

            model.makeInvite("07700 900123")
            advanceUntilIdle()
            assertNull(api.invited!!.invitedEmail)

            model.clearInvite()
            assertNull(model.state.value.inviteUrl)
        }

    @Test
    fun `loading reads the role, the policy and the fees, and a 403 on fees is no error`() =
        runTest(dispatcher.scheduler) {
            val model = ClubAdminViewModel(object : Admin() {
                override suspend fun myRole(clubId: String) = ClubRoleInfo(UserRole.Member)
                override suspend fun settings(clubId: String) = policy
                override suspend fun outstandingFees(clubId: String): OutstandingFees =
                    throw refused(403, "captains only")
            }, "c1", "https://x")
            model.load()
            advanceUntilIdle()

            val state = model.state.value
            assertEquals(policy, state.settings)
            assertNull(state.fees)
            assertNull(state.error)
            assertFalse(state.canManage)
            assertFalse(state.canChase)
        }

    /** A stepper fires on every press, and each press should not be a round trip. */
    @Test
    fun `quick changes to the policy are saved once, with the last values`() = runTest(dispatcher.scheduler) {
        val api = object : Admin() {
            override suspend fun myRole(clubId: String) = ClubRoleInfo(UserRole.ClubAdmin, isSecretary = true)
            override suspend fun settings(clubId: String) = policy
            override suspend fun outstandingFees(clubId: String) = OutstandingFees()
        }
        val model = ClubAdminViewModel(api, "c1", "https://x")
        model.load()
        advanceUntilIdle()

        model.changeSettings { it.copy(confirmLeadHours = it.confirmLeadHours + 6) }
        advanceTimeBy(100)
        model.changeSettings { it.copy(confirmLeadHours = it.confirmLeadHours + 6) }
        advanceTimeBy(100)
        model.changeSettings { it.copy(selectionAutonomy = "auto_publish") }
        assertEquals("shown at once", 60, model.state.value.settings!!.confirmLeadHours)
        assertTrue("not saved yet", api.saved.isEmpty())

        advanceUntilIdle()
        assertEquals(listOf(policy.copy(confirmLeadHours = 60, selectionAutonomy = "auto_publish")), api.saved)
    }

    @Test
    fun `the policy is held to what the server accepts`() = runTest(dispatcher.scheduler) {
        val api = object : Admin() {
            override suspend fun settings(clubId: String) = policy
            override suspend fun myRole(clubId: String) = ClubRoleInfo(UserRole.ClubAdmin, isSecretary = true)
            override suspend fun outstandingFees(clubId: String) = OutstandingFees()
        }
        val model = ClubAdminViewModel(api, "c1", "https://x", saveDelayMs = 0)
        model.load()
        advanceUntilIdle()

        model.changeSettings { it.copy(dropLeadHours = -6, feeChaseMaxReminders = 11, feeChaseAfterHours = 400) }
        advanceUntilIdle()

        val sent = api.saved.single()
        assertEquals(0, sent.dropLeadHours)
        assertEquals(10, sent.feeChaseMaxReminders)
        assertEquals(336, sent.feeChaseAfterHours)
    }

    @Test
    fun `a refused policy shows what is actually in force`() = runTest(dispatcher.scheduler) {
        val api = object : Admin() {
            override suspend fun settings(clubId: String) = policy
            override suspend fun myRole(clubId: String) = ClubRoleInfo(UserRole.Member)
            override suspend fun outstandingFees(clubId: String) = OutstandingFees()
            override suspend fun updateSettings(clubId: String, body: ClubSettings): ClubSettings =
                throw refused(403, "you need manage_club_ops for that")
        }
        val model = ClubAdminViewModel(api, "c1", "https://x", saveDelayMs = 0)
        model.load()
        advanceUntilIdle()

        model.changeSettings { it.copy(selectionAutonomy = "off") }
        advanceUntilIdle()

        assertEquals(policy, model.state.value.settings)
        assertEquals("you need manage_club_ops for that", model.state.value.error)
    }

    @Test
    fun `chasing fees says it went, and shows the counts after`() = runTest(dispatcher.scheduler) {
        var chased = false
        val owed = OutstandingFee("u1", "Tom", "e1", "Watford away", "2026-11-08T13:00:00Z", 1200, "GBP", 1)
        val model = ClubAdminViewModel(object : Admin() {
            override suspend fun chaseFees(clubId: String) {
                chased = true
            }
            override suspend fun outstandingFees(clubId: String) =
                OutstandingFees(1200, 1, listOf(owed.copy(remindersSent = if (chased) 2 else 1)))
        }, "c1", "https://x")

        model.chaseFees()
        advanceUntilIdle()

        assertTrue(chased)
        assertEquals("Reminders sent.", model.state.value.note)
        assertEquals(2, model.state.value.fees!!.owed.single().remindersSent)
        assertFalse(model.state.value.isChasing)
    }

    @Test
    fun `a fee reads in its own currency`() {
        assertEquals("£12.00", money(1200, "GBP"))
        assertEquals("₹600.00", money(60000, "INR"))
        assertEquals("no currency is the club's pounds", "£0.50", money(50, null))
    }
}
