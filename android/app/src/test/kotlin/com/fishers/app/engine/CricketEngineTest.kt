package com.fishers.app.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.fishers_ffi.EngineException
import uniffi.fishers_ffi.applyEvent
import uniffi.fishers_ffi.engineVersion
import uniffi.fishers_ffi.replayMatch
import uniffi.fishers_ffi.wouldAccept

/**
 * These call the real engine — the same Rust the server scores with, through
 * the generated bindings, loaded by JNA from the host build.
 *
 * That is the point of them. A test against a Kotlin reimplementation would
 * only prove the reimplementation agreed with itself; the whole reason this
 * engine is shared is that three hand-written copies of the Laws drifted apart
 * twice in a week. If these pass, the phone and the server are running the same
 * rules, because they are running the same code.
 */
class CricketEngineTest {

    private val prepared = """
        [{"client_event_id":"3f2504e0-4f89-41d3-9a0c-0305e82c3301","seq":1,
          "kind":{"type":"match_prepared","overs_limit":20,
                  "home_name":"Lords","away_name":"Hemel"}}]
    """.trimIndent()

    @Test
    fun `a log replays into a state`() {
        val state = replayMatch(prepared)
        assertTrue("the names come back", state.contains("Lords"))
        assertTrue("and the format", state.contains("\"overs_limit\":20"))
    }

    @Test
    fun `the engine refuses what it should, in its own words`() {
        val fresh = replayMatch("[]")
        val endIt = """
            {"client_event_id":"3f2504e0-4f89-41d3-9a0c-0305e82c3302","seq":1,
             "kind":{"type":"innings_completed"}}
        """.trimIndent()

        val refusal = runCatching { applyEvent(fresh, endIt) }.exceptionOrNull()
        assertTrue("a refusal, not a crash", refusal is EngineException.Refused)
        assertTrue("and it says why", (refusal as EngineException.Refused).detail.isNotBlank())
    }

    @Test
    fun `malformed input is named as malformed, not treated as a refusal`() {
        val err = runCatching { replayMatch("not json") }.exceptionOrNull()
        assertTrue(err is EngineException.Malformed)
        assertEquals("an event log", (err as EngineException.Malformed).what)
    }

    @Test
    fun `wouldAccept agrees with applyEvent, so a button can be disabled honestly`() {
        val fresh = replayMatch("[]")
        val endIt = """
            {"client_event_id":"3f2504e0-4f89-41d3-9a0c-0305e82c3303","seq":1,
             "kind":{"type":"innings_completed"}}
        """.trimIndent()
        assertFalse(wouldAccept(fresh, endIt))
        assertTrue(runCatching { applyEvent(fresh, endIt) }.isFailure)
    }

    @Test
    fun `the engine says which rules it is carrying`() {
        assertTrue(engineVersion().isNotBlank())
    }
}
