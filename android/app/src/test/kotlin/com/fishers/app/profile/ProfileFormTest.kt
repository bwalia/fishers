package com.fishers.app.profile

import com.fishers.app.EnglishStrings
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** What an edit sends, and what the server's answer reads as. */
class ProfileFormTest {
    @get:Rule val english = EnglishStrings()

    /** The configuration `Network` builds Retrofit with: what goes over the wire is this. */
    private val wire = Json { ignoreUnknownKeys = true; explicitNulls = false }

    private val ravi = Me(
        id = "u1",
        name = "Ravi Patel",
        phone = "07700 900123",
        primarySport = "cricket",
        sportProfiles = listOf(
            SportProfile(sport = "cricket", position = "Spinner", skillLevel = "Club standard", stats = mapOf("bowling_style" to "Off-spin")),
            SportProfile(sport = "football", position = "Defender"),
        ),
        location = PlayerLocation(area = "Hemel", transport = "driverWithSeats", spareSeats = 2, preferredDays = listOf(7, 1)),
    )

    @Test
    fun `a profile read into the form goes back unchanged`() {
        val update = ProfileForm.from(ravi).toUpdate()

        assertEquals("Ravi Patel", update.name)
        assertEquals("07700 900123", update.phone)
        assertEquals("cricket", update.primarySport)
        assertEquals(listOf("cricket", "football"), update.sportsPlayed)
        assertEquals(ravi.sportProfiles, update.sportProfiles)
        // The flat fields mirror the main sport, for list views.
        assertEquals("Spinner", update.positionRole)
        assertEquals("Club standard", update.skillLevel)
        assertEquals("Hemel", update.location?.area)
        assertEquals(2, update.location?.spareSeats)
        assertEquals(listOf(1, 7), update.location?.preferredDays)
    }

    @Test
    fun `dropping a sport forgets its details and hands the main sport on`() {
        val form = ProfileForm.from(ravi).toggle(Sport.Cricket)

        assertEquals(listOf(Sport.Football), form.selectedSports)
        assertEquals(Sport.Football, form.primarySport)
        // Picking it again starts clean, as iOS does.
        assertNull(form.toggle(Sport.Cricket).detail(Sport.Cricket).position)
    }

    /**
     * `encodeDefaults` is off, so a field equal to its default is not written.
     * Every sport deselected must still go up as `[]`, or the server keeps the
     * old ones — while a blank phone must stay out, which the server reads as
     * "unchanged" rather than wiping it.
     */
    @Test
    fun `an emptied sport list is still sent, and a blank field is left out`() {
        val form = ProfileForm.from(ravi).toggle(Sport.Cricket).toggle(Sport.Football).copy(phone = "  ")
        val body = wire.parseToJsonElement(wire.encodeToString(form.toUpdate())).jsonObject

        assertEquals(0, body.getValue("sport_profiles").jsonArray.size)
        assertEquals(0, body.getValue("sports_played").jsonArray.size)
        assertFalse("blank phone is not sent", "phone" in body)
        assertFalse("no main sport is not sent", "primary_sport" in body)
    }

    @Test
    fun `spare seats only go up for somebody who offers lifts`() {
        val driver = ProfileForm.from(ravi).copy(transport = TransportMode.Driver, spareSeats = 3)
        assertNull(driver.toUpdate().location?.spareSeats)
        assertEquals("driver", driver.toUpdate().location?.transport)
    }

    @Test
    fun `a profile saved as padel comes back as paddle`() {
        val old = ravi.copy(primarySport = "padel", sportProfiles = listOf(SportProfile(sport = "padel", position = "Left side")))
        val update = ProfileForm.from(old).toUpdate()

        assertEquals("paddle", update.primarySport)
        assertEquals("Left side", update.sportProfiles.single().position)
        assertEquals("paddle", update.sportProfiles.single().sport)
    }

    @Test
    fun `a stat cleared to blank is removed rather than stored empty`() {
        val form = ProfileForm.from(ravi).withStat(Sport.Cricket, "bowling_style", "")
        assertFalse("bowling_style" in form.detail(Sport.Cricket).stats)
        val set = form.withStat(Sport.Cricket, "batting_number", "3")
        assertEquals("3", set.detail(Sport.Cricket).stats["batting_number"])
    }

    @Test
    fun `a typed number is held to the field's range`() {
        assertEquals("11", SportStats.clampWhole("15", 1..11))
        assertEquals("1", SportStats.clampWhole("0", 1..11))
        assertEquals("42", SportStats.clampWhole("4a2", 0..999))
        assertEquals("", SportStats.clampWhole("abc", 0..999))
    }

    @Test
    fun `a standard is stored as iOS stores it and read either way`() {
        assertEquals("Club standard", SkillTier.Club.wire)
        assertEquals("Advanced", SkillTier.Advanced.wire)
        assertEquals(SkillTier.Club, SkillTier.stored("Club standard"))
        assertEquals(SkillTier.Club, SkillTier.stored("club"))
        assertEquals(SkillTier.Elite, SkillTier.stored("ELITE"))
        assertNull(SkillTier.stored("superstar"))
    }

    @Test
    fun `a stored stat reads in words on the profile`() {
        val summary = SportStats.summary(ravi.sportProfiles.first())
        assertEquals(listOf("Bowling" to "Off-spin"), summary)
    }

    /** The real `/me`, with fields this app does not read: they must not stop it decoding. */
    @Test
    fun `the server's whole user decodes`() {
        val json = """
            {"id":"u1","name":"Ravi Patel","email":"r@x.test","phone":null,"avatar_url":null,
             "sports_played":["cricket"],"position_role":null,"skill_level":null,"emergency_contact":null,
             "primary_sport":"cricket","sport_profiles":[{"sport":"cricket","stats":{}}],"location":null,
             "profile_complete":false,"email_verified":true,"phone_verified":false,"role_intent":"player",
             "profile_strength":{"percent":45,"missing":["photo"],"next_up":"Add a photo"},
             "reliability":{"score":0,"attendance_rate":0.0,"response_rate":0.0,"payment_rate":1.0,
                            "late_cancellations":0,"sample_size":0,"band":"unproven"},
             "platform_admin":false}
        """.trimIndent()
        val me = wire.decodeFromString<Me>(json)

        assertTrue(me.isVerified)
        assertEquals("cricket", me.primaryProfile?.sport)
        assertTrue(me.reliability!!.isUnproven)
        assertEquals("player", me.toPublicUser().roleIntent)
    }
}

/** How full a profile is — the same arithmetic as the server's `ProfileStrength::of`. */
class ProfileStrengthTest {
    @get:Rule val english = EnglishStrings()

    private val bare = Me(id = "u1", name = "Pat Player", email = "pat@x.test")

    @Test
    fun `a new account has its name and little else`() {
        val strength = ProfileStrength(bare)
        assertEquals(10, strength.percent)
        assertEquals("Add what you play, a photo and the standard you play at", strength.nextUp)
        assertEquals("sport", strength.missing.first().id)
    }

    @Test
    fun `the quick start is a third of the way`() {
        val strength = ProfileStrength(
            bare.copy(phone = "07700900123", primarySport = "cricket", sportProfiles = listOf(SportProfile("cricket"))),
        )
        assertEquals(35, strength.percent)
        assertEquals("Add a photo, the standard you play at and your position", strength.nextUp)
    }

    @Test
    fun `everything filled in is complete`() {
        val strength = ProfileStrength(
            bare.copy(
                phone = "07700900123",
                avatarUrl = "https://x/p.jpg",
                emergencyContact = "Mum",
                emailVerified = true,
                primarySport = "cricket",
                sportProfiles = listOf(SportProfile("cricket", skillLevel = "Club", position = "Batter")),
                location = PlayerLocation(area = "Hemel", transport = "driver"),
            ),
        )
        assertTrue(strength.isComplete)
        assertEquals("", strength.nextUp)
    }
}

/** Career figures: sums first, averages from the sums. */
class TotalsTest {
    @get:Rule val english = EnglishStrings()

    private fun season(year: Int, runs: Int, innings: Int, notOuts: Int, overs: Double = 0.0, conceded: Int = 0, wickets: Int = 0) =
        PlayerSeasonStats(
            id = "$year", seasonYear = year, runs = runs, battingInnings = innings, notOuts = notOuts,
            oversBowled = overs, bowlingRuns = conceded, wickets = wickets, matches = innings,
        )

    @Test
    fun `the career average comes from the sums, not from averaging averages`() {
        // 100 in 2 outs (50.0) and 10 in 10 outs (1.0): averaging those says
        // 25.5; the career is 110 runs in 12 outs.
        val totals = Totals(listOf(season(2025, 100, 3, 1), season(2026, 10, 10, 0)))
        assertEquals(110.0 / 12, totals.battingAverage!!, 1e-9)
    }

    @Test
    fun `never out is no average at all`() {
        assertNull(Totals(listOf(season(2026, 40, 2, 2))).battingAverage)
        assertEquals("—", figure(null))
        assertEquals("24.50", figure(24.5))
    }

    @Test
    fun `the best economy is the lowest one`() {
        val rows = listOf(
            season(2025, 0, 0, 0, overs = 10.0, conceded = 60, wickets = 2),
            season(2026, 0, 0, 0, overs = 10.0, conceded = 35, wickets = 1),
        )
        val economy = careerHighlights(rows, batting = false).first { it.labelKey == "rest.best_economy" }
        assertEquals("3.50", economy.value)
        assertEquals(2026, economy.season)
    }

    @Test
    fun `the club named is the one played for most`() {
        val rows = listOf(
            PlayerSeasonStats(id = "1", seasonYear = 2025, matches = 3, clubName = "Lords CC"),
            PlayerSeasonStats(id = "2", seasonYear = 2026, matches = 9, clubName = "Hemel CC"),
        )
        assertEquals("Hemel CC", mainClub(rows, "Typed Team"))
        assertEquals("Typed Team", mainClub(emptyList(), "Typed Team"))
    }
}
