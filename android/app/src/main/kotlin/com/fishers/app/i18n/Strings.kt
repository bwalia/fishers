package com.fishers.app.i18n

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONObject

/**
 * What the app says, in the language the person reads.
 *
 * The same dictionary the website and the iPhone app use, generated into
 * assets/strings/ by tools/i18n. The rules below are the web's rules,
 * deliberately — a club whose secretary reads Punjabi on a laptop, a phone and
 * a tablet is one product, and three sets of plural rules would be three
 * products that disagree about what a wicket is called.
 *
 *   - a key is `area.thing`, and `t("nav.home")` returns it
 *   - `{name}` in a string is replaced from `vars`
 *   - a plural is two keys, `.one` and `.other`, picked by `count`
 *   - **fallback is per key, not per language**: a half-translated language
 *     shows what it has and English for the rest. Falling back to the key
 *     would put `moment.hat_trick` on a live scoreboard.
 */
object Strings {
    private var tables: Map<Language, Map<String, String>> = emptyMap()

    /**
     * The reader's language.
     *
     * A Compose state, so every composable that calls [t] re-reads it and
     * redraws itself when this changes. That is the whole mechanism — no
     * provider to thread down, and no activity recreation.
     */
    var language by mutableStateOf(Language.fallback)
        private set

    private const val PREFS = "fishers.i18n"
    private const val KEY = "language"

    /** Call once, before anything draws. */
    fun load(context: Context) {
        if (tables.isNotEmpty()) return
        tables = Language.entries.associateWith { read(context, it) }
        val saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
        // No saved choice means whatever the phone is already set to, which is
        // the best guess available for somebody who has never opened the picker.
        language = if (saved != null) Language.from(saved) else Language.from(systemTag())
    }

    fun set(context: Context, next: Language) {
        if (next == language) return
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, next.code).apply()
        language = next
    }

    private fun systemTag(): String =
        android.content.res.Resources.getSystem().configuration.locales[0]?.language ?: Language.fallback.code

    private fun read(context: Context, language: Language): Map<String, String> =
        runCatching {
            val text = context.assets.open("strings/${language.code}.json").bufferedReader().use { it.readText() }
            val json = JSONObject(text)
            buildMap(json.length()) {
                for (key in json.keys()) put(key, json.getString(key))
            }
        // Not fatal on purpose: a missing table means that language falls back
        // to English, which is a worse app rather than no app.
        }.getOrDefault(emptyMap())

    /**
     * The key a lookup should actually use. With a count, the plural form if
     * the dictionary has one; without, the key itself — and for a plural stem
     * asked without a count, the `.other` form, because the general wording
     * beats printing the stem.
     */
    fun resolve(key: String, count: Int?): String {
        val english = tables[Language.fallback].orEmpty()
        if (count != null) {
            val form = "$key.${if (count == 1) "one" else "other"}"
            if (english.containsKey(form)) return form
        }
        if (english.containsKey(key)) return key
        val other = "$key.other"
        return if (english.containsKey(other)) other else key
    }

    fun get(key: String, language: Language, count: Int? = null, vars: Map<String, Any> = emptyMap()): String {
        val form = resolve(key, count)
        var out = tables[language]?.get(form) ?: tables[Language.fallback]?.get(form) ?: form
        if (count != null && !vars.containsKey("count")) {
            out = out.replace("{count}", count.toString())
        }
        for ((name, value) in vars) out = out.replace("{$name}", value.toString())
        return out
    }

    /** Every key the tables carry, for the test that checks what the app asks for. */
    fun keys(language: Language): Set<String> = tables[language].orEmpty().keys
}

/**
 * `t("nav.home")` — the same call the web and the iPhone app make.
 *
 * Reading [Strings.language] inside a composable is what subscribes it, so a
 * screen redraws in the new language the moment the picker is used.
 */
fun t(key: String, count: Int? = null, vars: Map<String, Any> = emptyMap()): String =
    Strings.get(key, Strings.language, count, vars)
