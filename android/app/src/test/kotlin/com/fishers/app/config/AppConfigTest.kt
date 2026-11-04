package com.fishers.app.config

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The order is the whole of this class, and getting it wrong points a build at
 * the wrong server without saying so — a debug build that quietly talks to
 * production is the bad end of it.
 */
class AppConfigTest {

    private class FakeStore(private val values: MutableMap<String, String?> = mutableMapOf()) :
        ConfigStore {
        override fun get(key: String) = values[key]
        override fun set(key: String, value: String?) {
            if (value == null) values.remove(key) else values[key] = value
        }
    }

    @Test
    fun `the environment beats everything`() {
        val config = AppConfig(
            store = FakeStore(mutableMapOf(AppConfig.OVERRIDE_KEY to "https://settings.example")),
            debug = true,
            buildTimeApiBase = "https://build.example",
            environment = mapOf(AppConfig.ENV_KEY to "https://env.example"),
        )
        assertEquals("https://env.example", config.apiBaseUrl)
    }

    @Test
    fun `the settings panel beats the build`() {
        val config = AppConfig(
            store = FakeStore(mutableMapOf(AppConfig.OVERRIDE_KEY to "https://settings.example")),
            debug = false,
            buildTimeApiBase = "https://build.example",
            environment = emptyMap(),
        )
        assertEquals("https://settings.example", config.apiBaseUrl)
    }

    @Test
    fun `a debug build with nothing set reaches the emulator's host, not production`() {
        val config = AppConfig(FakeStore(), debug = true, environment = emptyMap())
        assertEquals("http://10.0.2.2:7312", config.apiBaseUrl)
    }

    @Test
    fun `a release build with nothing set reaches production`() {
        val config = AppConfig(FakeStore(), debug = false, environment = emptyMap())
        assertEquals(AppConfig.DEVICE_API_BASE, config.apiBaseUrl)
    }

    @Test
    fun `the port follows env, because dotenv moves it`() {
        val config = AppConfig(
            FakeStore(),
            debug = true,
            environment = mapOf(AppConfig.API_PORT_KEY to "9999"),
        )
        assertEquals("http://10.0.2.2:9999", config.apiBaseUrl)
    }

    @Test
    fun `blank is not an answer, at any level`() {
        val config = AppConfig(
            store = FakeStore(mutableMapOf(AppConfig.OVERRIDE_KEY to "   ")),
            debug = false,
            buildTimeApiBase = "",
            environment = mapOf(AppConfig.ENV_KEY to ""),
        )
        assertEquals(AppConfig.DEVICE_API_BASE, config.apiBaseUrl)
    }

    @Test
    fun `everything hangs off api v1, with no doubled slash`() {
        val config = AppConfig(
            FakeStore(),
            debug = false,
            buildTimeApiBase = "https://int.fishers.cloud/",
            environment = emptyMap(),
        )
        assertEquals("https://int.fishers.cloud/api/v1", config.apiV1)
    }

    // ---- what a build carries as its own server ----

    /**
     * The store build. CI passes no explicit URL, so this is the whole of what a
     * Gully Cricket install knows — and it used to know Fishers', which would
     * have signed its players into somebody else's database.
     */
    @Test
    fun `a release build with no explicit url is its own brand's production host`() {
        val baked = AppConfig.bakedApiBase(explicit = "", debug = false, brandHost = "www.gullycricket.app")
        val config = AppConfig(FakeStore(), debug = false, buildTimeApiBase = baked, environment = emptyMap())

        assertEquals("https://www.gullycricket.app/api/v1", config.apiV1)
    }

    @Test
    fun `an explicit url wins, so a developer can point a build at int`() {
        assertEquals(
            "https://int.gullycricket.app",
            AppConfig.bakedApiBase("https://int.gullycricket.app", debug = false, brandHost = "www.gullycricket.app"),
        )
    }

    @Test
    fun `a debug build keeps its loopback fallback rather than quietly using production`() {
        assertNull(AppConfig.bakedApiBase(explicit = "", debug = true, brandHost = "www.gullycricket.app"))
    }

    @Test
    fun `a blank url is no url`() {
        assertEquals(
            "https://www.fishers.cloud",
            AppConfig.bakedApiBase(explicit = "   ", debug = false, brandHost = "www.fishers.cloud"),
        )
    }
}
