package com.fishers.app

import android.app.Application
import com.fishers.app.config.AppConfig
import com.fishers.app.net.KeystoreTokenStore
import com.fishers.app.net.Network
import com.fishers.app.net.Session

/**
 * What the app is made of, built once.
 *
 * No dependency-injection framework: there are three things here and they are
 * constructed in one place. A framework earns its keep when the graph is deep
 * enough to be hard to read, and this one is four lines.
 */
class FishersApp : Application() {
    lateinit var config: AppConfig
        private set
    lateinit var session: Session
        private set
    lateinit var network: Network
        private set

    override fun onCreate() {
        super.onCreate()
        config = AppConfig.from(
            context = this,
            debug = BuildConfig.DEBUG,
            buildTimeApiBase = BuildConfig.FISHERS_API_URL.takeIf { it.isNotBlank() },
        )
        session = Session(KeystoreTokenStore(this))
        network = Network(config, session)
    }
}
