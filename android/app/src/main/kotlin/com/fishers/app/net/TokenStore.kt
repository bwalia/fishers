package com.fishers.app.net

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Where the session tokens live between launches — `KeychainStore.swift`'s
 * opposite number.
 *
 * An interface, so the session logic below can be tested on the JVM without an
 * emulator, and so the backing store can change without touching anything that
 * uses it.
 */
interface TokenStore {
    fun get(key: String): String?
    fun set(key: String, value: String?)

    companion object {
        const val ACCESS = "access_token"
        const val REFRESH = "refresh_token"
    }
}

/**
 * Backed by the Android Keystore, which is what iOS uses the Keychain for: the
 * app sandbox already keeps other apps out, and this is what keeps the tokens
 * out of a physical extraction off a rooted device.
 *
 * `security-crypto` is at alpha and Google have signalled they will replace it.
 * That is survivable here precisely because of the interface — when the
 * replacement lands, one class changes and nothing else notices.
 */
class KeystoreTokenStore(context: Context) : TokenStore {
    private val prefs = EncryptedSharedPreferences.create(
        context,
        "fishers.session",
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    override fun get(key: String): String? = prefs.getString(key, null)

    override fun set(key: String, value: String?) {
        prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    }
}
