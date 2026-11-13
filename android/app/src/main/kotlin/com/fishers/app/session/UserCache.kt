package com.fishers.app.session

import android.content.Context
import com.fishers.app.net.PublicUser
import kotlinx.serialization.json.Json

/**
 * The signed-in person as last seen, so the app opens at a ground with no
 * signal instead of asking somebody mid-match to sign in again.
 */
interface UserCache {
    fun load(): PublicUser?
    fun save(user: PublicUser)
    fun clear()

    object None : UserCache {
        override fun load(): PublicUser? = null
        override fun save(user: PublicUser) = Unit
        override fun clear() = Unit
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun prefs(context: Context): UserCache = object : UserCache {
            private val prefs = context.applicationContext
                .getSharedPreferences("fishers.session", Context.MODE_PRIVATE)

            override fun load(): PublicUser? = prefs.getString("me", null)
                ?.let { runCatching { json.decodeFromString(PublicUser.serializer(), it) }.getOrNull() }

            override fun save(user: PublicUser) {
                prefs.edit().putString("me", json.encodeToString(PublicUser.serializer(), user)).apply()
            }

            override fun clear() {
                prefs.edit().remove("me").apply()
            }
        }
    }
}
