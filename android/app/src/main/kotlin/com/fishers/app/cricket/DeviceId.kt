package com.fishers.app.cricket

import android.content.Context
import java.util.UUID

/**
 * This install's id, for the scorer lock: the API lets one device score a
 * match at a time (`claim-scorer`, `events` both carry it). Stable across
 * launches, new on a reinstall — which is what "this phone" means here.
 */
object DeviceId {
    private const val PREFS = "fishers.device"
    private const val KEY = "device_id"

    fun get(context: Context): String {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return prefs.getString(KEY, null) ?: UUID.randomUUID().toString().also {
            prefs.edit().putString(KEY, it).apply()
        }
    }
}
