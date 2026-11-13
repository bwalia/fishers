package com.fishers.app.profile

import com.fishers.app.EnglishStrings
import com.fishers.app.net.RoleIntentPatch
import com.fishers.app.onboarding.Gate
import com.fishers.app.onboarding.PendingInvite
import com.fishers.app.onboarding.PendingInvitesViewModel
import com.fishers.app.onboarding.QuickStartMemory
import com.fishers.app.onboarding.QuickStartViewModel
import com.fishers.app.onboarding.SportsOnOffer
import com.fishers.app.onboarding.VerificationChannel
import com.fishers.app.onboarding.VerificationCode
import com.fishers.app.onboarding.VerificationSent
import com.fishers.app.onboarding.VerificationStatus
import com.fishers.app.onboarding.VerifyViewModel
import com.fishers.app.session.RoleIntent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
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
import java.io.IOException

@OptIn(ExperimentalCoroutinesApi::class)
class OnboardingTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private class Memory(vararg past: String) : QuickStartMemory {
        val marked = past.toMutableSet()
        override fun isPast(userId: String) = userId in marked
        override fun markPast(userId: String) {
            marked += userId
        }
    }

    private val newcomer = Me(id = "u1", name = "Ravi Patel", email = "r@x.test")

    // ---- The quick start ----

    @Test
    fun `somebody past it on this phone goes straight in without a request`() = runTest(dispatcher.scheduler) {
        val model = QuickStartViewModel(FakeProfileApi(), Memory("u1"), "u1")

        assertEquals(Gate.Done, model.state.value.gate)
        model.check() // would reach /me, which the fake refuses loudly
        advanceUntilIdle()
        assertEquals(Gate.Done, model.state.value.gate)
    }

    @Test
    fun `a profile that already names a sport is past it on every phone`() = runTest(dispatcher.scheduler) {
        val memory = Memory()
        val model = QuickStartViewModel(object : FakeProfileApi() {
            override suspend fun me() = newcomer.copy(sportProfiles = listOf(SportProfile("cricket")))
        }, memory, "u1")

        model.check()
        advanceUntilIdle()

        assertEquals(Gate.Done, model.state.value.gate)
        assertTrue(memory.isPast("u1"))
    }

    @Test
    fun `no sport yet asks, and only asks what signing up did not`() = runTest(dispatcher.scheduler) {
        val model = QuickStartViewModel(object : FakeProfileApi() {
            override suspend fun me() = newcomer.copy(roleIntent = "player", phone = "07700 900123")
            override suspend fun offeredSports() = SportsOnOffer(offered = listOf("cricket"))
        }, Memory(), "u1")

        model.check()
        advanceUntilIdle()

        val state = model.state.value
        assertEquals(Gate.Ask, state.gate)
        assertEquals("Ravi", state.firstName)
        assertFalse("the role was asked on the sign-up form", state.asksRole)
        assertFalse("they gave a number", state.asksPhone)
        assertEquals(RoleIntent.Player, state.role)
        assertEquals(listOf(Sport.Cricket), state.offered)
        assertFalse("nothing picked, nothing to continue with", state.canContinue)
    }

    @Test
    fun `continuing saves the role, the sport and the number, then lets them in`() = runTest(dispatcher.scheduler) {
        var role: RoleIntentPatch? = null
        var update: ProfileUpdate? = null
        var handed: Me? = null
        val memory = Memory()
        val model = QuickStartViewModel(
            object : FakeProfileApi() {
                override suspend fun me() = newcomer
                override suspend fun offeredSports() = SportsOnOffer()
                override suspend fun setRoleIntent(body: RoleIntentPatch): Me {
                    role = body
                    return newcomer.copy(roleIntent = body.roleIntent)
                }
                override suspend fun updateProfile(body: ProfileUpdate): Me {
                    update = body
                    return newcomer.copy(sportProfiles = body.sportProfiles, primarySport = body.primarySport)
                }
            },
            memory, "u1", onUser = { handed = it },
        )
        model.check()
        advanceUntilIdle()

        model.pickRole(RoleIntent.Secretary)
        model.toggleSport(Sport.Cricket)
        model.toggleSport(Sport.Football)
        model.setPhone(" 07700 900123 ")
        model.finish()
        advanceUntilIdle()

        assertEquals("secretary", role?.roleIntent)
        assertEquals("Ravi Patel", update?.name)
        assertEquals(listOf("cricket", "football"), update?.sportsPlayed)
        assertEquals("cricket", update?.primarySport)
        assertEquals("07700 900123", update?.phone)
        assertEquals("cricket", handed?.primarySport)
        assertEquals(Gate.Done, model.state.value.gate)
        assertTrue(memory.isPast("u1"))
    }

    @Test
    fun `skipping still keeps the role they picked`() = runTest(dispatcher.scheduler) {
        var role: RoleIntentPatch? = null
        val memory = Memory()
        val model = QuickStartViewModel(object : FakeProfileApi() {
            override suspend fun me() = newcomer
            override suspend fun offeredSports() = SportsOnOffer()
            override suspend fun setRoleIntent(body: RoleIntentPatch): Me {
                role = body
                return newcomer
            }
        }, memory, "u1")
        model.check()
        advanceUntilIdle()

        model.pickRole(RoleIntent.Player)
        model.skip()
        advanceUntilIdle()

        assertEquals("player", role?.roleIntent)
        assertEquals(Gate.Done, model.state.value.gate)
        assertTrue(memory.isPast("u1"))
    }

    @Test
    fun `not being able to ask does not stand between somebody and the app`() = runTest(dispatcher.scheduler) {
        val memory = Memory()
        val model = QuickStartViewModel(object : FakeProfileApi() {
            override suspend fun me(): Me = throw IOException("offline")
        }, memory, "u1")

        model.check()
        advanceUntilIdle()

        assertEquals(Gate.Done, model.state.value.gate)
        assertFalse("asked again next launch", memory.isPast("u1"))
    }

    // ---- Invitations ----

    private fun invite(id: String, status: String = "pending", name: String? = "Lords CC") = PendingInvite(
        id = id, targetType = "club", targetId = "c1", token = "tok-$id", status = status,
        createdAt = "2026-11-12T10:00:00.123456Z", targetName = name, invitedByName = "Sam",
    )

    @Test
    fun `only invitations still waiting are listed`() = runTest(dispatcher.scheduler) {
        val model = PendingInvitesViewModel(object : FakeProfileApi() {
            override suspend fun myInvites() = listOf(invite("1"), invite("2", status = "accepted"), invite("3", name = null))
        })

        model.load()
        advanceUntilIdle()

        assertEquals(listOf("1", "3"), model.state.value.invites.map { it.id })
        assertEquals("A club invitation", model.state.value.invites.last().title)
    }

    @Test
    fun `accepting takes it off the list and refreshes the person`() = runTest(dispatcher.scheduler) {
        var accepted: String? = null
        var reloaded = false
        val model = PendingInvitesViewModel(
            object : FakeProfileApi() {
                override suspend fun myInvites() = listOf(invite("1"))
                override suspend fun acceptInvite(token: String) = emptyJson.also { accepted = token }
            },
            onAccepted = { reloaded = true },
        )
        model.load()
        advanceUntilIdle()

        model.accept(model.state.value.invites.single())
        advanceUntilIdle()

        assertEquals("tok-1", accepted)
        assertTrue(reloaded)
        assertTrue(model.state.value.invites.isEmpty())
    }

    @Test
    fun `an unconfirmed account is offered the way to confirm`() = runTest(dispatcher.scheduler) {
        val model = PendingInvitesViewModel(object : FakeProfileApi() {
            override suspend fun myInvites() = listOf(invite("1"))
            override suspend fun acceptInvite(token: String) =
                throw refusal(403, "confirm your email or phone number first — it takes a minute", "unverified")
        })
        model.load()
        advanceUntilIdle()

        model.accept(model.state.value.invites.single())
        advanceUntilIdle()

        val state = model.state.value
        assertTrue(state.needsVerification)
        assertEquals(
            "Starting a club and accepting an invite need a confirmed email address or phone number.",
            state.error,
        )
        assertEquals("the invite is still there afterwards", 1, state.invites.size)
        assertNull(state.busy)
    }

    @Test
    fun `somebody the club removed is told why, in the app's own words`() = runTest(dispatcher.scheduler) {
        val model = PendingInvitesViewModel(object : FakeProfileApi() {
            override suspend fun myInvites() = listOf(invite("1"))
            override suspend fun acceptInvite(token: String) = throw refusal(403, "removed", "removed_from_club")
        })
        model.load()
        advanceUntilIdle()

        model.accept(model.state.value.invites.single())
        advanceUntilIdle()

        assertFalse(model.state.value.needsVerification)
        assertTrue(model.state.value.error!!.startsWith("The club removed you"))
    }

    // ---- Confirming a contact ----

    private val both = VerificationStatus(
        enabled = true,
        email = VerificationStatus.Channel(address = "r@x.test", available = true),
        phone = VerificationStatus.Channel(address = "+447700900123", available = true),
        verificationRequired = true,
    )

    @Test
    fun `the seconds to wait are read from the server's sentence`() {
        assertEquals(42, VerifyViewModel.secondsToWait("a code is on its way — you can ask for another in 42s"))
        assertNull(VerifyViewModel.secondsToWait("too many codes this hour — try again later"))
    }

    @Test
    fun `a full code confirms itself`() = runTest(dispatcher.scheduler) {
        var sent: Pair<String, String>? = null
        var verified: Me? = null
        val model = VerifyViewModel(object : FakeProfileApi() {
            override suspend fun verificationStatus() = both
            override suspend fun confirmVerification(channel: String, body: VerificationCode): Me {
                sent = channel to body.code
                return Me(id = "u1", name = "Ravi", emailVerified = true)
            }
        }, onVerified = { verified = it })
        model.load()
        advanceUntilIdle()
        assertEquals(VerificationChannel.Email, model.state.value.channel)

        model.typeCode("12a34")
        advanceUntilIdle()
        assertNull("five digits do not go up", sent)

        model.typeCode("1234567")
        advanceUntilIdle()

        assertEquals("email" to "123456", sent)
        assertTrue(verified!!.isVerified)
        assertTrue(model.state.value.verified)
    }

    @Test
    fun `asking again too soon becomes a countdown, not an error`() = runTest(dispatcher.scheduler) {
        val model = VerifyViewModel(object : FakeProfileApi() {
            override suspend fun verificationStatus() = both
            override suspend fun sendVerificationCode(channel: String): VerificationSent =
                throw refusal(429, "a code is on its way — you can ask for another in 3s")
        })
        model.load()
        advanceUntilIdle()

        model.send()
        runCurrent()
        assertEquals(3, model.state.value.wait)
        assertNull(model.state.value.error)

        advanceTimeBy(3_100)
        assertEquals(0, model.state.value.wait)
    }

    @Test
    fun `a new code says where it went`() = runTest(dispatcher.scheduler) {
        val model = VerifyViewModel(object : FakeProfileApi() {
            override suspend fun verificationStatus() = both
            override suspend fun sendVerificationCode(channel: String) = VerificationSent(sentTo = "+44••••0123", resendAfter = 60)
        })
        model.load()
        advanceUntilIdle()

        model.selectChannel(VerificationChannel.Phone)
        model.send()
        runCurrent()

        assertEquals("New code sent on WhatsApp to +44••••0123.", model.state.value.note)
        assertEquals(60, model.state.value.wait)
    }

    @Test
    fun `a wrong code clears the field and says so`() = runTest(dispatcher.scheduler) {
        val model = VerifyViewModel(object : FakeProfileApi() {
            override suspend fun verificationStatus() = both
            override suspend fun confirmVerification(channel: String, body: VerificationCode): Me =
                throw refusal(400, "that code is not right — 4 more tries")
        })
        model.load()
        advanceUntilIdle()

        model.typeCode("000000")
        advanceUntilIdle()

        assertEquals("", model.state.value.code)
        assertEquals("That code is not right — 4 more tries", model.state.value.error)
        assertFalse(model.state.value.verified)
    }
}
