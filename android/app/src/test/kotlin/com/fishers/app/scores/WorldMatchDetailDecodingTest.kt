package com.fishers.app.scores

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The scorecard page's payload, pinned to a real four-innings Test.
 *
 * Four innings is the case that matters: two of them belong to each side, so
 * the team name alone will not tell them apart, and everything the tabs say
 * depends on getting that right.
 */
class WorldMatchDetailDecodingTest {
    private val json = Json { ignoreUnknownKeys = true }

    /** Captured from `GET /api/v1/cricket/world-scores/54297112`. */
    private val captured = """
{
  "summary": {
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
    "report": "Day 2 - Maiwand need 296 runs.",
    "home_score": "103 & 109/7",
    "home_info": "24 ov, T:405",
    "away_score": "175 & 332",
    "away_info": null
  },
  "detail": {
    "venue": null,
    "batting_now": [
      {
        "name": "Asghar Atal",
        "team_name": "Maiwand Champions",
        "line": "0"
      }
    ],
    "bowling_now": [
      {
        "name": "Nasim Mangal",
        "team_name": "Pamir Legends",
        "line": "3/33 (8.2 ov)"
      }
    ],
    "innings": [
      {
        "team_name": "Pamir Legends",
        "team_short": "PAL",
        "team_logo": "https://highlightly.net/cricket/images/teams/45984437.png",
        "total_runs": 175,
        "wickets": 10,
        "batting": [
          {
            "name": "Usman Noori",
            "runs": 0,
            "balls": 5,
            "fours": 0,
            "sixes": 0,
            "strike_rate": 0.0,
            "how_out": "lbw b Bilal Sami",
            "not_out": false
          },
          {
            "name": "Jalat Khan",
            "runs": 12,
            "balls": 22,
            "fours": 1,
            "sixes": 0,
            "strike_rate": 54.54,
            "how_out": "c Shams Ur Rahman b Bilal Sami",
            "not_out": false
          }
        ],
        "bowling": [
          {
            "name": "Nijat Masood",
            "overs": 6.0,
            "maidens": 1,
            "runs": 30,
            "wickets": 0,
            "economy": 5.0
          }
        ],
        "fall_of_wickets": [
          {
            "wicket": 1,
            "runs": 3,
            "overs": 1.3,
            "batter": "Usman Noori"
          }
        ],
        "extras": {
          "total": 2,
          "byes": 0,
          "leg_byes": 2,
          "wides": 0,
          "no_balls": 0
        }
      },
      {
        "team_name": "Maiwand Champions",
        "team_short": "MWC",
        "team_logo": "https://highlightly.net/cricket/images/teams/48698372.png",
        "total_runs": 103,
        "wickets": 10,
        "batting": [
          {
            "name": "Asghar Atal",
            "runs": 13,
            "balls": 7,
            "fours": 2,
            "sixes": 0,
            "strike_rate": 185.71,
            "how_out": "b Nasim Mangal",
            "not_out": false
          },
          {
            "name": "Khalid Ahmadzai",
            "runs": 0,
            "balls": 1,
            "fours": 0,
            "sixes": 0,
            "strike_rate": 0.0,
            "how_out": "lbw b Fareed Ahmad",
            "not_out": false
          }
        ],
        "bowling": [
          {
            "name": "Fareed Ahmad",
            "overs": 10.0,
            "maidens": 0,
            "runs": 51,
            "wickets": 5,
            "economy": 5.1
          }
        ],
        "fall_of_wickets": [
          {
            "wicket": 1,
            "runs": 7,
            "overs": 0.3,
            "batter": "Khalid Ahmadzai"
          }
        ],
        "extras": {
          "total": 10,
          "byes": 4,
          "leg_byes": 4,
          "wides": 0,
          "no_balls": 2
        }
      },
      {
        "team_name": "Pamir Legends",
        "team_short": "PAL",
        "team_logo": "https://highlightly.net/cricket/images/teams/45984437.png",
        "total_runs": 332,
        "wickets": 10,
        "batting": [
          {
            "name": "Usman Noori",
            "runs": 10,
            "balls": 12,
            "fours": 1,
            "sixes": 0,
            "strike_rate": 83.33,
            "how_out": "b Bilal Sami",
            "not_out": false
          },
          {
            "name": "Jalat Khan",
            "runs": 32,
            "balls": 46,
            "fours": 4,
            "sixes": 0,
            "strike_rate": 69.56,
            "how_out": "c Bilal Sami b Abdullah Tarakhail",
            "not_out": false
          }
        ],
        "bowling": [
          {
            "name": "Nijat Masood",
            "overs": 20.0,
            "maidens": 0,
            "runs": 108,
            "wickets": 2,
            "economy": 5.4
          }
        ],
        "fall_of_wickets": [
          {
            "wicket": 1,
            "runs": 17,
            "overs": 3.3,
            "batter": "Usman Noori"
          }
        ],
        "extras": {
          "total": 18,
          "byes": 9,
          "leg_byes": 9,
          "wides": 0,
          "no_balls": 0
        }
      },
      {
        "team_name": "Maiwand Champions",
        "team_short": "MWC",
        "team_logo": "https://highlightly.net/cricket/images/teams/48698372.png",
        "total_runs": 110,
        "wickets": 9,
        "batting": [
          {
            "name": "Khalid Ahmadzai",
            "runs": 8,
            "balls": 15,
            "fours": 1,
            "sixes": 0,
            "strike_rate": 53.33,
            "how_out": "c Fareed Ahmad b Nasim Mangal",
            "not_out": false
          },
          {
            "name": "Majeed Alam",
            "runs": 0,
            "balls": 3,
            "fours": 0,
            "sixes": 0,
            "strike_rate": 0.0,
            "how_out": "lbw b Fareed Ahmad",
            "not_out": false
          }
        ],
        "bowling": [
          {
            "name": "Fareed Ahmad",
            "overs": 9.0,
            "maidens": 0,
            "runs": 48,
            "wickets": 2,
            "economy": 5.33
          }
        ],
        "fall_of_wickets": [
          {
            "wicket": 1,
            "runs": 3,
            "overs": 0.4,
            "batter": "Majeed Alam"
          }
        ],
        "extras": {
          "total": 6,
          "byes": 0,
          "leg_byes": 5,
          "wides": 0,
          "no_balls": 1
        }
      }
    ]
  },
  "detail_as_of": "2026-09-29T12:23:59.704171183Z"
}
""".trimIndent()

    private fun decode() = json.decodeFromString<WorldMatchDetailView>(captured)

    @Test
    fun `decodes the whole page`() {
        val v = decode()
        assertNotNull(v.detail)
        assertEquals(4, v.detail!!.innings.size)
        assertNotNull(v.detailAsOf)
    }

    /**
     * Two innings each, so a label has to carry the ordinal or two tabs read
     * identically.
     */
    @Test
    fun `tab labels tell the two innings of a side apart`() {
        val inns = decode().detail!!.innings
        assertEquals("PAL 1st", inns.tabLabel(0))
        assertEquals("MWC 1st", inns.tabLabel(1))
        assertEquals("PAL 2nd", inns.tabLabel(2))
        assertEquals("MWC 2nd", inns.tabLabel(3))
    }

    /** The heading has the room the tab does not. */
    @Test
    fun `the heading says the name in full`() {
        val inns = decode().detail!!.innings
        assertEquals("Pamir Legends · 1st innings", inns.title(0))
        assertEquals("Maiwand Champions · 2nd innings", inns.title(3))
    }

    /**
     * A side's score across the match. An innings all out shows just the runs;
     * one still going shows the wickets too — which is how the feed writes it.
     */
    @Test
    fun `a side's score reads across both its innings`() {
        val inns = decode().detail!!.innings
        assertEquals("175 & 332", inns.sideScore("Pamir Legends"))
        // 103 all out, then 110 for 9 and still batting.
        assertEquals("103 & 110/9", inns.sideScore("Maiwand Champions"))
        assertNull(inns.sideScore("Nobody CC"))
    }

    @Test
    fun `an innings knows its own score`() {
        val inns = decode().detail!!.innings
        assertEquals("175-10", inns[0].score)
        assertEquals("110-9", inns[3].score)
    }

    /**
     * The dismissal arrives already written. If it ever becomes parts again,
     * three clients start inventing three different phrasings.
     */
    @Test
    fun `the dismissal is a composed phrase`() {
        val batting = decode().detail!!.innings.flatMap { it.batting }
        assertTrue(batting.isNotEmpty())
        assertTrue(batting.all { it.howOut.isNotBlank() })
    }

    /** "did not bat" is not "not out", and the bottom of a card is where it shows. */
    @Test
    fun `not out and did not bat are different`() {
        val batting = decode().detail!!.innings.flatMap { it.batting }
        batting.filter { it.howOut == "did not bat" }.forEach {
            assertFalse(it.notOut)
            assertNull(it.runs)
        }
        batting.filter { it.notOut }.forEach { assertEquals("not out", it.howOut) }
    }

    /** The crease lines are composed server-side too, for the same reason. */
    @Test
    fun `the crease lines arrive ready to print`() {
        val d = decode().detail!!
        assertTrue(d.battingNow.first().line.isNotBlank())
        assertTrue(d.bowlingNow.first().line.contains("ov"))
    }

    @Test
    fun `extras break down into words or nothing`() {
        val extras = decode().detail!!.innings.first().extras
        assertNotNull(extras.total)
        // Only the ones that happened; never an empty pair of brackets.
        extras.breakdown?.let { assertFalse(it.isBlank()) }
    }

    /** A match nobody has opened yet has no card, and that is not an error. */
    @Test
    fun `a match with no scorecard decodes`() {
        val summary = captured.substringAfter("\"summary\":").substringBeforeLast(",\n  \"detail\"")
        val v = json.decodeFromString<WorldMatchDetailView>(
            """{"summary":$summary,"detail":null,"detail_as_of":null}""",
        )
        assertNull(v.detail)
        assertEquals("not loaded yet", v.freshness())
    }
}
