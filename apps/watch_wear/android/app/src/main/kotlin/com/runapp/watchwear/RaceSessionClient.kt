package com.runapp.watchwear

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
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
    ///
    /// [startGate] / [finishGate] are the course's timing lines and
    /// [finishLineSelfCross] says the route crosses its own finish line before
    /// its end, so the line cannot tell a lap from the finish and the race
    /// finishes by hand only (#1307). Read off the race's frozen copy
    /// (`race_session_courses`, decisions § 2391) when it has one, so a course
    /// edited mid-race moves only the next race. Serializable so the course is
    /// cached on the watch and a race times by its lines with no signal.
    /// [lapCount] is the lap count the race froze (`finish_lap_count`,
    /// decisions § 2472); the live row has none.
    @Serializable
    data class RaceCourse(
        val id: String,
        val name: String?,
        val distanceM: Double?,
        val finishLat: Double?,
        val finishLng: Double?,
        val startLat: Double? = null,
        val startLng: Double? = null,
        val startGate: Gate? = null,
        val finishGate: Gate? = null,
        val finishLineSelfCross: Boolean = false,
        val lapCount: Int? = null,
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
    /// Hops rather than an embedded select, so nothing here depends on a
    /// foreign-key name PostgREST would have to resolve. The route itself
    /// is never read: a non-owner is served it privacy-clipped (moving the
    /// finish) and a private route not at all, so the finish comes off the
    /// course row and a course without one finishes by hand.
    ///
    /// The lines, finish point, distance and self-cross flag come off the
    /// race's frozen copy when it has one; a race with none (created before
    /// it existed, or not armed yet) or a failed read of it keeps the live
    /// row's, as the phone's `_loadCourse` does. The start point the
    /// late-start check reads is always the live row's.
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
        val live = parseCourse(
            get(
                "$baseUrl/rest/v1/event_courses?id=eq.${enc(courseId)}" +
                    "&select=id,name,distance_m,finish_lat,finish_lng,start_lat,start_lng,$GATE_COLUMNS",
                accessToken,
            ),
        ) ?: return null
        // A failed read of the frozen copy is answered by the live row, which
        // is what every race created before the copy existed times by.
        val frozen = runCatching {
            get(
                "$baseUrl/rest/v1/race_session_courses?event_id=eq.${enc(eventId)}" +
                    "&instance_start=eq.${enc(instanceStart)}" +
                    "&course_id=eq.${enc(courseId)}" +
                    "&select=course_id,finish_lat,finish_lng,distance_m,finish_lap_count,$GATE_COLUMNS",
                accessToken,
            )
        }.getOrNull()?.let(::parseFrozenCourse)
        return withFrozen(live, frozen)
    }

    /// Delete the runner's own automatic result for one race: "Not finished?
    /// Resume" (#1307 m11). Only an `auto` row goes, so a host's edit or a
    /// result the runner typed since is never taken with it.
    suspend fun deleteOwnAutoResult(
        accessToken: String,
        userId: String,
        eventId: String,
        instanceStart: String,
    ) {
        val req = Request.Builder()
            .url(
                "$baseUrl/rest/v1/event_results?event_id=eq.${enc(eventId)}" +
                    "&instance_start=eq.${enc(instanceStart)}" +
                    "&user_id=eq.${enc(userId)}" +
                    "&finish_method=eq.auto",
            )
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $accessToken")
            .header("Prefer", "return=minimal")
            .delete()
            .build()
        execute(req)
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
        sinceStartLineS: Int? = null,
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
            if (sinceStartLineS != null) put("since_start_line_s", sinceStartLineS)
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

    /// One round trip to `server_now()`, answered with the server's clock: the
    /// debug line-calibration tool measures its offset from ten of these, as
    /// the phone's does. Signed out it goes as the anon role, which may call
    /// it. Null when the answer carried no readable instant.
    suspend fun sampleServerNow(accessToken: String?): ClockSample? {
        val req = Request.Builder()
            .url("$baseUrl/rest/v1/rpc/server_now")
            .header("apikey", anonKey)
            .header("Authorization", "Bearer ${accessToken ?: anonKey}")
            .get()
            .build()
        return withContext(Dispatchers.IO) {
            val sentAt = System.currentTimeMillis()
            http.newCall(req).execute().use { resp ->
                val receivedAt = System.currentTimeMillis()
                val text = resp.body.string()
                if (!resp.isSuccessful) {
                    throw RuntimeException("HTTP ${resp.code}: $text")
                }
                parseServerNowMs(text)?.let { ClockSample(sentAt, receivedAt, it) }
            }
        }
    }

    /// Files through `file_event_result`, not an upsert on `event_results`:
    /// the upsert reads back from EXCLUDED every column it writes, which
    /// needs SELECT on columns being withdrawn from signed-in readers
    /// (decisions § 2474). The function keeps the upsert's shape, so an
    /// omitted key still keeps its stored value.
    suspend fun submitResult(accessToken: String, result: PendingRaceResult) {
        val body = buildJsonObject { put("p_result", resultBody(result)) }
        val req = Request.Builder()
            .url("$baseUrl/rest/v1/rpc/file_event_result")
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $accessToken")
            .header("Content-Type", "application/json")
            .post(body.toString().toRequestBody(jsonMedia))
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

        /// The instant `server_now()` answers with: a JSON string.
        @JvmStatic
        internal fun parseServerNowMs(body: String): Long? =
            runCatching { parser.parseToJsonElement(body).jsonPrimitive.contentOrNull }
                .getOrNull()
                ?.let(::parseServerInstantMs)

        @JvmStatic
        internal fun parseCourseId(body: String): String? =
            firstRow(body)?.get("course_id")?.jsonPrimitive?.contentOrNull

        /// The line columns every course read selects, live row and frozen
        /// copy alike (the phone's `kCourseGateColumns`).
        internal const val GATE_COLUMNS =
            "start_gate_lat,start_gate_lng,start_gate_bearing_deg,start_gate_half_width_m," +
                "finish_gate_lat,finish_gate_lng,finish_gate_bearing_deg,finish_gate_half_width_m," +
                "finish_line_self_cross"

        /// One timing line off a course row, [prefix] `start_gate` or
        /// `finish_gate`: all four columns finite, or no line.
        @JvmStatic
        internal fun parseGate(row: JsonObject, prefix: String): Gate? {
            fun n(k: String) = row["${prefix}_$k"]?.jsonPrimitive?.doubleOrNull?.takeIf { it.isFinite() }
            val lat = n("lat") ?: return null
            val lng = n("lng") ?: return null
            val bearing = n("bearing_deg") ?: return null
            val half = n("half_width_m") ?: return null
            return Gate(lat, lng, bearing, half)
        }

        private fun selfCross(row: JsonObject): Boolean =
            row["finish_line_self_cross"]?.jsonPrimitive?.booleanOrNull == true

        /// The frozen fields of one `race_session_courses` row.
        data class FrozenCourse(
            val distanceM: Double?,
            val finishLat: Double?,
            val finishLng: Double?,
            val startGate: Gate?,
            val finishGate: Gate?,
            val finishLineSelfCross: Boolean,
            val lapCount: Int? = null,
        )

        @JvmStatic
        internal fun parseFrozenCourse(body: String): FrozenCourse? {
            val row = runCatching { firstRow(body) }.getOrNull() ?: return null
            row["course_id"]?.jsonPrimitive?.contentOrNull ?: return null
            val lat = row["finish_lat"]?.jsonPrimitive?.doubleOrNull
            val lng = row["finish_lng"]?.jsonPrimitive?.doubleOrNull
            val hasFinish = lat != null && lng != null
            return FrozenCourse(
                distanceM = row["distance_m"]?.jsonPrimitive?.doubleOrNull,
                finishLat = lat.takeIf { hasFinish },
                finishLng = lng.takeIf { hasFinish },
                startGate = parseGate(row, "start_gate"),
                finishGate = parseGate(row, "finish_gate"),
                finishLineSelfCross = selfCross(row),
                lapCount = row["finish_lap_count"]?.jsonPrimitive?.intOrNull?.takeIf { it >= 2 },
            )
        }

        /// The live course with its race's frozen copy laid over it.
        @JvmStatic
        internal fun withFrozen(live: RaceCourse, frozen: FrozenCourse?): RaceCourse =
            if (frozen == null) {
                live
            } else {
                live.copy(
                    distanceM = frozen.distanceM,
                    finishLat = frozen.finishLat,
                    finishLng = frozen.finishLng,
                    startGate = frozen.startGate,
                    finishGate = frozen.finishGate,
                    finishLineSelfCross = frozen.finishLineSelfCross,
                    lapCount = frozen.lapCount,
                )
            }

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
                startGate = parseGate(row, "start_gate"),
                finishGate = parseGate(row, "finish_gate"),
                finishLineSelfCross = selfCross(row),
            )
        }

        /// The result `file_event_result` files. The race-mode columns are written
        /// only when known, so a result with no course or no gun says nothing
        /// about them rather than writing nulls over a host's correction.
        ///
        /// The four crossing columns are the exception and always go, null
        /// included (#1307, decisions § 2450): an upsert keeps an omitted
        /// column, and the server derives a gun-mode result's times from a
        /// `finish_at` left by an earlier write, so a Wear result over a
        /// phone's row for the same race would otherwise be re-timed by the
        /// phone's crossings. `clock_offset_ms` belongs to the crossings it
        /// converted: written beside them, never cleared by a write that has
        /// none. [PendingRaceResult.runId] is absent on a finish filed at the
        /// line, before the run row exists; Stop files it again with the run.
        @JvmStatic
        internal fun resultBody(r: PendingRaceResult): JsonObject = buildJsonObject {
            put("event_id", r.eventId)
            put("instance_start", r.instanceStart)
            put("user_id", r.userId)
            r.runId?.let { put("run_id", it) }
            put("duration_s", r.durationS)
            put("distance_m", r.distanceM)
            put("finisher_status", r.finisherStatus)
            r.finishMethod?.let { put("finish_method", it) }
            r.courseId?.let { put("course_id", it) }
            r.gunTimeS?.let { put("gun_time_s", it) }
            r.chipTimeS?.let { put("chip_time_s", it) }
            put("start_at", r.startAt)
            put("finish_at", r.finishAt)
            put("start_detection", r.startDetection)
            put("finish_detection", r.finishDetection)
            if (r.startAt != null || r.finishAt != null || r.clockOffsetMs != null) {
                put("clock_offset_ms", r.clockOffsetMs)
            }
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
