package com.fishers.app

import android.app.Application
import com.fishers.app.config.AppConfig

class FishersApp : Application() {
    lateinit var config: AppConfig
        private set

    override fun onCreate() {
        super.onCreate()
        config = AppConfig.from(
            context = this,
            debug = BuildConfig.DEBUG,
            buildTimeApiBase = BuildConfig.FISHERS_API_URL.takeIf { it.isNotBlank() },
        )
    }
}
