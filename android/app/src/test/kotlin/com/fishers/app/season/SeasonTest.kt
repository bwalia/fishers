package com.fishers.app.season

import com.fishers.app.EnglishStrings
import com.fishers.app.FakeFishersApi
import com.fishers.app.clubs.Club
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.Json
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import retrofit2.HttpException
import retrofit2.Response
import java.time.ZoneOffset

/**
 * The season pages, pinned to real responses.
 *
 * The fixtures under `src/test/resources/season/` were captured from
 * `/me/game`, `/clubs/{id}/season`, `/clubs/{id}/my-role` and the close
 * preview against a local API holding a copy of the dev database: a batter,
 * an all-rounder, somebody who has not played, and a secretary. A field the
 * API renames fails here rather than as a blank tile on a phone.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SeasonTest {
    @get:Rule val english = EnglishStrings()

    // One scheduler for runTest and Main — see ClubsTest for why.
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    /** The app's own decoder settings, from `net/Network.kt`. */
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    private fun fixture(name: String): String =
        requireNotNull(javaClass.getResource("/season/$name.json")) { "no fixture $name" }.readText()

    private inline fun <reified T> decode(name: String): T = json.decodeFromString(fixture(name))

    private val clubId = "6074888b-460c-456d-a9e5-9e5e7d1a3fff"

    // MARK: Decoding

    @Test
    fun `a batter's season decodes, field for field`() {
        val g = decode<PlayerGame>("player_game_batter")
        assertEquals("Gary Tucker", g.name)
        assertEquals(2026, g.season)
        assertEquals(listOf(2026), g.seasons)
        assertEquals(7, g.totals.battingInnings)
        assertEquals(281, g.totals.runs)
        assertEquals(0, g.totals.bowlingBalls)
        assertNull("never bowled, so no figures", g.totals.bestBowling)
        assertNull("first season, nothing to compare with", g.previous)
        assertEquals(7, g.form.matches.size)
        assertEquals("steady", g.form.battingTrend)
        assertNull(g.form.bowlingTrend)
        assertEquals(clubId, g.clubRank!!.clubId)
        assertEquals(1, g.clubRank!!.runs)
        assertNull(g.clubRank!!.wickets)
        assertEquals(listOf("best_score", "most_sixes", "most_catches"), g.bests.map { it.code })
        assertTrue(g.bests.all { it.thisSeason })
        assertEquals("first_match", g.milestones.first().code)
    }

    @Test
    fun `an all-rounder carries bowling figures and a bowling trend`() {
        val g = decode<PlayerGame>("player_game_allrounder")
        assertEquals(10, g.totals.wickets)
        assertEquals(Figures(wickets = 3, runs = 21), g.totals.bestBowling)
        assertEquals("rising", g.form.bowlingTrend)
        assertTrue(g.form.matches.any { it.bowled })
    }

    @Test
    fun `a club's season decodes with all ten boards`() {
        val c = decode<ClubSeason>("club_season")
        assertEquals("Hemel Hempstead Town CC", c.clubName)
        assertEquals(SeasonRecord(played = 8, won = 4, lost = 3, tiedOrNoResult = 1), c.record)
        assertEquals(50, c.record.winPercent)
        assertEquals(22, c.players)
        assertEquals(
            listOf(
                "runs", "wickets", "batting_average", "strike_rate", "economy",
                "best_innings", "best_bowling", "catches", "sixes", "player_of_match",
            ),
            c.boards.map { it.code },
        )
        assertTrue(c.boards.all { it.leaders.size <= 5 })
        assertEquals("281", c.boards.first().leaders.first().value)
        assertEquals("7 inns", c.boards.first().leaders.first().detail)
        assertNotNull(c.closedAt)
    }

    @Test
    fun `only somebody who runs the club's operations may close the season`() {
        assertTrue(decode<MyClubRole>("my_role_secretary").canCloseSeason)
        assertFalse(decode<MyClubRole>("my_role_player").canCloseSeason)
        val p = decode<ClosePreview>("close_preview")
        assertEquals(34, p.members)
        assertEquals(33, p.willEmail)
        assertEquals(22, p.played)
    }

    // MARK: Words

    @Test
    fun `highlights are written from their code, not the API's English`() {
        val g = decode<PlayerGame>("player_game_batter")
        assertEquals(
            listOf(
                "Best score of the season: 79 against Radlett.",
                "Milestone reached: 250 career runs.",
                "Top for runs at Hemel Hempstead Town CC this season.",
                "You reached double figures in 7 of 7 innings.",
            ),
            g.highlights.map(::highlightText),
        )
    }

    @Test
    fun `a highlight this build does not know falls back to the API's text`() {
        assertEquals(
            "Something new and good.",
            highlightText(Highlight("brand_new_code", "Something new and good.", "3")),
        )
        // And a best with nothing to say who it was against keeps the API's sentence.
        assertEquals("Fallback.", highlightText(Highlight("new_best_score", "Fallback.", "80")))
    }

    @Test
    fun `counted highlights pluralise`() {
        assertEquals(
            "Player of the match once this season.",
            highlightText(Highlight("player_of_match", "", "1")),
        )
        assertEquals(
            "Player of the match 3 times this season.",
            highlightText(Highlight("player_of_match", "", "3")),
        )
        assertEquals(
            "You played 4 matches this season — every game counts towards the next.",
            highlightText(Highlight("turned_up", "", "4")),
        )
    }

    @Test
    fun `places are words for the top three and a number after`() {
        assertEquals(listOf("Top", "Second", "Third", "No. 7"), listOf(1, 2, 3, 7).map(::place))
        assertEquals(
            "Second for wickets at Lords CC this season.",
            highlightText(Highlight("club_top_wickets", "", "2", "Lords CC")),
        )
    }

    @Test
    fun `milestones read as words, counted ones with their number`() {
        assertEquals("First fifty", milestoneLabel("first_fifty"))
        assertEquals("250 career runs", milestoneLabel("runs_250"))
        assertEquals("50 matches", milestoneLabel("matches_50"))
        assertEquals("some new thing", milestoneLabel("some_new_thing"))
    }

    @Test
    fun `boards, bests and trends have labels`() {
        assertEquals("Most runs", boardLabel("runs"))
        assertEquals("Player of the match", boardLabel("player_of_match"))
        assertEquals("Most sixes in a match", bestLabel("most_sixes"))
        assertEquals(
            "Steady: 45.2 runs an innings over your last five.",
            trendText("steady", 45.2, batting = true),
        )
        assertNull("an unknown trend says nothing", trendText("sideways", 1.0, batting = true))
    }

    @Test
    fun `dates read the way a club would write them`() {
        assertEquals("3 Oct", shortDate("2026-10-03T12:00:00Z", ZoneOffset.UTC))
        assertEquals("2026", yearOf("2026-10-03T12:00:00Z", ZoneOffset.UTC))
        assertEquals("", shortDate("not a date"))
    }

    // MARK: Headline tiles

    @Test
    fun `somebody who never bowled is shown no bowling tiles`() {
        val g = decode<PlayerGame>("player_game_batter")
        val keys = headlineTiles(g.totals, g.previous).map { it.key }
        assertEquals(listOf("matches", "runs", "avg", "sr", "field"), keys)
    }

    @Test
    fun `an all-rounder gets both`() {
        val g = decode<PlayerGame>("player_game_allrounder")
        val tiles = headlineTiles(g.totals, g.previous).associateBy { it.key }
        assertTrue("wkts" in tiles && "econ" in tiles)
        assertEquals("Best 3/21", tiles.getValue("wkts").sub)
    }

    /**
     * A lower number than last season is context, not a mark against. Only
     * an improvement is ever flagged, and "lower is better" for economy.
     */
    @Test
    fun `only an improvement is flagged, never a drop`() {
        val now = Totals(
            matches = 8, battingInnings = 8, runs = 200, battingAverage = 25.0, strikeRate = 90.0,
            bowlingBalls = 120, wickets = 6, economy = 5.5, overs = "20.0",
        )
        val before = Totals(
            matches = 8, battingInnings = 8, runs = 300, battingAverage = 30.0, strikeRate = 80.0,
            bowlingBalls = 120, wickets = 4, economy = 6.0, overs = "20.0",
        )
        val tiles = headlineTiles(now, before).associateBy { it.key }
        assertEquals(false, tiles.getValue("runs").up)
        assertEquals("300", tiles.getValue("runs").was)
        assertEquals(false, tiles.getValue("avg").up)
        assertEquals(true, tiles.getValue("sr").up)
        assertEquals(true, tiles.getValue("wkts").up)
        assertEquals("cheaper is better", true, tiles.getValue("econ").up)
        assertEquals("6.00", tiles.getValue("econ").was)
    }

    @Test
    fun `the season picker always offers this year, newest first`() {
        assertEquals(listOf(2026, 2025, 2023), pickerSeasons(2026, listOf(2023, 2025), listOf(2025)))
        assertEquals(listOf(2026), pickerSeasons(2026, emptyList()))
    }

    // MARK: The push

    @Test
    fun `a season_closed push lands on that season and club`() {
        val link = SeasonLink.fromPush(
            url = "/stats?season=2026&club=$clubId",
            season = "2026",
            clubId = clubId,
            thisYear = 2026,
        )
        assertEquals(SeasonLink(SeasonTab.Mine, 2026, clubId), link)
        // The url alone is enough.
        assertEquals(
            SeasonLink(SeasonTab.Mine, 2026, clubId),
            SeasonLink.fromPush("/stats?season=2026&club=$clubId", thisYear = 2026),
        )
    }

    @Test
    fun `other pushes are not ours, and a silly year is ignored`() {
        assertNull(SeasonLink.fromPush("/chat/abc"))
        assertNull(SeasonLink.fromPush(null))
        assertNull(SeasonLink.fromPush("/stats?season=1066", thisYear = 2026)!!.season)
    }

    // MARK: The model

    private fun clubApi(
        role: String,
        closeResult: () -> SeasonClosed = { error("closeSeason not expected") },
    ) = object : FakeFishersApi() {
        var closed = false
        override suspend fun myClubs() = listOf(Club(clubId, "Hemel Hempstead Town CC"))
        override suspend fun myGame(season: Int?, clubId: String?) = decode<PlayerGame>("player_game_batter")
        override suspend fun clubSeason(clubId: String, season: Int?) =
            decode<ClubSeason>("club_season").copy(closedAt = if (closed) "2026-11-07T12:00:00Z" else null)
        override suspend fun myClubRole(id: String) = decode<MyClubRole>(role)
        override suspend fun closeSeasonPreview(clubId: String, season: Int) = decode<ClosePreview>("close_preview")
        // Closed either way: by this call, or — for a 409 — by somebody first.
        override suspend fun closeSeason(clubId: String, season: Int): SeasonClosed {
            closed = true
            return closeResult()
        }
    }

    @Test
    fun `my game takes the season the API chose`() = runTest(dispatcher.scheduler) {
        val model = SeasonViewModel(clubApi("my_role_player"))
        model.open(SeasonLink())
        advanceUntilIdle()
        assertEquals(2026, model.state.value.season)
        assertEquals("Gary Tucker", model.state.value.game!!.name)
        assertEquals(clubId, model.state.value.clubId)
    }

    @Test
    fun `a player is never shown the close box`() = runTest(dispatcher.scheduler) {
        val model = SeasonViewModel(clubApi("my_role_player"))
        model.open(SeasonLink(SeasonTab.Club, 2026, clubId))
        advanceUntilIdle()
        assertNotNull(model.state.value.club)
        assertNull(model.state.value.preview)
    }

    @Test
    fun `a secretary sees the preview, closes, and the season reads as closed`() =
        runTest(dispatcher.scheduler) {
            val model = SeasonViewModel(clubApi("my_role_secretary", closeResult = { SeasonClosed(2026, 33) }))
            model.open(SeasonLink(SeasonTab.Club, 2026, clubId))
            advanceUntilIdle()
            assertEquals(33, model.state.value.preview!!.willEmail)

            model.close()
            advanceUntilIdle()
            assertEquals(
                "Season closed. 33 emails are on their way over the next few minutes.",
                model.state.value.closeNote,
            )
            assertNotNull(model.state.value.club!!.closedAt)
            assertNull("no box for a closed season", model.state.value.preview)
        }

    @Test
    fun `closed already elsewhere is not an error`() = runTest(dispatcher.scheduler) {
        val conflict = HttpException(Response.error<Any>(409, "{}".toResponseBody()))
        val model = SeasonViewModel(clubApi("my_role_secretary", closeResult = { throw conflict }))
        model.open(SeasonLink(SeasonTab.Club, 2026, clubId))
        advanceUntilIdle()
        model.close()
        advanceUntilIdle()
        assertNull(model.state.value.closeNote)
        assertNull(model.state.value.error)
        assertNotNull(model.state.value.club!!.closedAt)
    }

    @Test
    fun `a club somebody cannot see says so in words`() = runTest(dispatcher.scheduler) {
        val forbidden = HttpException(Response.error<Any>(403, "{}".toResponseBody()))
        val model = SeasonViewModel(object : FakeFishersApi() {
            override suspend fun myClubs() = emptyList<Club>()
            override suspend fun clubSeason(clubId: String, season: Int?): ClubSeason = throw forbidden
        })
        model.open(SeasonLink(SeasonTab.Club, 2026, "someone-elses"))
        advanceUntilIdle()
        assertEquals("Could not load the stats", model.state.value.error)
    }
}
