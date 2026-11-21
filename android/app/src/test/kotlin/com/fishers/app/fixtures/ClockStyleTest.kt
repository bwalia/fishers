package com.fishers.app.fixtures

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalTime
import java.time.ZoneOffset

/**
 * Every time on screen follows the phone's clock, as the schedule form's does.
 * Home said "18:30" while the form beside it said "6:30 PM".
 */
class ClockStyleTest {

    @After
    fun reset() {
        ClockStyle.is24Hour = true
    }

    @Test
    fun `a 24-hour phone reads 24-hour times everywhere`() {
        ClockStyle.is24Hour = true
        assertEquals("Sat 14 Nov, 18:30", formatWhen("2026-11-14T18:30:00Z", ZoneOffset.UTC))
        assertEquals("18:30", formatTime(LocalTime.of(18, 30)))
    }

    @Test
    fun `a 12-hour phone reads 12-hour times everywhere`() {
        ClockStyle.is24Hour = false
        val home = formatWhen("2026-11-14T18:30:00Z", ZoneOffset.UTC)
        assertTrue(home, home.startsWith("Sat 14 Nov, 6:30"))
        assertFalse(home, home.contains("18:30"))
        val time = formatTime(LocalTime.of(18, 30))
        assertTrue(time, time.startsWith("6:30"))
        val span = formatSpan("2026-11-14T13:00:00Z", "2026-11-14T15:00:00Z", ZoneOffset.UTC)
        assertTrue(span, span.contains("1:00") && span.contains("3:00") && !span.contains("13:00"))
    }
}
