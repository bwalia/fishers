package com.fishers.app.profile

import com.fishers.app.EnglishStrings
import com.fishers.app.onboarding.ShareLinkToken
import com.fishers.app.onboarding.SportsOnOffer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import okhttp3.MultipartBody
import okio.Buffer
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
class ProfileViewModelsTest {
    @get:Rule val english = EnglishStrings()

    // One scheduler for the dispatcher and runTest — see ClubsTest for why.
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val ravi = Me(
        id = "u1",
        name = "Ravi Patel",
        primarySport = "cricket",
        sportProfiles = listOf(SportProfile(sport = "cricket", skillLevel = "Beginner")),
    )

    // ---- Edit profile ----

    @Test
    fun `the edit form opens filled in from the server`() = runTest(dispatcher.scheduler) {
        val model = EditProfileViewModel(object : FakeProfileApi() {
            override suspend fun me() = ravi
            override suspend fun offeredSports() = SportsOnOffer(offered = listOf("cricket"))
        })

        model.load()
        advanceUntilIdle()

        val state = model.state.value
        assertEquals("Ravi Patel", state.form.name)
        assertEquals(listOf(Sport.Cricket), state.form.selectedSports)
        // Gully Cricket offers cricket only: that is the whole picker.
        assertEquals(listOf(Sport.Cricket), state.sportsShown)
        assertTrue(state.canSave)
    }

    @Test
    fun `saving sends the form and hands back the user the server returned`() = runTest(dispatcher.scheduler) {
        var sent: ProfileUpdate? = null
        var handed: Me? = null
        val model = EditProfileViewModel(
            object : FakeProfileApi() {
                override suspend fun me() = ravi
                override suspend fun offeredSports() = throw IOException("offline")
                override suspend fun updateProfile(body: ProfileUpdate): Me {
                    sent = body
                    return ravi.copy(name = body.name)
                }
            },
            onSaved = { handed = it },
        )
        model.load()
        advanceUntilIdle()

        model.edit { f -> f.copy(name = "  Ravi P  ").mutate(Sport.Cricket) { it.copy(position = "Spinner") } }
        model.save()
        advanceUntilIdle()

        assertEquals("Ravi P", sent?.name)
        assertEquals("Spinner", sent?.positionRole)
        assertEquals("Ravi P", handed?.name)
        assertTrue(model.state.value.saved)
        // An unreadable /sports leaves every sport on offer, not none.
        assertEquals(Sport.entries.size, model.state.value.offered.size)
    }

    @Test
    fun `a nameless profile is not sent`() = runTest(dispatcher.scheduler) {
        val model = EditProfileViewModel(object : FakeProfileApi() {
            override suspend fun me() = ravi
            override suspend fun offeredSports() = SportsOnOffer()
        })
        model.load()
        advanceUntilIdle()

        model.edit { it.copy(name = "   ") }
        model.save() // would reach updateProfile, which the fake refuses loudly
        advanceUntilIdle()

        assertFalse(model.state.value.canSave)
        assertFalse(model.state.value.saved)
    }

    @Test
    fun `a refused save says what the server said and stays open`() = runTest(dispatcher.scheduler) {
        val model = EditProfileViewModel(object : FakeProfileApi() {
            override suspend fun me() = ravi
            override suspend fun offeredSports() = SportsOnOffer()
            override suspend fun updateProfile(body: ProfileUpdate): Me = throw refusal(400, "name: must be 1 to 120 characters")
        })
        model.load()
        advanceUntilIdle()

        model.save()
        advanceUntilIdle()

        assertEquals("Name: must be 1 to 120 characters", model.state.value.error)
        assertFalse(model.state.value.saved)
        assertFalse(model.state.value.isSaving)
    }

    // ---- Your own page ----

    @Test
    fun `a new photo goes up as a file part and reaches the rest of the app`() = runTest(dispatcher.scheduler) {
        var part: MultipartBody.Part? = null
        var handed: Me? = null
        val model = ProfileViewModel(
            object : FakeProfileApi() {
                override suspend fun uploadAvatar(file: MultipartBody.Part): Me {
                    part = file
                    return ravi.copy(avatarUrl = "https://cdn/a.jpg")
                }
            },
            webBase = "https://www.gullycricket.app",
            onUser = { handed = it },
        )
        val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0x00)

        model.uploadPhoto(jpeg)
        advanceUntilIdle()

        assertEquals("https://cdn/a.jpg", model.state.value.me?.avatarUrl)
        assertEquals("https://cdn/a.jpg", handed?.avatarUrl)
        val disposition = part!!.headers!!["Content-Disposition"]!!
        assertTrue(disposition, disposition.contains("name=\"file\""))
        assertEquals("image/jpeg", part!!.body.contentType().toString())
        assertEquals(4L, Buffer().also { part!!.body.writeTo(it) }.size)
    }

    @Test
    fun `a photo the server turns down says why`() = runTest(dispatcher.scheduler) {
        val model = ProfileViewModel(object : FakeProfileApi() {
            override suspend fun uploadAvatar(file: MultipartBody.Part): Me = throw refusal(400, "that picture is over 2MB")
        }, webBase = "https://x")

        model.uploadPhoto(byteArrayOf(1, 2, 3))
        advanceUntilIdle()

        assertEquals("That picture is over 2MB", model.state.value.photoError)
        assertFalse(model.state.value.photoBusy)
    }

    @Test
    fun `the profile link opens on the website`() = runTest(dispatcher.scheduler) {
        val model = ProfileViewModel(object : FakeProfileApi() {
            override suspend fun shareLink() = ShareLinkToken("abc123")
        }, webBase = "https://www.gullycricket.app/")

        model.makeShareLink()
        advanceUntilIdle()

        assertEquals("https://www.gullycricket.app/p/abc123", model.state.value.shareLink)
    }

    @Test
    fun `no season on record is not an error`() = runTest(dispatcher.scheduler) {
        val model = ProfileViewModel(object : FakeProfileApi() {
            override suspend fun me() = ravi
            override suspend fun myStats(): MeStats = throw refusal(404, "no stats")
        }, webBase = "https://x")

        model.load()
        advanceUntilIdle()

        assertEquals(ravi, model.state.value.me)
        assertNull(model.state.value.error)
        assertTrue(model.state.value.seasons.isEmpty())
    }

    // ---- Somebody else ----

    @Test
    fun `somebody you share no club with reads as a plain sentence`() = runTest(dispatcher.scheduler) {
        val model = PlayerProfileViewModel(object : FakeProfileApi() {
            override suspend fun teammate(userId: String): TeammateProfile = throw refusal(403, "not in a shared club")
        }, "u2")

        model.load()
        advanceUntilIdle()

        assertEquals("Could not load this player.", model.state.value.error)
        assertFalse(model.state.value.isLoading)
    }

    @Test
    fun `a teammate's seasons come newest first, and missing honours are no error`() = runTest(dispatcher.scheduler) {
        val model = PlayerProfileViewModel(object : FakeProfileApi() {
            override suspend fun teammate(userId: String) = TeammateProfile(id = userId, name = "Amy Best", sharedClubs = listOf("Lords CC"))
            override suspend fun playerSeasons(userId: String) = listOf(
                PlayerSeasonStats(id = "a", seasonYear = 2024, runs = 10),
                PlayerSeasonStats(id = "b", seasonYear = 2026, runs = 30),
            )
            override suspend fun playerAchievements(userId: String): List<UserAchievement> = throw IOException("offline")
        }, "u2")

        model.load()
        advanceUntilIdle()

        val state = model.state.value
        assertEquals("Amy Best", state.player?.name)
        assertEquals(listOf(2026, 2024), state.seasons.map { it.seasonYear })
        assertEquals(40, state.totals.runs)
        assertTrue(state.honours.isEmpty())
        assertNull(state.error)
    }
}
