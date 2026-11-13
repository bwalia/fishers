package com.fishers.app.cricket

import com.fishers.app.EnglishStrings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class MatchViewTest {
    @get:Rule val english = EnglishStrings()

    private fun chase(oversAvailable: Int) = MatchView(
        status = "live",
        conditions = ConditionsView(oversLimit = 5),
        innings = listOf(
            InningsView(index = 0, oversAvailable = 5, complete = true),
            InningsView(
                index = 1,
                strikerId = "babar",
                nonStrikerId = "imran",
                oversAvailable = oversAvailable,
                batters = listOf(BatterView("babar", runs = 12, balls = 2), BatterView("imran"), BatterView("shadab")),
            ),
        ),
    )

    @Test
    fun `a non-striker who has not faced yet is not out, and the rest did not bat`() {
        val view = chase(oversAvailable = 5)
        val inn = view.innings[1]
        assertEquals("not out", view.dismissalText(inn.batter("imran")!!))
        assertEquals("did not bat", view.dismissalText(inn.batter("shadab")!!))
    }

    @Test
    fun `DLS only comes into it when overs were lost`() {
        assertFalse("an uninterrupted five-over chase", chase(oversAvailable = 5).oversWereLost)
        assertTrue("rain took an over off the chase", chase(oversAvailable = 4).oversWereLost)
    }
}
