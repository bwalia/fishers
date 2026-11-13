package com.fishers.app.match

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.cricket.Engine
import com.fishers.app.cricket.Events
import com.fishers.app.cricket.ScoringEvent
import com.fishers.app.match.start.ClaimScorer
import com.fishers.app.match.start.FixtureInfo
import com.fishers.app.match.start.MatchPlayer
import com.fishers.app.match.start.MatchSetupViewModel
import com.fishers.app.match.start.MatchSquads
import com.fishers.app.match.start.NewMatch
import com.fishers.app.match.start.Official
import com.fishers.app.match.start.SetupBatch
import com.fishers.app.match.start.SetupBook
import com.fishers.app.match.start.SetupEvents
import com.fishers.app.match.start.SetupMatch
import com.fishers.app.match.start.SetupStep
import com.fishers.app.match.start.Side
import com.fishers.app.match.start.SideSquad
import com.fishers.app.match.start.TossCall
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.time.Instant

// Player ids are user ids — UUIDs — and the engine refuses anything else.
private const val RAVI = "10000000-0000-4000-8000-000000000001"
private const val TOM = "10000000-0000-4000-8000-000000000002"
private const val AMY = "10000000-0000-4000-8000-000000000003"
private const val ZOE = "10000000-0000-4000-8000-000000000004"
private const val H1 = "20000000-0000-4000-8000-000000000001"
private const val H2 = "20000000-0000-4000-8000-000000000002"
private const val A1 = "30000000-0000-4000-8000-000000000001"
private const val A2 = "30000000-0000-4000-8000-000000000002"

/**
 * The wizard against a fake server that keeps a real log, folded by the real
 * engine — the same Rust the server scores with. What these prove is that the
 * events the wizard posts replay into a match the scorer can bowl the first
 * ball of.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MatchSetupTest {
    @get:Rule val english = EnglishStrings()

    // One scheduler for runTest and Dispatchers.Main — see ClubsTest.
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val engine = Engine()

    private fun member(id: String, name: String, captain: Boolean = false) =
        ClubMemberDetail(userId = id, name = name, isCaptain = captain)

    private val lordsSquad = listOf(
        member(RAVI, "Ravi Patel", captain = true),
        member(TOM, "Tom Hardy"),
        member(AMY, "Amy Best"),
        member(ZOE, "Zoe Adams"),
    )

    /**
     * The server, as far as setting a match up goes: one fixture, a match once
     * it is made, and the log — skipping a batch's events the log has already
     * passed, as `apply_event_batch` does.
     */
    private open inner class Server(
        var match: SetupMatch? = null,
        val log: MutableList<ScoringEvent> = mutableListOf(),
        val canScore: Boolean = true,
    ) : FakeMatchStartApi() {
        val calls = mutableListOf<String>()
        var created: NewMatch? = null
        var claimedWith: ClaimScorer? = null
        val appointed = mutableListOf<Official>()

        override suspend fun event(eventId: String): FixtureInfo {
            calls += "GET /events/$eventId"
            return FixtureInfo(
                id = eventId, clubId = "lords", title = "Lords CC v Hemel CC",
                metadata = buildJsonObject { put("opposition", "Hemel CC"); put("home_name", "Lords CC") },
            )
        }

        override suspend fun matchForEvent(eventId: String): SetupMatch {
            calls += "GET /events/$eventId/cricket-match"
            return match ?: throw refused(404, "cricket match not started")
        }

        override suspend fun createMatch(eventId: String, body: NewMatch): SetupMatch {
            calls += "POST /events/$eventId/cricket-match"
            created = body
            val made = match ?: SetupMatch(
                id = body.matchId, eventId = eventId, clubId = "lords",
                oversLimit = body.oversLimit, homeName = body.homeName, awayName = body.awayName,
                canScore = canScore, myClubSide = Side.Home,
            )
            match = made
            return made
        }

        override suspend fun claimScorer(matchId: String, body: ClaimScorer): SetupMatch {
            calls += "POST /cricket/matches/$matchId/claim-scorer"
            claimedWith = body
            return match!!
        }

        override suspend fun matchEvents(matchId: String): List<ScoringEvent> {
            calls += "GET /cricket/matches/$matchId/events"
            // The server's list carries no `at`.
            return log.map { it.copy(at = null) }
        }

        override suspend fun postEvents(matchId: String, body: SetupBatch): SetupMatch {
            calls += "POST /cricket/matches/$matchId/events " + body.events.joinToString(",") { it.kind["type"]!!.jsonPrimitive.content }
            assertEquals("the scorer's lock is this device's", "device-1", body.deviceId)
            val seen = log.map { it.clientEventId }.toSet()
            for (event in body.events) {
                if (event.clientEventId in seen || event.seq <= (log.lastOrNull()?.seq ?: 0)) continue
                log += event
            }
            return match!!.copy(lastSeq = log.lastOrNull()?.seq ?: 0)
        }

        override suspend fun squads(matchId: String): MatchSquads {
            calls += "GET /cricket/matches/$matchId/squad"
            return MatchSquads(home = SideSquad(players = emptyList()), away = SideSquad(players = emptyList()))
        }

        override suspend fun clubMembers(clubId: String): List<ClubMemberDetail> {
            calls += "GET /clubs/$clubId/members"
            if (clubId != "lords") throw refused(403, "you are not a member of this club")
            return lordsSquad
        }

        override suspend fun appointOfficial(matchId: String, body: Official): JsonElement {
            calls += "POST /cricket/matches/$matchId/officials"
            appointed += body
            return JsonNull
        }
    }

    private var ids = 0
    private fun model(server: Server) = MatchSetupViewModel(
        api = server,
        eventId = "e1",
        deviceId = "device-1",
        userName = "Ravi Patel",
        engine = engine,
        newId = { "00000000-0000-4000-8000-%012d".format(++ids) },
        now = { Instant.parse("2026-11-14T12:00:00Z") },
    )

    /** The log as the server holds it, folded by the engine. */
    private fun fold(server: Server): String = engine.replay(server.log).getOrThrow()

    @Test
    fun `a fresh fixture is set up to the first ball, and the log replays live`() = runTest(dispatcher.scheduler) {
        val server = Server()
        val model = model(server)
        model.load()
        advanceUntilIdle()

        // The names the quick start wrote into the fixture.
        assertEquals(SetupStep.Terms, model.state.value.step)
        assertEquals("Lords CC", model.state.value.homeName)
        assertEquals("Hemel CC", model.state.value.awayName)
        assertNull("nothing is made just by opening the screen", server.created)

        // 1. The terms.
        model.setOvers(16)
        model.propose()
        advanceUntilIdle()
        val made = server.created!!
        assertEquals("the match id is chosen on the device", "00000000-0000-4000-8000-000000000001", made.matchId)
        assertEquals(16, made.oversLimit)
        assertEquals("Lords CC", made.homeName)
        assertEquals("Hemel CC", made.awayName)
        assertEquals(ClaimScorer(deviceId = "device-1", force = false), server.claimedWith)
        assertEquals(listOf("match_prepared", "conditions_proposed"), server.log.map { it.kind["type"]!!.jsonPrimitive.content })
        assertEquals(SetupStep.Agreement, model.state.value.step)
        // Proposing is the proposer's agreement; the other captain still has to.
        assertEquals("Ravi Patel", model.state.value.book.agreedHome)
        assertNull(model.state.value.book.agreedAway)

        // 2. The other captain agrees, in front of the scorer.
        model.continueToToss()
        assertEquals("the toss waits for both captains", SetupStep.Agreement, model.state.value.step)
        model.agree(Side.Away, "Imran Khan")
        advanceUntilIdle()
        assertTrue(model.state.value.book.bothAgreed)
        model.continueToToss()
        assertEquals(SetupStep.Toss, model.state.value.step)

        // 3. The toss: Hemel won and bowled, so Lords bat.
        model.setToss(Side.Away)
        model.setTossDecision(TossCall.Bowl)
        assertEquals(Side.Home, model.state.value.battingFirst)
        model.recordToss()
        advanceUntilIdle()
        assertEquals(SetupStep.Sheets, model.state.value.step)

        // 4. The team sheets: Lords from the club, Hemel typed.
        val pool = model.state.value.clubPlayers
        assertEquals(listOf("Ravi Patel", "Tom Hardy", "Amy Best", "Zoe Adams"), pool.map { it.name })
        pool.take(3).forEach { model.addPlayer(Side.Home, it) }
        assertEquals("picking the club's captain marks them C", RAVI, model.state.value.homeCaptain)
        model.setKeeper(Side.Home, TOM)
        listOf("Imran Khan", "Wasim Akram", "Saqlain Mushtaq").forEach { model.addGuest(Side.Away, it) }
        model.movePlayer(Side.Away, model.state.value.awaySheet[2].id, up = true)
        assertEquals(listOf("Imran Khan", "Saqlain Mushtaq", "Wasim Akram"), model.state.value.awaySheet.map { it.name })
        model.addOfficial(umpire = true, player = MatchPlayer(ZOE, "Zoe Adams"))
        model.addOfficialGuest(umpire = false, name = "Dickie Bird")

        model.confirmSheet(Side.Home)
        advanceUntilIdle()
        assertEquals("one side named, the other still to come", SetupStep.Sheets, model.state.value.step)
        model.confirmSheet(Side.Away)
        advanceUntilIdle()
        assertEquals(SetupStep.Openers, model.state.value.step)
        // A member named an official may score: the API is told. A guest is not.
        assertEquals(listOf(Official(ZOE, "umpire")), server.appointed)

        // 5. The openers default to the top of the order and the first bowler.
        assertEquals(RAVI, model.state.value.strikerId)
        assertEquals(TOM, model.state.value.nonStrikerId)
        assertEquals("Imran Khan", model.state.value.book.players(Side.Away).first { it.id == model.state.value.bowlerId }.name)
        model.setStriker(AMY)
        model.startInnings()
        advanceUntilIdle()
        assertEquals(SetupStep.Scoring, model.state.value.step)

        // The hand-over: exactly this log, in this order…
        assertEquals(
            listOf(
                "match_prepared", "conditions_proposed", "conditions_agreed", "toss_recorded",
                "xi_selected", "xi_selected", "officials_appointed", "innings_started",
            ),
            server.log.map { it.kind["type"]!!.jsonPrimitive.content },
        )
        assertEquals((1L..8L).toList(), server.log.map { it.seq })

        // …which the engine folds into a live match, the openers in, the terms agreed…
        val state = fold(server)
        val book = SetupBook.read(state)
        assertEquals("live", book.status)
        assertEquals(16, book.conditions?.oversLimit)
        assertEquals(listOf(RAVI, TOM, AMY), book.homeXi)
        assertEquals(TOM, book.homeKeeper)
        assertEquals(Side.Away, book.tossWinner)
        val innings = kotlinx.serialization.json.Json.parseToJsonElement(state).jsonObject["innings"]!!.jsonArray.single().jsonObject
        assertEquals("home", innings["batting"]!!.jsonPrimitive.content)
        assertEquals(AMY, innings["striker_id"]!!.jsonPrimitive.content)
        assertEquals(TOM, innings["non_striker_id"]!!.jsonPrimitive.content)
        assertEquals(model.state.value.bowlerId, innings["bowler_id"]!!.jsonPrimitive.content)

        // …and ready for the first ball: the scorer's own delivery is accepted.
        val score = engine.scoreline(state)!!
        assertEquals(0, score.runs)
        assertEquals("Lords CC", score.battingName)
        val firstBall = ScoringEvent(clientEventId = "00000000-0000-4000-8000-999999999999", seq = 9, kind = Events.delivery(1))
        assertTrue("the first ball is the scorer's to bowl", engine.accepts(state, firstBall))
    }

    /** The order of calls the scorer's screen relies on: the match exists, this device holds the book, then the log. */
    @Test
    fun `the match is made and the book claimed before anything is written`() = runTest(dispatcher.scheduler) {
        val server = Server()
        val model = model(server)
        model.load()
        advanceUntilIdle()
        model.propose()
        advanceUntilIdle()

        val writes = server.calls.filter { it.startsWith("POST") }
        val matchId = server.created!!.matchId
        assertEquals("POST /events/e1/cricket-match", writes[0])
        assertEquals("POST /cricket/matches/$matchId/claim-scorer", writes[1])
        assertEquals("POST /cricket/matches/$matchId/events match_prepared,conditions_proposed", writes[2])
    }

    /** A match somebody set up already: picked up where its log got to, from the server. */
    @Test
    fun `a match half set up is resumed at the team sheets`() = runTest(dispatcher.scheduler) {
        val log = mutableListOf<ScoringEvent>()
        fun add(kind: JsonObject) {
            log += ScoringEvent("00000000-0000-4000-9000-%012d".format(log.size + 1), log.size + 1L, kind)
        }
        add(SetupEvents.matchPrepared(20, "Lords CC", "Hemel CC"))
        add(SetupEvents.conditionsProposed(com.fishers.app.match.start.MatchConditions.standard(20), Side.Home, "Ravi"))
        add(SetupEvents.conditionsAgreed(Side.Away, "Imran"))
        add(SetupEvents.tossRecorded(Side.Home, TossCall.Bat))
        add(SetupEvents.xiSelected(Side.Away, listOf(MatchPlayer(A1, "Imran"), MatchPlayer(A2, "Wasim")), A1, null))
        val server = Server(
            match = SetupMatch(id = "m1", eventId = "e1", clubId = "lords", status = "selecting_xi", canScore = true, lastSeq = 5),
            log = log,
        )
        val model = model(server)
        model.load()
        advanceUntilIdle()

        assertTrue(server.calls.contains("POST /cricket/matches/m1/claim-scorer"))
        assertEquals(SetupStep.Sheets, model.state.value.step)
        assertTrue("the away side is already named", model.state.value.named(Side.Away))
        assertEquals(listOf("Imran", "Wasim"), model.state.value.awaySheet.map { it.name })
        assertEquals(Side.Home, model.state.value.battingFirst)

        // Naming the home side carries on from seq 6, not from 1.
        model.state.value.clubPlayers.take(2).forEach { model.addPlayer(Side.Home, it) }
        model.confirmSheet(Side.Home)
        advanceUntilIdle()
        assertEquals(6L, server.log.last().seq)
        assertEquals(SetupStep.Openers, model.state.value.step)
    }

    @Test
    fun `a match already being scored goes straight to the scorer`() = runTest(dispatcher.scheduler) {
        val log = mutableListOf<ScoringEvent>()
        fun add(kind: JsonObject) {
            log += ScoringEvent("00000000-0000-4000-9000-%012d".format(log.size + 1), log.size + 1L, kind)
        }
        add(SetupEvents.matchPrepared(20, "Lords CC", "Hemel CC"))
        add(SetupEvents.conditionsProposed(com.fishers.app.match.start.MatchConditions.standard(20), Side.Home, "Ravi"))
        add(SetupEvents.conditionsAgreed(Side.Away, "Imran"))
        add(SetupEvents.tossRecorded(Side.Home, TossCall.Bat))
        add(SetupEvents.xiSelected(Side.Home, listOf(MatchPlayer(H1, "Ravi"), MatchPlayer(H2, "Tom")), null, null))
        add(SetupEvents.xiSelected(Side.Away, listOf(MatchPlayer(A1, "Imran"), MatchPlayer(A2, "Wasim")), null, null))
        add(SetupEvents.inningsStarted(Side.Home, H1, H2, A1))
        val server = Server(
            match = SetupMatch(id = "m1", eventId = "e1", status = "live", canScore = true, lastSeq = 7),
            log = log,
        )
        val model = model(server)
        model.load()
        advanceUntilIdle()
        assertEquals(SetupStep.Scoring, model.state.value.step)
    }

    @Test
    fun `another phone holding the book stops the setup with the server's words`() = runTest(dispatcher.scheduler) {
        val server = object : Server(
            match = SetupMatch(id = "m1", eventId = "e1", status = "preparing", canScore = true),
        ) {
            override suspend fun claimScorer(matchId: String, body: ClaimScorer): SetupMatch =
                throw refused(409, "someone else is scoring this match — ask them to hand it over")
        }
        val model = model(server)
        model.load()
        advanceUntilIdle()
        assertEquals("Someone else is scoring this match — ask them to hand it over", model.state.value.blocked)
        assertFalse(server.calls.any { it.startsWith("POST /cricket/matches/m1/events") })
    }

    @Test
    fun `the engine's refusal is shown and nothing is sent`() = runTest(dispatcher.scheduler) {
        val server = Server()
        val model = model(server)
        model.load()
        advanceUntilIdle()
        model.propose()
        advanceUntilIdle()
        val posted = server.log.size

        // Straight to the toss with only one captain agreed: the Laws say no.
        model.recordToss()
        advanceUntilIdle()
        assertNotNull(model.state.value.error)
        assertEquals(posted, server.log.size)
        assertEquals(SetupStep.Agreement, model.state.value.step)
    }

    @Test
    fun `a sheet needs two players and the openers must differ`() = runTest(dispatcher.scheduler) {
        val server = Server()
        val model = model(server)
        model.load()
        advanceUntilIdle()
        model.addGuest(Side.Home, "Only One")
        model.confirmSheet(Side.Home)
        advanceUntilIdle()
        assertEquals("A team sheet needs at least two players.", model.state.value.error)

        model.setStriker("x")
        model.setNonStriker("x")
        model.setBowler("y")
        model.startInnings()
        advanceUntilIdle()
        assertEquals("Pick two different batters and a bowler.", model.state.value.error)
        assertTrue(server.log.isEmpty())
    }

    @Test
    fun `an agreement needs a name against it`() = runTest(dispatcher.scheduler) {
        val server = Server()
        val model = model(server)
        model.load()
        advanceUntilIdle()
        model.agree(Side.Away, "   ")
        assertEquals("Put a name against the agreement.", model.state.value.error)
    }
}
