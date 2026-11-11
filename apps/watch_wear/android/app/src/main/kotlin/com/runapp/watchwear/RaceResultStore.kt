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
///
/// [runId] is null for a finish filed at the line, before Stop saves the run
/// row it would point at (#1307). The crossing fields (`start_at` /
/// `finish_at` on the server clock as ISO-8601, how each was detected, and
/// the clock offset that converted them) ride the queue so a replay files
/// exactly what the line saw.
@Serializable
data class PendingRaceResult(
    val userId: String,
    val eventId: String,
    val instanceStart: String,
    val runId: String?,
    val durationS: Int,
    val distanceM: Double,
    val finisherStatus: String,
    val finishMethod: String? = null,
    val courseId: String? = null,
    val gunTimeS: Int? = null,
    val chipTimeS: Int? = null,
    val startAt: String? = null,
    val finishAt: String? = null,
    val startDetection: String? = null,
    val finishDetection: String? = null,
    val clockOffsetMs: Long? = null,
)

/// An automatic finish the runner withdrew ("Not finished? Resume") whose
/// delete has not reached the server. It is deleted before any later result
/// for the same race is sent, so a hand finish never lands beside, or under
/// the lock rule of, the finish the runner took back.
@Serializable
data class PendingRaceVoid(
    val userId: String,
    val eventId: String,
    val instanceStart: String,
)

/// The frozen course of the race this account last found, kept so a race
/// times by its lines with no signal (#1307 offline): one entry, keyed to
/// its account and race.
@Serializable
data class CachedRaceCourse(
    val userId: String,
    val eventId: String,
    val instanceStart: String,
    val course: RaceSessionClient.RaceCourse,
)

/// The scheduled or self-timed race this account last found, kept beside its
/// course so a watch restarted with no signal still knows which race to time
/// and when GO is (#1307 offline). One entry, keyed to its account; the race
/// key (account, event, instance) is also the course cache's key, and
/// [courseId] is the course it was found with. Mirrors the phone's
/// `race_active_cache`.
@Serializable
data class CachedActiveRace(
    val userId: String,
    val eventId: String,
    val instanceStart: String,
    val status: String,
    val startMode: String,
    val startedAtMs: Long? = null,
    val eventTitle: String? = null,
    val startInstantMs: Long? = null,
    val windowClosesAtMs: Long? = null,
    val courseId: String? = null,
)

/// What the watch keeps of the race a poll found: nothing for no race, and
/// nothing for a Host GO race, whose GO only the host knows — the phone keeps
/// none either.
internal fun activeRaceCacheEntry(userId: String, race: ActiveRaceState?): CachedActiveRace? {
    val r = race?.takeIf { it.startMode != "host_go" } ?: return null
    return CachedActiveRace(
        userId = userId,
        eventId = r.eventId,
        instanceStart = r.instanceStart,
        status = r.status,
        startMode = r.startMode,
        startedAtMs = r.startedAtMs,
        eventTitle = r.eventTitle,
        startInstantMs = r.startInstantMs,
        windowClosesAtMs = r.windowClosesAtMs,
        courseId = r.course?.id,
    )
}

/// The cached race as the watch's active race at [nowMs], or null: another
/// account's entry, a Host GO race, and a race finished, cancelled or whose
/// window has closed by now are not restored. The attempt toggle is not kept:
/// a self-timed attempt is armed again by hand, as on the phone.
internal fun restorableActiveRace(
    entry: CachedActiveRace?,
    userId: String,
    nowMs: Long,
    course: RaceSessionClient.RaceCourse? = null,
): ActiveRaceState? {
    val e = entry ?: return null
    if (e.userId != userId || e.startMode == "host_go") return null
    val status = raceEffectiveStatus(e.status, e.startMode, e.startInstantMs, e.windowClosesAtMs, nowMs)
    if (status != "armed" && status != "running") return null
    return ActiveRaceState(
        eventId = e.eventId,
        instanceStart = e.instanceStart,
        status = e.status,
        startedAtMs = e.startedAtMs,
        eventTitle = e.eventTitle,
        course = course?.takeIf { e.courseId == null || it.id == e.courseId },
        startMode = e.startMode,
        startInstantMs = e.startInstantMs,
        windowClosesAtMs = e.windowClosesAtMs,
    )
}

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

/// The queue minus every entry for [userId]'s result in one race: an undo
/// takes back a finish that never left the watch.
internal fun dequeueRaceResults(
    queue: List<PendingRaceResult>,
    userId: String,
    eventId: String,
    instanceStart: String,
): List<PendingRaceResult> =
    queue.filterNot { it.userId == userId && it.eventId == eventId && it.instanceStart == instanceStart }

private val Context.raceResultDataStore by preferencesDataStore(name = "watch_wear_race_results")
private val KEY_PENDING: Preferences.Key<String> = stringPreferencesKey("pending_race_results_v1")
private val KEY_VOIDS: Preferences.Key<String> = stringPreferencesKey("pending_race_voids_v1")
private val KEY_COURSE: Preferences.Key<String> = stringPreferencesKey("race_course_cache_v1")
private val KEY_ACTIVE: Preferences.Key<String> = stringPreferencesKey("race_active_cache_v1")
private val pendingJson = Json { ignoreUnknownKeys = true }
private val pendingSerializer = ListSerializer(PendingRaceResult.serializer())
private val voidSerializer = ListSerializer(PendingRaceVoid.serializer())

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

    /// Drop every queued result for [userId] in one race.
    suspend fun dequeue(userId: String, eventId: String, instanceStart: String) {
        dataStore.edit { prefs ->
            val list = decodeOrEmpty(prefs[KEY_PENDING])
            prefs[KEY_PENDING] = pendingJson.encodeToString(
                pendingSerializer,
                dequeueRaceResults(list, userId, eventId, instanceStart),
            )
        }
    }

    suspend fun voids(): List<PendingRaceVoid> = decodeVoids(dataStore.data.first()[KEY_VOIDS])

    suspend fun addVoid(v: PendingRaceVoid) {
        dataStore.edit { prefs ->
            val list = decodeVoids(prefs[KEY_VOIDS])
            prefs[KEY_VOIDS] = pendingJson.encodeToString(voidSerializer, list.filterNot { it == v } + v)
        }
    }

    suspend fun removeVoid(v: PendingRaceVoid) {
        dataStore.edit { prefs ->
            val list = decodeVoids(prefs[KEY_VOIDS])
            prefs[KEY_VOIDS] = pendingJson.encodeToString(voidSerializer, list - v)
        }
    }

    /// Keep [course] as the one cached race course.
    suspend fun cacheCourse(entry: CachedRaceCourse) {
        dataStore.edit { prefs ->
            prefs[KEY_COURSE] = pendingJson.encodeToString(CachedRaceCourse.serializer(), entry)
        }
    }

    /// The cached course for this account's race, or null.
    suspend fun cachedCourse(
        userId: String,
        eventId: String,
        instanceStart: String,
    ): RaceSessionClient.RaceCourse? {
        val raw = dataStore.data.first()[KEY_COURSE] ?: return null
        val entry = runCatching { pendingJson.decodeFromString(CachedRaceCourse.serializer(), raw) }
            .getOrElse { e ->
                Log.w("RaceResultStore", "cached race course unreadable, ignoring", e)
                null
            } ?: return null
        val mine = entry.userId == userId && entry.eventId == eventId && entry.instanceStart == instanceStart
        return entry.course.takeIf { mine }
    }

    /// Keep [entry] as the one cached race; null forgets it.
    suspend fun cacheActiveRace(entry: CachedActiveRace?) {
        dataStore.edit { prefs ->
            if (entry == null) {
                prefs.remove(KEY_ACTIVE)
            } else {
                prefs[KEY_ACTIVE] = pendingJson.encodeToString(CachedActiveRace.serializer(), entry)
            }
        }
    }

    /// The cached race, whoever's it is, or null.
    suspend fun cachedActiveRace(): CachedActiveRace? {
        val raw = dataStore.data.first()[KEY_ACTIVE] ?: return null
        return runCatching { pendingJson.decodeFromString(CachedActiveRace.serializer(), raw) }
            .getOrElse { e ->
                Log.w("RaceResultStore", "cached race unreadable, ignoring", e)
                null
            }
    }

    /// After a restart: this account's cached race at [nowMs] with its cached
    /// course, so detection and binding resume with no signal. Null when there
    /// is none to restore ([restorableActiveRace]).
    suspend fun restoreActiveRace(userId: String, nowMs: Long): ActiveRaceState? {
        val entry = cachedActiveRace() ?: return null
        if (restorableActiveRace(entry, userId, nowMs) == null) return null
        val course = cachedCourse(userId, entry.eventId, entry.instanceStart)
        return restorableActiveRace(entry, userId, nowMs, course)
    }

    /// Sign-out: every queued result, withdrawn finish, cached course and
    /// cached race, for every account.
    suspend fun clear() {
        dataStore.edit { prefs ->
            prefs.remove(KEY_PENDING)
            prefs.remove(KEY_VOIDS)
            prefs.remove(KEY_COURSE)
            prefs.remove(KEY_ACTIVE)
        }
    }
}

private fun decodeVoids(raw: String?): List<PendingRaceVoid> {
    if (raw == null) return emptyList()
    return runCatching { pendingJson.decodeFromString(voidSerializer, raw) }
        .getOrElse { e ->
            Log.w("RaceResultStore", "pending race voids unreadable, dropping", e)
            emptyList()
        }
}
