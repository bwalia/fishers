package com.fishers.app.payments

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A picture of a payment, shrunk to what the server keeps: at most 1600 px and under a megabyte. */
class ScreenshotSizeTest {

    @Test
    fun `a big picture is scaled to 1600 on its long edge, keeping its shape`() {
        assertEquals(1600 to 1200, ScreenshotSize.fit(4000, 3000))
        assertEquals(738 to 1600, ScreenshotSize.fit(1080, 2340))
        assertEquals("a small one is never enlarged", 720 to 1280, ScreenshotSize.fit(720, 1280))
        assertEquals(1600 to 1600, ScreenshotSize.fit(1600, 1600))
    }

    @Test
    fun `a huge photo is decoded at a fraction of its size first, never below the target`() {
        assertEquals(1, ScreenshotSize.sampleSize(1080, 2340))
        assertEquals(4, ScreenshotSize.sampleSize(8000, 6000))
        assertTrue(8000 / ScreenshotSize.sampleSize(8000, 6000) >= ScreenshotSize.MAX_SIDE)
    }

    @Test
    fun `the plan's size and quality come first, and are kept when they fit`() {
        val asked = mutableListOf<Pair<Int, Int>>()
        val bytes = ScreenshotSize.shrink { side, quality ->
            asked += side to quality
            ByteArray(300_000)
        }
        assertEquals(listOf(1600 to 70), asked)
        assertEquals(300_000, bytes?.size)
    }

    @Test
    fun `too big steps down quality, then pixels, until it fits under the limit`() {
        val asked = mutableListOf<Pair<Int, Int>>()
        val small = ByteArray(650_000) { 1 }
        val bytes = ScreenshotSize.shrink { side, quality ->
            asked += side to quality
            if (side >= 1280) ByteArray(1_500_000) else small
        }
        assertEquals(listOf(1600 to 70, 1600 to 55, 1280 to 55, 1024 to 50), asked)
        assertArrayEquals(small, bytes)
        assertTrue(bytes!!.size <= ScreenshotSize.MAX_BYTES)
        // Sent as base64 in JSON (a third bigger), it still fits the server's megabyte.
        assertTrue("under the server's megabyte as base64", ScreenshotSize.MAX_BYTES * 4 / 3 + 64 < 1_000_000)
    }

    @Test
    fun `nothing that fits, or nothing at all, is no picture`() {
        assertNull(ScreenshotSize.shrink { _, _ -> ByteArray(2_000_000) })
        assertNull(ScreenshotSize.shrink { _, _ -> ByteArray(0) })
    }
}
