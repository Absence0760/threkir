package com.runapp.watchwear

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.net.URLEncoder
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/// Epoch millis of a PostgREST `timestamptz`, which arrives as
/// `2026-05-22T18:00:00+00:00` (an offset, not `Z`) with optional fractional
/// seconds. Null when unparseable: a race with no readable gun has no gun time.
internal fun parseServerInstantMs(iso: String): Long? =
    runCatching { java.time.OffsetDateTime.parse(iso).toInstant().toEpochMilli() }.getOrNull()

/// Thin REST client for the `race_sessions`, `race_pings`, and
/// `event_results` endpoints. Shares the wire format with
/// `SupabaseClient.saveRun` — this file owns nothing else about that
/// service and keeps `SupabaseClient.kt` focused on the run-upload path.
class RaceSessionClient(
    private val baseUrl: String,
    private val anonKey: String,
    private val http: OkHttpClient = OkHttpClient(),
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val jsonMedia = "application/json".toMediaType()

    data class ActiveRace(
        val eventId: String,
        val instanceStart: String,
        val status: String,
        val startedAtIso: String?,
        val eventTitle: String?,
        /// `host_go` | `scheduled` | `self_timed` (#1306).
        val startMode: String = "host_go",
        /// When the clock starts: the scheduled GO or the window's opening.
        val startInstantIso: String? = null,
        val windowClosesAtIso: String? = null,
    )

    /// The runner's chosen course for a race: `event_attendees.course_id` →
    /// the `event_courses` row, whose finish point the server copied from
    /// the route's last waypoint. Null [finishLat]/[finishLng] (a course with
    /// no route) or a null [distanceM] leave the race to a manual finish.
    /// [startLat]/[startLng] are the route's first point, copied and
    /// privacy-clipped the same way (migration `20270728000001`); read only by
    /// the late-start check, and null when the row has none or the owner's
    /// zone clipped it away, which leaves that check to the time arm.
    data class RaceCourse(
        val id: String,
        val name: String?,
        val distanceM: Double?,
        val finishLat: Double?,
        val finishLng: Double?,
        val startLat: Double? = null,
        val startLng: Double? = null,
    ) {
        val hasStart: Boolean get() = startLat != null && startLng != null
    }

    /// The most relevant armed or live race for the signed-in user, from
    /// `my_race_sessions()` (#1306): one round trip that finds races by
    /// window rather than by the occurrence's start (a self-timed window can
    /// open days after it), creates the sessions of due scheduled and
    /// self-timed occurrences, and judges status on the server clock. Null
    /// when none match; the watch then hides the race banner.
    suspend fun fetchActive(accessToken: String, userId: String): ActiveRace? {
        val body = post("$baseUrl/rest/v1/rpc/my_race_sessions", "{}", accessToken)
        return pickActiveRace(parseMyRaceSessions(body))
    }

    /// The course the runner picked at RSVP. Null when they picked none.
    /// Two hops rather than an embedded select, so nothing here depends on
    /// a foreign-key name PostgREST would have to resolve. The route itself
    /// is never read: a non-owner is served it privacy-clipped (moving the
    /// finish) and a private route not at all, so the finish comes off the
    /// course row and a course without one finishes by hand.
    suspend fun fetchCourse(
        accessToken: String,
        userId: String,
        eventId: String,
        instanceStart: String,
    ): RaceCourse? {
        val courseId = parseCourseId(
            get(
                "$baseUrl/rest/v1/event_attendees?user_id=eq.${enc(userId)}" +
                    "&event_id=eq.${enc(eventId)}" +
                    "&instance_start=eq.${enc(instanceStart)}" +
                    "&select=course_id",
                accessToken,
            ),
        ) ?: return null
        return parseCourse(
            get(
                "$baseUrl/rest/v1/event_courses?id=eq.${enc(courseId)}" +
                    "&select=id,name,distance_m,finish_lat,finish_lng,start_lat,start_lng",
                accessToken,
            ),
        )
    }

    /// Status of one race session regardless of phase, so a host's End can be
    /// told apart from "no race found". Null when the row is not readable.
    suspend fun fetchSessionStatus(
        accessToken: String,
        eventId: String,
        instanceStart: String,
    ): String? {
        val res = get(
            "$baseUrl/rest/v1/race_sessions?event_id=eq.${enc(eventId)}" +
                "&instance_start=eq.${enc(instanceStart)}&select=status",
            accessToken,
        )
        val row = (json.parseToJsonElement(res) as? JsonArray)?.firstOrNull() as? JsonObject
        return row?.get("status")?.jsonPrimitive?.contentOrNull
    }

    /// One round trip answered with the server's own clock: the ping's
    /// `at`, read back on the insert. Feeds [ServerClockOffset].
    data class ClockSample(val sentAtMs: Long, val receivedAtMs: Long, val serverAtMs: Long)

    /// Ping post, read back for its server-stamped `at` so the watch's clock
    /// offset comes from the same source the phone's does. Null when the
    /// response carried no readable `at`. Caller debounces to every 10s or so.
    suspend fun pushPing(
        accessToken: String,
        userId: String,
        eventId: String,
        instanceStart: String,
        lat: Double,
        lng: Double,
        distanceM: Double,
        elapsedS: Int,
        bpm: Int?,
    ): ClockSample? {
        val body = buildJsonObject {
            put("event_id", eventId)
            put("instance_start", instanceStart)
            put("user_id", userId)
            put("lat", lat)
            put("lng", lng)
            put("distance_m", distanceM)
            put("elapsed_s", elapsedS)
            if (bpm != null) put("bpm", bpm)
        }
        val req = Request.Builder()
            .url("$baseUrl/rest/v1/race_pings?select=at")
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $accessToken")
            .header("Content-Type", "application/json")
            .header("Prefer", "return=representation")
            .post(body.toString().toRequestBody(jsonMedia))
            .build()
        return withContext(Dispatchers.IO) {
            val sentAt = System.currentTimeMillis()
            http.newCall(req).execute().use { resp ->
                val receivedAt = System.currentTimeMillis()
                val text = resp.body.string()
                if (!resp.isSuccessful) {
                    throw RuntimeException("HTTP ${resp.code}: $text")
                }
                parsePingAtMs(text)?.let { ClockSample(sentAt, receivedAt, it) }
            }
        }
    }

    suspend fun submitResult(accessToken: String, result: PendingRaceResult) {
        val req = Request.Builder()
            .url("$baseUrl/rest/v1/event_results?on_conflict=event_id,instance_start,user_id")
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $accessToken")
            .header("Content-Type", "application/json")
            .header("Prefer", "resolution=merge-duplicates,return=minimal")
            .post(resultBody(result).toString().toRequestBody(jsonMedia))
            .build()
        execute(req)
    }

    // ----- internal -----

    private suspend fun get(url: String, token: String): String {
        val req = Request.Builder()
            .url(url)
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $token")
            .get()
            .build()
        return execute(req)
    }

    private suspend fun post(url: String, body: String, token: String): String {
        val req = Request.Builder()
            .url(url)
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .post(body.toRequestBody(jsonMedia))
            .build()
        return execute(req)
    }

    private suspend fun execute(req: Request): String = withContext(Dispatchers.IO) {
        http.newCall(req).execute().use { resp ->
            val body = resp.body.string()
            if (!resp.isSuccessful) {
                throw RuntimeException("HTTP ${resp.code}: $body")
            }
            body
        }
    }

    private fun enc(s: String): String = encodeQueryValue(s)

    companion object {
        private val parser = Json { ignoreUnknownKeys = true }

        private fun firstRow(body: String): JsonObject? =
            (parser.parseToJsonElement(body) as? JsonArray)?.firstOrNull() as? JsonObject

        /// The `at` of the inserted `race_pings` row, echoed back by
        /// `return=representation`.
        @JvmStatic
        internal fun parsePingAtMs(body: String): Long? =
            firstRow(body)?.get("at")?.jsonPrimitive?.contentOrNull?.let(::parseServerInstantMs)

        @JvmStatic
        internal fun parseCourseId(body: String): String? =
            firstRow(body)?.get("course_id")?.jsonPrimitive?.contentOrNull

        /// One `event_courses` row. The finish and start points are each
        /// both-or-neither in the schema; a half pair read here is treated as
        /// no point.
        @JvmStatic
        internal fun parseCourse(body: String): RaceCourse? {
            val row = firstRow(body) ?: return null
            val id = row["id"]?.jsonPrimitive?.contentOrNull ?: return null
            val lat = row["finish_lat"]?.jsonPrimitive?.doubleOrNull
            val lng = row["finish_lng"]?.jsonPrimitive?.doubleOrNull
            val hasFinish = lat != null && lng != null
            val startLat = row["start_lat"]?.jsonPrimitive?.doubleOrNull
            val startLng = row["start_lng"]?.jsonPrimitive?.doubleOrNull
            val hasStart = startLat != null && startLng != null
            return RaceCourse(
                id = id,
                name = row["name"]?.jsonPrimitive?.contentOrNull,
                distanceM = row["distance_m"]?.jsonPrimitive?.doubleOrNull,
                finishLat = lat.takeIf { hasFinish },
                finishLng = lng.takeIf { hasFinish },
                startLat = startLat.takeIf { hasStart },
                startLng = startLng.takeIf { hasStart },
            )
        }

        /// The `event_results` upsert body. The race-mode columns are written
        /// only when known, so a result with no course or no gun says nothing
        /// about them rather than writing nulls over a host's correction.
        @JvmStatic
        internal fun resultBody(r: PendingRaceResult): JsonObject = buildJsonObject {
            put("event_id", r.eventId)
            put("instance_start", r.instanceStart)
            put("user_id", r.userId)
            put("run_id", r.runId)
            put("duration_s", r.durationS)
            put("distance_m", r.distanceM)
            put("finisher_status", r.finisherStatus)
            r.finishMethod?.let { put("finish_method", it) }
            r.courseId?.let { put("course_id", it) }
            r.gunTimeS?.let { put("gun_time_s", it) }
            r.chipTimeS?.let { put("chip_time_s", it) }
        }

        /// The rows of `my_race_sessions()`, each with its status on the
        /// server clock. Malformed rows are skipped.
        @JvmStatic
        internal fun parseMyRaceSessions(body: String): List<ActiveRace> {
            val arr = runCatching { Json.parseToJsonElement(body) as? JsonArray }.getOrNull()
                ?: return emptyList()
            return arr.mapNotNull { el ->
                val o = el as? JsonObject ?: return@mapNotNull null
                fun str(k: String) = o[k]?.jsonPrimitive?.contentOrNull
                val eventId = str("event_id") ?: return@mapNotNull null
                val instance = str("instance_start") ?: return@mapNotNull null
                val status = str("effective_status") ?: str("status") ?: return@mapNotNull null
                val mode = str("start_mode") ?: "host_go"
                ActiveRace(
                    eventId = eventId,
                    instanceStart = instance,
                    status = status,
                    startedAtIso = str("started_at"),
                    eventTitle = str("event_title"),
                    startMode = mode,
                    startInstantIso = if (mode == "self_timed") str("window_opens_at") else str("scheduled_start_at"),
                    windowClosesAtIso = str("window_closes_at"),
                )
            }
        }

        /// A live race wins over an armed one; otherwise the first.
        @JvmStatic
        internal fun pickActiveRace(races: List<ActiveRace>): ActiveRace? =
            races.firstOrNull { it.status == "running" } ?: races.firstOrNull()

        /// URL-encode a value for interpolation into a PostgREST query
        /// string. Critically defensive for `instance_start` values
        /// that come BACK from PostgREST as timestamptz — Postgres
        /// serializes timestamptz as `2026-05-22T18:00:00+00:00`, and
        /// a raw `+` in a PostgREST query value gets decoded as a
        /// SPACE (PostgREST treats the query as
        /// application/x-www-form-urlencoded). Without this encoding a
        /// course or status read's `instance_start=eq.<value>` would fail
        /// to match the row the race came back with.
        ///
        /// `internal` so unit tests can exercise it without spinning
        /// up a real OkHttp stack — see `RaceSessionClientTest`.
        @JvmStatic
        internal fun encodeQueryValue(s: String): String =
            URLEncoder.encode(s, Charsets.UTF_8.name())
    }
}
