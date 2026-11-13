package com.fishers.app.match

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.clubs.Team
import com.fishers.app.cricket.AbandonBody
import com.fishers.app.cricket.BallCommentary
import com.fishers.app.cricket.BookSweeper
import com.fishers.app.cricket.ClaimScorerBody
import com.fishers.app.cricket.CommentaryRequest
import com.fishers.app.cricket.CricketMatch
import com.fishers.app.cricket.Engine
import com.fishers.app.cricket.EventsBatch
import com.fishers.app.cricket.FileBallStore
import com.fishers.app.cricket.HandoverBody
import com.fishers.app.cricket.LiveScorerViewModel
import com.fishers.app.cricket.MatchOfficialRow
import com.fishers.app.cricket.ScoreboardShare
import com.fishers.app.cricket.ScoringEvent
import com.fishers.app.cricket.ShareScoreboardBody
import com.fishers.app.cricket.SyncStatus
import com.fishers.app.match.start.ClaimScorer
import com.fishers.app.match.start.CreatedFixture
import com.fishers.app.match.start.FixtureInfo
import com.fishers.app.match.start.FixtureInfoPage
import com.fishers.app.match.start.FixturePage
import com.fishers.app.match.start.MatchRegistrar
import com.fishers.app.match.start.MatchSetupViewModel
import com.fishers.app.match.start.NewClub
import com.fishers.app.match.start.NewFixture
import com.fishers.app.match.start.NewMatch
import com.fishers.app.match.start.OfflineCache
import com.fishers.app.match.start.ScoreHubViewModel
import com.fishers.app.match.start.SetupBatch
import com.fishers.app.match.start.SetupBook
import com.fishers.app.match.start.SetupMatch
import com.fishers.app.match.start.SetupStep
import com.fishers.app.match.start.Side
import com.fishers.app.match.start.StartMatchViewModel
import com.fishers.app.match.start.TossCall
import com.fishers.app.match.start.phoneMatches
import com.fishers.app.net.ScoringApi
import com.fishers.app.season.MyClubRole
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.time.Instant

/**
 * The owner's question — can a match be played with no internet? — end to end,
 * against the real engine: somebody with no club starts a match in airplane
 * mode, sets it up, scores an over; then the signal comes back and the server
 * is told, in order, exactly once.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class OfflineMatchTest {
    @get:Rule val english = EnglishStrings()
    @get:Rule val disk = TemporaryFolder()

    // One scheduler for runTest and Dispatchers.Main — see ClubsTest.
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val engine = Engine()
    private val noon = Instant.parse("2026-11-14T12:00:00Z")
    private var ids = 0
    private val newId = { "00000000-0000-4000-8000-%012d".format(++ids) }

    /**
     * The server, by hand: clubs, fixtures, matches and their logs, folded by
     * the real engine. With [online] off every call fails as airplane mode
     * does; [loseAnswer] makes the next matching call do its work and then
     * lose the answer on the way back, which is what a dropped signal does.
     */
    private inner class Ground {
        var online = false
        var loseAnswer: ((String) -> Boolean)? = null
        /** Every call that reached the server, in order. */
        val calls = mutableListOf<String>()
        val clubs = mutableListOf<Club>()
        val events = mutableListOf<FixtureInfo>()
        private val startAt = mutableMapOf<String, Instant>()
        /** By fixture: the match id, and which device holds the book. */
        val matches = mutableMapOf<String, NewMatch>()
        var scorerDevice: String? = null
        val log = mutableListOf<ScoringEvent>()

        val writes: List<String> get() = calls.filter { it.startsWith("POST") }

        private fun reach(call: String) {
            if (!online) throw IOException("no signal")
            calls += call
        }

        private fun <T> answer(call: String, value: T): T {
            if (loseAnswer?.invoke(call) == true) {
                loseAnswer = null
                throw IOException("the answer never arrived")
            }
            return value
        }

        private fun eventOf(matchId: String) = matches.entries.single { it.value.matchId == matchId }.key

        private fun status() = SetupBook.read(engine.replay(log).getOrThrow()).status

        fun setup(eventId: String): SetupMatch {
            val m = matches.getValue(eventId)
            return SetupMatch(
                id = m.matchId, eventId = eventId, clubId = events.single { it.id == eventId }.clubId,
                status = status(), oversLimit = m.oversLimit, homeName = m.homeName, awayName = m.awayName,
                lastSeq = log.lastOrNull()?.seq ?: 0, activeScorerUserId = scorerDevice?.let { "u-me" },
                canScore = true, myClubSide = Side.Home,
            )
        }

        fun cricket(eventId: String): CricketMatch {
            val m = matches.getValue(eventId)
            return CricketMatch(
                id = m.matchId, eventId = eventId, status = status(), oversLimit = m.oversLimit,
                homeName = m.homeName, awayName = m.awayName, lastSeq = log.lastOrNull()?.seq ?: 0,
                canScore = true, activeScorerUserId = scorerDevice?.let { "u-me" }, activeScorerDeviceId = scorerDevice,
                clubId = events.single { it.id == eventId }.clubId,
            )
        }

        val start = object : FakeMatchStartApi() {
            override suspend fun cricketFixtures(state: String?, search: String?, order: String, page: Int, perPage: Int): FixturePage {
                reach("GET /cricket/fixtures")
                return FixturePage()
            }
            override suspend fun myClubs(): List<Club> = reach("GET /clubs").let { clubs.toList() }
            override suspend fun myClubRole(clubId: String) =
                reach("GET /clubs/$clubId/my-role").let { MyClubRole(permissions = listOf("manage_events", "score_match")) }
            override suspend fun clubTeams(clubId: String): List<Team> = reach("GET /clubs/$clubId/teams").let { emptyList() }
            override suspend fun clubMembers(clubId: String): List<ClubMemberDetail> =
                reach("GET /clubs/$clubId/members").let { emptyList() }

            override suspend fun createClub(body: NewClub): Club {
                reach("POST /clubs")
                val club = Club(id = "club-${clubs.size + 1}", name = body.name, isInformalGroup = body.isInformalGroup)
                clubs += club
                return answer("POST /clubs", club)
            }

            override suspend fun createEvent(body: NewFixture): CreatedFixture {
                reach("POST /events")
                assertTrue("a fixture needs a club", body.clubId.isNotBlank())
                val event = FixtureInfo(
                    id = "srv-event-${events.size + 1}", clubId = body.clubId, title = body.title,
                    metadata = JsonObject(body.metadata.mapValues { JsonPrimitive(it.value) }),
                )
                events += event
                startAt[event.id] = Instant.parse(body.startAt)
                return answer("POST /events", CreatedFixture(event.id, body.clubId, body.title))
            }

            override suspend fun clubFixtures(clubId: String, from: String, to: String, perPage: Int): FixtureInfoPage {
                reach("GET /events")
                val window = Instant.parse(from)..Instant.parse(to)
                return FixtureInfoPage(events.filter { it.clubId == clubId && startAt.getValue(it.id) in window })
            }

            /** Create-or-get by fixture, as `cricket_repo::create_match` is. */
            override suspend fun createMatch(eventId: String, body: NewMatch): SetupMatch {
                val call = "POST /events/$eventId/cricket-match"
                reach(call)
                assertTrue("no such fixture", events.any { it.id == eventId })
                matches.getOrPut(eventId) { body }
                return answer(call, setup(eventId))
            }

            override suspend fun claimScorer(matchId: String, body: ClaimScorer): SetupMatch {
                val call = "POST /cricket/matches/$matchId/claim-scorer"
                reach(call)
                scorerDevice = body.deviceId
                return answer(call, setup(eventOf(matchId)))
            }

            override suspend fun postEvents(matchId: String, body: SetupBatch): SetupMatch =
                throw AssertionError("the setup sends nothing with no signal")
        }

        val scoring = object : ScoringApi {
            override suspend fun matchForEvent(eventId: String): CricketMatch {
                reach("GET /events/$eventId/cricket-match")
                if (eventId !in matches) throw refused(404, "cricket match not started")
                return cricket(eventId)
            }
            override suspend fun match(matchId: String): CricketMatch {
                reach("GET /cricket/matches/$matchId")
                return cricket(eventOf(matchId))
            }
            override suspend fun events(matchId: String): List<ScoringEvent> {
                reach("GET /cricket/matches/$matchId/events")
                return log.map { it.copy(at = null) }
            }
            /** Skips what it holds by `client_event_id` and by number, as `apply_event_batch` does. */
            override suspend fun postEvents(matchId: String, body: EventsBatch): CricketMatch {
                val call = "POST /cricket/matches/$matchId/events"
                reach(call)
                assertEquals("the book is this phone's", scorerDevice, body.deviceId)
                val seen = log.map { it.clientEventId }.toSet()
                for (event in body.events) {
                    if (event.clientEventId in seen || event.seq <= (log.lastOrNull()?.seq ?: 0)) continue
                    log += event
                }
                engine.replay(log).getOrThrow()
                return answer(call, cricket(eventOf(matchId)))
            }
            override suspend fun claimScorer(matchId: String, body: ClaimScorerBody): CricketMatch {
                reach("POST /cricket/matches/$matchId/claim-scorer")
                scorerDevice = body.deviceId
                return cricket(eventOf(matchId))
            }
            override suspend fun scorecard(matchId: String): JsonObject = throw AssertionError()
            override suspend fun shareScoreboard(matchId: String, body: ShareScoreboardBody): ScoreboardShare = throw AssertionError()
            override suspend fun handOver(matchId: String, body: HandoverBody): CricketMatch = throw AssertionError()
            override suspend fun officials(matchId: String): List<MatchOfficialRow> = emptyList()
            override suspend fun squads(matchId: String) = com.fishers.app.cricket.MatchSquads()
            override suspend fun abandon(matchId: String, body: AbandonBody): CricketMatch = throw AssertionError()
            override suspend fun commentary(matchId: String, body: CommentaryRequest) = BallCommentary()
        }
    }

    /** One phone: its books and its saved clubs, in their own folder. */
    private inner class Phone(name: String) {
        val store = FileBallStore(File(disk.root, "$name/books"))
        val cache = OfflineCache(File(disk.root, "$name/cache"))
        val device = "device-$name"

        fun registrar(ground: Ground) = MatchRegistrar(ground.start, store, device)
        fun sweeper(ground: Ground) = BookSweeper(ground.scoring, store, device, registrar = registrar(ground))
        fun scorer(ground: Ground, eventId: String) = LiveScorerViewModel(
            api = ground.scoring, eventId = eventId, deviceId = device, store = store, myUserId = "u-me",
            registrar = registrar(ground), newId = newId, now = { null },
        )
    }

    /** What came of playing the match with no signal. */
    private class Played(val phoneEventId: String, val matchId: String, val scorer: LiveScorerViewModel)

    /**
     * The owner's case with the signal off: a player with no club — the phone
     * saw that once, online — starts a match, sets it up and scores an over.
     */
    private suspend fun TestScope.playOffline(ground: Ground, phone: Phone): Played {
        // Once, with signal: the phone learns this player has no club to start a match for.
        ground.online = true
        StartMatchViewModel(ground.start, phone.cache, phone.store, phone.device, now = { noon }, newId = newId).load()
        advanceUntilIdle()
        ground.calls.clear()
        ground.online = false

        // At the ground. The quick start, with no signal.
        val start = StartMatchViewModel(ground.start, phone.cache, phone.store, phone.device, "u-me", now = { noon }, newId = newId)
        start.load()
        advanceUntilIdle()
        assertTrue("no signal is said, not hidden", start.state.value.offline)
        assertTrue("the player with no club is asked for a team name", start.state.value.needsATeam)
        start.setNewTeamName(" Gully Kings ")
        start.setOpposition("Southall Strikers", null)
        start.start()
        advanceUntilIdle()
        assertNull(start.state.value.error)
        val phoneEventId = checkNotNull(start.state.value.startedEventId) { "the match did not start" }
        assertTrue("the phone made no club yet", ground.clubs.isEmpty())

        // The setup, all of it on the phone's book.
        val setup = MatchSetupViewModel(
            api = ground.start, eventId = phoneEventId, deviceId = phone.device, userName = "Sunny",
            store = phone.store, cache = phone.cache, myUserId = "u-me", engine = engine, newId = newId, now = { noon },
        )
        setup.load()
        advanceUntilIdle()
        assertTrue(setup.state.value.offline)
        assertEquals(SetupStep.Terms, setup.state.value.step)
        assertEquals("Gully Kings", setup.state.value.homeName)
        assertEquals("Southall Strikers", setup.state.value.awayName)

        setup.setOvers(2)
        setup.propose()
        advanceUntilIdle()
        assertEquals(SetupStep.Agreement, setup.state.value.step)
        setup.agree(Side.Away, "Imran")
        advanceUntilIdle()
        setup.continueToToss()
        setup.setToss(Side.Home)
        setup.setTossDecision(TossCall.Bat)
        setup.recordToss()
        advanceUntilIdle()
        assertEquals(SetupStep.Sheets, setup.state.value.step)
        // Guests, typed: ids minted on the phone, as UUIDs the engine takes.
        listOf("Sunny", "Raj", "Dev").forEach { setup.addGuest(Side.Home, it) }
        listOf("Imran", "Wasim", "Saqlain").forEach { setup.addGuest(Side.Away, it) }
        setup.confirmSheet(Side.Home)
        advanceUntilIdle()
        setup.confirmSheet(Side.Away)
        advanceUntilIdle()
        assertEquals(SetupStep.Openers, setup.state.value.step)
        setup.startInnings()
        advanceUntilIdle()
        assertNull(setup.state.value.error)
        assertEquals("the scorer takes over", SetupStep.Scoring, setup.state.value.step)

        // The scorer, from the phone's book, by the id the setup handed it.
        val scorer = phone.scorer(ground, phoneEventId)
        scorer.load()
        advanceUntilIdle()
        assertTrue("scoring with no signal", scorer.state.value.isLive)
        repeat(6) { assertTrue(scorer.runs(1)) }
        advanceUntilIdle()
        assertEquals("6/0", scorer.state.value.view!!.current!!.score)
        assertEquals(SyncStatus.Offline, scorer.state.value.sync)
        assertEquals("the bar counts balls, not the toss", 6, scorer.state.value.unsentBalls)

        assertTrue("nothing reached the server", ground.calls.isEmpty())
        return Played(phoneEventId, phone.store.read(phoneEventId)!!.matchId, scorer)
    }

    @Test
    fun `a match is started, set up and scored with no signal, then put on the server once`() = runTest(dispatcher.scheduler) {
        val ground = Ground()
        val phone = Phone("a")
        val played = playOffline(ground, phone)

        // "On this phone", with no signal: the way back to the match.
        val hub = ScoreHubViewModel(ground.start, phone.store, phone.cache, sweep = { phone.sweeper(ground).sendLeftovers() })
        hub.load()
        advanceUntilIdle()
        val row = hub.state.value.onThisPhone.single()
        assertEquals(played.phoneEventId, row.eventId)
        assertEquals("Gully Kings v Southall Strikers", row.title)
        assertEquals(6, row.unsentBalls)
        assertTrue(row.waiting)
        assertFalse("it opens on the scorer", row.settingUp)
        assertNotNull("the server's list says it could not load", hub.state.value.error)

        // The signal comes back; the app comes to the front.
        ground.online = true
        val sent = phone.sweeper(ground).sendLeftovers()

        val match = played.matchId
        val event = ground.events.single().id
        assertEquals(
            "club, fixture, match, the book, the log — in that order, once each",
            listOf(
                "POST /clubs",
                "POST /events",
                "POST /events/$event/cricket-match",
                "POST /cricket/matches/$match/claim-scorer",
                "POST /cricket/matches/$match/events",
            ),
            ground.writes,
        )
        assertEquals(13, sent)

        val club = ground.clubs.single()
        assertEquals("Gully Kings", club.name)
        assertTrue(club.isInformalGroup)
        val fixture = ground.events.single()
        assertEquals(club.id, fixture.clubId)
        assertEquals("the phone's id rides in the metadata", played.phoneEventId, fixture.clientRef)
        assertEquals("Gully Kings v Southall Strikers", fixture.title)
        assertEquals("the server took the phone's match id", match, ground.matches.getValue(event).matchId)
        assertEquals("device-a", ground.scorerDevice)

        // The server's book is the phone's: the same over, folded by the same engine.
        assertEquals(13, ground.log.size)
        assertEquals(played.scorer.state.value.view, engine.view(engine.replay(ground.log).getOrThrow()))

        // The book follows the server's id; the phone's id still finds it.
        val book = phone.store.read(event)!!
        assertEquals(event, book.eventId)
        assertNull(book.create)
        assertTrue(book.pending.isEmpty())
        assertEquals(event, phone.store.read(played.phoneEventId)!!.eventId)
        assertEquals(event, phone.store.resolve(played.phoneEventId))
        assertEquals(listOf(event), phone.store.all().map { it.eventId })
        assertFalse(phoneMatches(phone.store.all()).single().waiting)

        // A second sync has nothing to do, and does not ask.
        val before = ground.calls.toList()
        assertEquals(0, phone.sweeper(ground).sendLeftovers())
        assertEquals(before, ground.calls)

        // The scorer still on screen carries on under the server's id.
        ground.calls.clear()
        played.scorer.load()
        advanceUntilIdle()
        assertTrue(ground.calls.contains("GET /events/$event/cricket-match"))
        // The over is done: somebody else bowls the next.
        val next = played.scorer.bowlerChoices().first { it.refusal == null }.player.id
        assertTrue(played.scorer.changeBowler(next))
        assertTrue(played.scorer.runs(4))
        advanceUntilIdle()
        assertEquals(SyncStatus.Saved, played.scorer.state.value.sync)
        assertEquals(15, ground.log.size)
        assertEquals("10/0", engine.view(engine.replay(ground.log).getOrThrow())!!.current!!.score)
    }

    @Test
    fun `the scorer puts the match on the server itself when the signal comes back`() = runTest(dispatcher.scheduler) {
        val ground = Ground()
        val played = playOffline(ground, Phone("b"))

        ground.online = true
        played.scorer.onNetworkAvailable()
        advanceUntilIdle()

        val event = ground.events.single().id
        assertEquals(
            listOf(
                "POST /clubs",
                "POST /events",
                "POST /events/$event/cricket-match",
                "POST /cricket/matches/${played.matchId}/claim-scorer",
                "POST /cricket/matches/${played.matchId}/events",
            ),
            ground.writes,
        )
        val state = played.scorer.state.value
        assertEquals(SyncStatus.Saved, state.sync)
        assertEquals(0, state.unsent)
        assertNull(state.syncProblem)
        assertEquals(event, state.match?.eventId)
        assertEquals(13, ground.log.size)
    }

    /**
     * The signal goes again between a request landing and its answer coming
     * back, at every step in turn. Whatever the step, the next sync finds what
     * the lost answer made rather than making a second: one club, one fixture,
     * one match, every event once.
     */
    @Test
    fun `an answer lost at any step makes nothing twice`() = runTest(dispatcher.scheduler) {
        val steps = listOf<Pair<String, (String) -> Boolean>>(
            "the club" to { it == "POST /clubs" },
            "the fixture" to { it == "POST /events" },
            "the match" to { it.endsWith("/cricket-match") },
            "the claim" to { it.endsWith("/claim-scorer") },
            "the log" to { it.startsWith("POST /cricket/matches/") && it.endsWith("/events") },
        )
        for ((i, step) in steps.withIndex()) {
            val (name, lose) = step
            val ground = Ground()
            val phone = Phone("lost-$i")
            playOffline(ground, phone)

            ground.online = true
            ground.loseAnswer = lose
            phone.sweeper(ground).sendLeftovers()
            assertNull("$name: the answer was lost", ground.loseAnswer)
            var tries = 0
            while (phone.store.withUnsent().isNotEmpty() && tries++ < 3) phone.sweeper(ground).sendLeftovers()

            assertTrue("$name: everything went in the end", phone.store.withUnsent().isEmpty())
            assertEquals("$name: one club", 1, ground.clubs.size)
            assertEquals("$name: one fixture", 1, ground.events.size)
            assertEquals("$name: one match", 1, ground.matches.size)
            assertEquals("$name: the club was asked for once", 1, ground.writes.count { it == "POST /clubs" })
            assertEquals("$name: the fixture was asked for once", 1, ground.writes.count { it == "POST /events" })
            assertEquals("$name: every event once", 13, ground.log.size)
            assertEquals(13, ground.log.map { it.clientEventId }.toSet().size)
            assertEquals("6/0", engine.view(engine.replay(ground.log).getOrThrow())!!.current!!.score)

            val before = ground.calls.size
            phone.sweeper(ground).sendLeftovers()
            assertEquals("$name: a sync after has nothing to do", before, ground.calls.size)
        }
    }

    @Test
    fun `a match left on its first page makes nothing on the server`() = runTest(dispatcher.scheduler) {
        val ground = Ground()
        val phone = Phone("c")
        phone.cache.saveStartableClubs(emptyList())
        val start = StartMatchViewModel(ground.start, phone.cache, phone.store, phone.device, now = { noon }, newId = newId)
        start.load()
        advanceUntilIdle()
        start.setNewTeamName("Gully Kings")
        start.setOpposition("Southall", null)
        start.start()
        advanceUntilIdle()
        val id = start.state.value.startedEventId!!

        val row = phoneMatches(phone.store.all()).single()
        assertEquals(id, row.eventId)
        assertTrue("it opens on the setup", row.settingUp)

        // Signal, but the terms were never put: no fixture in anybody's diary.
        ground.online = true
        phone.sweeper(ground).sendLeftovers()
        assertTrue(ground.calls.isEmpty())
        assertNotNull(phone.store.read(id)?.create)
    }

    @Test
    fun `with no signal and nothing saved, a club is not guessed at`() = runTest(dispatcher.scheduler) {
        val ground = Ground()
        val phone = Phone("d")
        val start = StartMatchViewModel(ground.start, phone.cache, phone.store, phone.device, now = { noon }, newId = newId)
        start.load()
        advanceUntilIdle()
        assertFalse("not offered a team name: they may have a club", start.state.value.needsATeam)
        assertEquals(
            "Your clubs are not saved on this phone yet, and there is no signal to fetch them. " +
                "Open the app once with signal — after that you can start a match without any.",
            start.state.value.loadError,
        )
    }

    @Test
    fun `a club the phone saved is offered with no signal`() = runTest(dispatcher.scheduler) {
        val ground = Ground()
        val phone = Phone("e")
        ground.clubs += Club("lords", "Lords CC")
        ground.online = true
        StartMatchViewModel(ground.start, phone.cache, phone.store, phone.device, now = { noon }, newId = newId).load()
        advanceUntilIdle()
        ground.online = false

        val start = StartMatchViewModel(ground.start, phone.cache, phone.store, phone.device, now = { noon }, newId = newId)
        start.load()
        advanceUntilIdle()
        assertEquals(listOf("Lords CC"), start.state.value.clubs.map { it.name })
        assertFalse(start.state.value.needsATeam)
        start.setOpposition("Hemel", null)
        start.start()
        advanceUntilIdle()

        val book = phone.store.read(start.state.value.startedEventId!!)!!
        val create = book.create!!
        assertNull("no club to make", create.club)
        assertEquals("lords", create.clubId)
        assertEquals("lords", create.fixture?.clubId)
        assertEquals("Lords CC v Hemel", create.fixture?.title)
        assertEquals(book.eventId, create.fixture?.metadata?.get(FixtureInfo.CLIENT_REF))
    }
}
