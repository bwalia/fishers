// Generated from web/src/lib/i18n/ by tools/i18n. Do not edit.
//
// 3578 keys per language. The words are in assets/strings/; only the
// list of languages needs to be code, because it is what the picker iterates
// and what `Language.from` validates.

package com.fishers.app.i18n

/** A language the product speaks. */
enum class Language(val code: String, val native: String) {
    EN("en", "English"),
    PA("pa", "ਪੰਜਾਬੀ"),
    ;

    companion object {
        /** The language this build falls back to, per key. */
        val fallback = EN

        /**
         * A language from anything untrusted — a saved preference, a system
         * locale tag. "pa-Guru-IN" and "pa_IN" are both Punjabi as far as this
         * product cares, which is what the web's `localeFrom` does too.
         */
        fun from(tag: String?): Language {
            if (tag.isNullOrBlank()) return fallback
            val base = tag.trim().lowercase().split('-', '_').first()
            return entries.firstOrNull { it.code == base } ?: fallback
        }
    }
}
