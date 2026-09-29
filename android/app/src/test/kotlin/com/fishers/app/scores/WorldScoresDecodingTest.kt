package com.fishers.app.scores

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/**
 * `GET /cricket/world-scores` is the one screen whose content comes from
 * outside this project, by way of our own database. Two things can quietly
 * break it: the API renaming a field, and a score arriving as something other
 * than the string cricket actually needs ("128 & 59/5" is not a number). So
 * the payload is pinned to a real response.
 */
class WorldScoresDecodingTest {
    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Captured from `GET /api/v1/cricket/world-scores` against a local API
     * holding real feed data.
     */
    private val captured = """
    {
      "enabled": true,
      "as_of": "2026-09-29T10:35:54.649542Z",
      "live": [
        {
          "id": "54297112",
          "league_name": "Ahmad Shah Abdali 4-day Tournament",
          "league_season": 2026,
          "home_team_name": "Maiwand Champions",
          "home_team_short": "MWC",
          "home_team_logo": "https://highlightly.net/cricket/images/teams/48698372.png",
          "away_team_name": "Pamir Legends",
          "away_team_short": "PAL",
          "away_team_logo": "https://highlightly.net/cricket/images/teams/45984437.png",
          "country_code": "AF",
          "country_name": "Afghanistan",
          "format": "TEST",
          "day_type": "MULTI",
          "start_time": "2026-09-28T05:00:00Z",
          "start_date": "2026-09-28",
          "end_date": "2026-10-01",
          "state": "In play",
          "phase": "live",
          "report": "Day 2 - Maiwand need 390 runs.",
          "home_score": "103 & 15/1",
          "home_info": "4 ov, T:405",
          "away_score": "175 & 332",
          "away_info": null
        }
      ],
      "upcoming": [
        {
          "id": "54314542",
          "league_name": "Big Bash League",
          "league_season": 2026,
          "home_team_name": "Melbourne Renegades",
          "home_team_short": "MR",
          "home_team_logo": null,
          "away_team_name": "Melbourne Stars",
          "away_team_short": "MS",
          "away_team_logo": null,
          "country_code": "AU",
          "country_name": "Australia",
          "format": "T20",
          "day_type": "SINGLE",
          "start_time": "2026-09-29T16:00:00Z",
          "start_date": "2026-09-29",
          "end_date": "2026-09-29",
          "state": "Scheduled",
          "phase": "pending",
          "report": null,
          "home_score": null,
          "home_info": null,
          "away_score": null,
          "away_info": null
        }
      ],
      "recent": []
    }
    """.trimIndent()

    private fun decode(payload: String) = json.decodeFromString<WorldScores>(payload)

    @Test
    fun `decodes the response`() {
        val scores = decode(captured)
        assertTrue(scores.enabled)
        assertEquals(1, scores.live.size)
        assertEquals(1, scores.upcoming.size)
        assertTrue(scores.recent.isEmpty())
    }

    /**
     * Scores are strings because cricket's are: a Test innings reads
     * "103 & 15/1" and no number will hold that.
     */
    @Test
    fun `scores stay strings`() {
        val m = decode(captured).live[0]
        assertEquals("103 & 15/1", m.homeScore)
        assertEquals("175 & 332", m.awayScore)
        assertEquals("4 ov, T:405", m.homeInfo)
        assertNull(m.awayInfo)
    }

    /**
     * The side with an over count against it is the side at the crease. It is
     * the only signal the feed gives, and it is what the screen bolds.
     */
    @Test
    fun `the batting side is the one with an over count`() {
        val m = decode(captured).live[0]
        assertTrue(m.homeBatting)
        assertFalse(m.awayBatting)
    }

    /** A match that has not started has nobody at the crease. */
    @Test
    fun `nobody is batting in a match that has not started`() {
        val next = decode(captured).upcoming[0]
        assertFalse(next.isLive)
        assertFalse(next.homeBatting)
        assertFalse(next.awayBatting)
    }

    /**
     * The start date is a calendar day, not a moment. Parsing it into one in
     * the phone's timezone would file a match under the wrong day.
     */
    @Test
    fun `the start date stays a calendar day`() {
        val m = decode(captured).live[0]
        assertEquals("2026-09-28", m.startDate)
        assertEquals("2026-10-01", m.endDate)
    }

    @Test
    fun `format is title cased for reading`() {
        val scores = decode(captured)
        assertEquals("Test", scores.live[0].formatLabel)
        assertEquals("T20", scores.upcoming[0].formatLabel)
    }

    /**
     * A missing badge must stay missing rather than become an empty URL the
     * row would try to load.
     */
    @Test
    fun `a missing badge falls back to initials`() {
        val next = decode(captured).upcoming[0]
        assertNull(next.homeTeamLogo)
        assertEquals("MR", next.homeInitials)
        assertEquals("MS", next.awayInitials)
    }

    /**
     * Off is a state the screen has to render, not an error: int and test run
     * without a feed key on purpose.
     */
    @Test
    fun `a disabled feed decodes`() {
        val scores = decode("""{"enabled":false,"as_of":null,"live":[],"upcoming":[],"recent":[]}""")
        assertFalse(scores.enabled)
        assertNull(scores.asOf)
        assertEquals("not loaded yet", scores.freshness())
    }

    @Test
    fun `freshness reads as english`() {
        val at = Instant.parse("2026-09-29T12:00:00Z")
        fun ago(mins: Long) =
            WorldScores(enabled = true, asOf = at.toString())
                .freshness(now = at.plusSeconds(mins * 60))
        // Under a minute is "just now", never "0 minutes ago" — which reads
        // like a bug rather than a fresh score.
        assertEquals("just now", ago(0))
        assertEquals("1 minute ago", ago(1))
        assertEquals("7 minutes ago", ago(7))
        assertEquals("1 hour ago", ago(60))
        assertEquals("3 hours ago", ago(180))
    }
}
