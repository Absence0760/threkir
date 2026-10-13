package com.runapp.watchwear

import android.content.Context
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/// One `event_results` row the watch owes the server. Persisted, because the
/// moment it is produced — the finish line — is the moment a watch is least
/// likely to have a connection, and the official time cannot be rebuilt from
/// the run afterwards (the gun offset and the closest-approach fix are gone).
@Serializable
data class PendingRaceResult(
    val userId: String,
    val eventId: String,
    val instanceStart: String,
    val runId: String,
    val durationS: Int,
    val distanceM: Double,
    val finisherStatus: String,
    val finishMethod: String? = null,
    val courseId: String? = null,
    val gunTimeS: Int? = null,
    val chipTimeS: Int? = null,
)

/// Whether a failed upsert is worth replaying. The body is the problem on a
/// 400 / 403 / 404 / 422 and a replay sends the same body; everything else —
/// offline, 5xx, a 409 on a run that has not uploaded yet, an expired token —
/// can come right on its own.
internal fun isRetryableRaceResultFailure(e: Throwable): Boolean {
    val code = Regex("""^HTTP (\d{3})""").find(e.message.orEmpty())
        ?.groupValues?.get(1)?.toIntOrNull() ?: return true
    return code !in setOf(400, 403, 404, 422)
}

/// Replace any entry for the same race and user: the leaderboard holds one
/// row per runner, and the upsert would collapse them anyway.
internal fun enqueueRaceResult(
    queue: List<PendingRaceResult>,
    result: PendingRaceResult,
): List<PendingRaceResult> =
    queue.filterNot {
        it.eventId == result.eventId &&
            it.instanceStart == result.instanceStart &&
            it.userId == result.userId
    } + result

private val Context.raceResultDataStore by preferencesDataStore(name = "watch_wear_race_results")
private val KEY_PENDING: Preferences.Key<String> = stringPreferencesKey("pending_race_results_v1")
private val pendingJson = Json { ignoreUnknownKeys = true }
private val pendingSerializer = ListSerializer(PendingRaceResult.serializer())

/// An unreadable entry list is dropped rather than allowed to block every
/// later finish from being written: the one result it held is lost either way.
private fun decodeOrEmpty(raw: String?): List<PendingRaceResult> {
    if (raw == null) return emptyList()
    return runCatching { pendingJson.decodeFromString(pendingSerializer, raw) }
        .getOrElse { e ->
            Log.w("RaceResultStore", "pending race results unreadable, dropping", e)
            emptyList()
        }
}

/// The queue minus [result]. Every other entry, including another account's,
/// is left where it was.
internal fun removeRaceResult(
    queue: List<PendingRaceResult>,
    result: PendingRaceResult,
): List<PendingRaceResult> = queue - result

/// The DataStore is injected so the queue's behaviour is pinned on the host
/// JVM against a real file store; the app always takes the Context one.
class RaceResultStore internal constructor(private val dataStore: DataStore<Preferences>) {

    constructor(context: Context) : this(context.raceResultDataStore)

    suspend fun current(): List<PendingRaceResult> =
        decodeOrEmpty(dataStore.data.first()[KEY_PENDING])

    suspend fun add(result: PendingRaceResult) {
        dataStore.edit { prefs ->
            val list = decodeOrEmpty(prefs[KEY_PENDING])
            prefs[KEY_PENDING] = pendingJson.encodeToString(
                pendingSerializer,
                enqueueRaceResult(list, result),
            )
        }
    }

    suspend fun remove(result: PendingRaceResult) {
        dataStore.edit { prefs ->
            val list = decodeOrEmpty(prefs[KEY_PENDING])
            prefs[KEY_PENDING] = pendingJson.encodeToString(
                pendingSerializer,
                removeRaceResult(list, result),
            )
        }
    }

    suspend fun clear() {
        dataStore.edit { prefs -> prefs.remove(KEY_PENDING) }
    }
}
