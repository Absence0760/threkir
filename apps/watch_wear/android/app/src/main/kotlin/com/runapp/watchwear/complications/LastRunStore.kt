package com.runapp.watchwear.complications

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.Json

private val Context.lastRunDataStore by preferencesDataStore(name = "watch_wear_last_run")
private val KEY_LAST_RUN: Preferences.Key<String> = stringPreferencesKey("last_run_v1")
private val lastRunJson = Json { ignoreUnknownKeys = true }

internal fun encodeLastRun(run: LastRun): String =
    lastRunJson.encodeToString(LastRun.serializer(), run)

/// An unreadable entry reads as no last run: the complication then shows its
/// start prompt, which is what it would show on a fresh install anyway.
internal fun decodeLastRun(raw: String?): LastRun? {
    if (raw == null) return null
    return runCatching { lastRunJson.decodeFromString(LastRun.serializer(), raw) }.getOrNull()
}

/// The last run this watch recorded, kept for the watch-face complication's
/// idle state. Written once per run, when `RunViewModel.handleFinishedRun`
/// has banked it in the upload queue; cleared by that run's discard and by
/// sign-out, because a watch face is on show to anyone and the next account
/// must not inherit the previous one's distance.
///
/// The DataStore is injected so the behaviour is pinned on the host JVM
/// against a real file store; the app always takes the Context one.
class LastRunStore internal constructor(private val dataStore: DataStore<Preferences>) {

    constructor(context: Context) : this(context.applicationContext.lastRunDataStore)

    internal suspend fun current(): LastRun? = decodeLastRun(dataStore.data.first()[KEY_LAST_RUN])

    internal suspend fun save(run: LastRun) {
        dataStore.edit { prefs -> prefs[KEY_LAST_RUN] = encodeLastRun(run) }
    }

    /// Drop the entry only when it is [runId]'s, so discarding an older
    /// run's summary cannot erase a newer run's.
    suspend fun clearIfFor(runId: String) {
        dataStore.edit { prefs ->
            if (decodeLastRun(prefs[KEY_LAST_RUN])?.runId == runId) prefs.remove(KEY_LAST_RUN)
        }
    }

    suspend fun clear() {
        dataStore.edit { prefs -> prefs.remove(KEY_LAST_RUN) }
    }
}
