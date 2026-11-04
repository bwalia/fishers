package com.fishers.app

import com.fishers.app.i18n.Language
import com.fishers.app.i18n.Strings
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.rules.ExternalResource
import java.io.File

/**
 * The app's own words, for tests that assert on them.
 *
 * Reads the JSON files under `src/main/assets/strings` — the ones tools/i18n
 * generates and the app ships — rather than a copy, so a test checks what a person would see
 * and a reworded string fails here instead of drifting. Gradle runs unit tests
 * from the module directory, which is what makes the relative path right.
 */
object TestStrings {
    fun install() {
        val dir = File("src/main/assets/strings")
        Strings.install(
            Language.entries.associateWith { language ->
                val text = File(dir, "${language.code}.json").readText()
                Json.parseToJsonElement(text).jsonObject.mapValues { it.value.jsonPrimitive.content }
            },
        )
    }
}

/** `@get:Rule val english = EnglishStrings()` — the catalogue is loaded before each test. */
class EnglishStrings : ExternalResource() {
    override fun before() = TestStrings.install()
}
