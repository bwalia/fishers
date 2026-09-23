package com.fishers.app.clubs

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
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.IOException

@OptIn(ExperimentalCoroutinesApi::class)
class ClubsTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun member(
        id: String,
        name: String,
        role: UserRole = UserRole.Member,
        captain: Boolean = false,
        status: MembershipStatus = MembershipStatus.Active,
    ) = ClubMemberDetail(
        userId = id, name = name, role = role, isCaptain = captain, status = status,
    )

    @Test
    fun `clubs are listed alphabetically, ignoring case`() = runTest {
        val model = ClubsViewModel(object : FakeFishersApi() {
            override suspend fun myClubs() = listOf(
                Club("1", "wickham CC"),
                Club("2", "Ashford CC"),
                Club("3", "Lords CC"),
            )
        })

        model.load()
        advanceUntilIdle()

        assertEquals(
            listOf("Ashford CC", "Lords CC", "wickham CC"),
            model.state.value.clubs.map { it.name },
        )
    }

    /**
     * The order somebody scans when they are working out who to ask: whoever
     * runs the club, then whoever captains, then everybody else.
     */
    @Test
    fun `the roster puts the people you would ask at the top`() = runTest {
        val model = ClubDetailViewModel(object : FakeFishersApi() {
            override suspend fun clubMembers(id: String) = listOf(
                member("1", "Zoe Adams"),
                member("2", "Tom Hardy", captain = true),
                member("3", "Ravi Patel", role = UserRole.ClubAdmin),
                member("4", "Amy Best"),
            )
            override suspend fun clubTeams(id: String) = emptyList<Team>()
        }, "c1")

        model.load()
        advanceUntilIdle()

        assertEquals(
            listOf("Ravi Patel", "Tom Hardy", "Amy Best", "Zoe Adams"),
            model.state.value.members.map { it.name },
        )
    }

    /**
     * Somebody who was asked and has not answered is not in the side. A roster
     * that counts them is a roster that is wrong on a Saturday, so they are
     * listed apart rather than among the people who are actually available.
     */
    @Test
    fun `people who never answered are kept out of the count`() = runTest {
        val model = ClubDetailViewModel(object : FakeFishersApi() {
            override suspend fun clubMembers(id: String) = listOf(
                member("1", "Ravi Patel"),
                member("2", "Hopeful Hannah", status = MembershipStatus.Invited),
                member("3", "Gone Gary", status = MembershipStatus.Left),
            )
            override suspend fun clubTeams(id: String) = emptyList<Team>()
        }, "c1")

        model.load()
        advanceUntilIdle()

        assertEquals(listOf("Ravi Patel"), model.state.value.onTheBooks.map { it.name })
        assertEquals(listOf("Hopeful Hannah"), model.state.value.invited.map { it.name })
    }

    /**
     * Teams are a nicety; the roster is why somebody opened the screen.
     * Losing the teams must not empty it.
     */
    @Test
    fun `the roster survives the teams call failing`() = runTest {
        val model = ClubDetailViewModel(object : FakeFishersApi() {
            override suspend fun clubMembers(id: String) = listOf(member("1", "Ravi Patel"))
            override suspend fun clubTeams(id: String): List<Team> = throw IOException("down")
        }, "c1")

        model.load()
        advanceUntilIdle()

        assertEquals(1, model.state.value.members.size)
        assertTrue(model.state.value.teams.isEmpty())
        assertNull("and says nothing about it", model.state.value.error)
    }

    @Test
    fun `a roster that will not load says why`() = runTest {
        val model = ClubDetailViewModel(object : FakeFishersApi() {
            override suspend fun clubMembers(id: String): List<ClubMemberDetail> =
                throw IOException("offline")
            override suspend fun clubTeams(id: String) = emptyList<Team>()
        }, "c1")

        model.load()
        advanceUntilIdle()

        assertTrue(model.state.value.error!!.contains("connection"))
    }

    @Test
    fun `roles read as a club would say them, not as the database spells them`() {
        assertEquals("Secretary", UserRole.ClubAdmin.label)
        assertEquals("Vice captain", UserRole.TeamViceCaptain.label)
        assertTrue(UserRole.ClubAdmin.runsTheClub)
        assertTrue(!UserRole.TeamCaptain.runsTheClub)
    }
}
