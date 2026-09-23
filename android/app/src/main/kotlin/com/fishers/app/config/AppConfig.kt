package com.fishers.app.config

import android.content.Context

/**
 * Where the server address is remembered between launches. An interface rather
 * than `SharedPreferences` directly, so the resolution order below can be
 * tested on the JVM without an emulator — the same shape
 * `flutter/lib/config/app_config.dart` settled on for the same reason.
 */
interface ConfigStore {
    fun get(key: String): String?
    fun set(key: String, value: String?)
}

/**
 * Which server this install talks to — a port of `ios/Fishers/Config/AppConfig.swift`,
 * following `flutter/lib/config/app_config.dart` where that had already worked
 * out what Android does differently.
 *
 * Resolution order, most specific first, the same four sources as iOS:
 *
 *  1. `FISHERS_API_URL` in the process environment — an instrumented test, or
 *     CI. Wins over the settings panel, as the Xcode scheme does.
 *  2. `FishersAPIBaseURL` in the store — the settings panel. iOS keeps this in
 *     `UserDefaults`; here it is `SharedPreferences`.
 *  3. The value baked in at build time, which is what Info.plist is on iOS for
 *     Release and the store builds.
 *  4. Fallback: a debug build reaches for the host machine's loopback as the
 *     emulator sees it; a release build reaches for production.
 *
 * Every source is re-read on each access, the way iOS does it, so changing the
 * server in settings applies to the next request without a restart.
 */
class AppConfig(
    private val store: ConfigStore,
    private val debug: Boolean,
    private val buildTimeApiBase: String? = null,
    private val environment: Map<String, String> = System.getenv(),
) {
    val apiBaseUrl: String
        get() = environment[ENV_KEY].orNullIfBlank()
            ?: store.get(OVERRIDE_KEY).orNullIfBlank()
            ?: buildTimeApiBase.orNullIfBlank()
            ?: if (debug) emulatorApiBase else DEVICE_API_BASE

    /** Everything the app calls hangs off this. `/clubs` → `<base>/api/v1/clubs`. */
    val apiV1: String get() = "${apiBaseUrl.trimEnd('/')}/api/v1"

    fun setApiBaseUrlOverride(value: String?) =
        store.set(OVERRIDE_KEY, value.orNullIfBlank()?.trimEnd('/'))

    /**
     * An emulator's own 127.0.0.1 is the emulator, so the address that reaches
     * `scripts/start.sh` on the developer's Mac is 10.0.2.2. This is the one
     * substantive difference from iOS, whose Simulator shares the Mac's stack.
     *
     * The port is not hard-coded against `.env`, which moves it: a default that
     * contradicts the stack it is meant to reach is worse than none, because
     * the app then quietly talks to nothing.
     */
    private val emulatorApiBase: String
        get() = "http://10.0.2.2:${environment[API_PORT_KEY].orNullIfBlank() ?: DEFAULT_API_PORT}"

    private fun String?.orNullIfBlank(): String? = this?.takeIf { it.isNotBlank() }

    companion object {
        const val ENV_KEY = "FISHERS_API_URL"
        const val OVERRIDE_KEY = "FishersAPIBaseURL"
        const val API_PORT_KEY = "API_PORT"

        /** `scripts/start.sh`'s own default, off the beaten track so the stack
         *  does not fight Postgres on 5432 or another dev server on 8080. */
        const val DEFAULT_API_PORT = "7312"
        const val DEVICE_API_BASE = "https://www.fishers.cloud"

        private const val PREFS = "fishers.config"

        fun from(context: Context, debug: Boolean, buildTimeApiBase: String? = null): AppConfig {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return AppConfig(
                store = object : ConfigStore {
                    override fun get(key: String) = prefs.getString(key, null)
                    override fun set(key: String, value: String?) =
                        prefs.edit().apply {
                            if (value == null) remove(key) else putString(key, value)
                        }.apply()
                },
                debug = debug,
                buildTimeApiBase = buildTimeApiBase,
            )
        }
    }
}
