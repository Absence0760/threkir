package com.runapp.watchwear

import android.app.Application
import android.util.Log
import io.sentry.android.core.SentryAndroid

// The one place Sentry starts. The SDK's own SentryInitProvider is switched
// off in the manifest (`io.sentry.auto-init=false`): it runs before any app
// code, and with no DSN it throws "DSN is required" and kills the process.
// Application.onCreate still runs ahead of every component, so a crash in
// RunRecordingService or the tile service is caught even when MainActivity
// never opens.
class WatchWearApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        val dsn = BuildConfig.SENTRY_DSN
        if (dsn.isBlank()) return
        try {
            SentryAndroid.init(this) { options ->
                options.dsn = dsn
                options.release = BuildConfig.APP_RELEASE
                options.environment = if (BuildConfig.APP_RELEASE == "dev") "development" else "production"
                options.tracesSampleRate = 0.1
            }
        } catch (e: Exception) {
            Log.w("WatchWearApplication", "Sentry init failed; crash reporting is off", e)
        }
    }
}
