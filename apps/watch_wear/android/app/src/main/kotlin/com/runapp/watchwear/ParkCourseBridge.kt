package com.runapp.watchwear

import android.content.Context
import android.net.Uri
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlin.math.abs

/// A park course the phone put on the watch to run: its route line for the
/// map and the "X to go" badge, and what [LiveCourseTimer] times it by.
data class ParkCourse(
    val id: String,
    val routeId: String?,
    val name: String,
    val laps: Int?,
    val timing: CourseTimingSpec,
    val waypoints: List<SavedRoute.Waypoint>,
) {
    /// The course as a picker row. Its id is the course's own, prefixed, so
    /// it can never collide with a saved route's in the picker or the LRU.
    fun asRoute(): SavedRoute = SavedRoute(
        id = ROUTE_ID_PREFIX + id,
        name = name,
        distanceM = timing.distanceM,
        waypoints = waypoints,
        courseId = id,
    )

    companion object {
        const val ROUTE_ID_PREFIX = "park_course:"
    }
}

/// One delivery at `/park_courses`.
data class ParkCoursesPush(val courses: List<ParkCourse>, val updatedAtMs: Long)

/// The receive side's caps: a course past any of them is refused whole.
/// Checkpoints as `park_courses.checkpoints` holds them (at most 50); a line's
/// half-width as the gate CHECKs hold it (5..100 m); the length up to the
/// 1000 km the watch workout reader also restates; and a route line the
/// Data Layer's ~100 KB item can carry for [PARK_COURSES_MAX] courses.
const val PARK_COURSES_PAYLOAD_VERSION = 1
const val PARK_COURSES_MAX = 20
const val PARK_COURSE_MAX_CHECKPOINTS = 50
const val PARK_COURSE_MAX_WAYPOINTS = 1000
const val PARK_COURSE_MAX_DISTANCE_M = 1_000_000.0
const val PARK_COURSE_MIN_HALF_WIDTH_M = 5.0
const val PARK_COURSE_MAX_HALF_WIDTH_M = 100.0

/// Listens at `/park_courses` for the park courses the paired phone puts on
/// the watch (decisions § 2595). The DataMap carries `payload_version` (int),
/// `courses_json` (a JSON array, see [parseParkCoursesJson] and
/// `fixtures/wear_park_courses_payload.json`) and `updated_at_ms`. An empty
/// array is the phone saying "none": it clears the watch's course rows.
///
/// The DataItem persists on the watch, so [current] serves a cold launch with
/// no phone in range. Only public catalogue geometry travels here: the route
/// line, the two timing lines, the checkpoints and the stored length.
class ParkCourseBridge(context: Context) {
    private val dataClient: DataClient = Wearable.getDataClient(context)

    val events: Flow<ParkCoursesPush> = callbackFlow {
        val listener = DataClient.OnDataChangedListener { evts ->
            for (event in evts) {
                if (event.dataItem.uri.path != PATH) continue
                if (event.type != DataEvent.TYPE_CHANGED) continue
                val push = fromDataMap(DataMapItem.fromDataItem(event.dataItem).dataMap) ?: continue
                trySend(push)
            }
        }
        dataClient.addListener(listener)
        awaitClose { dataClient.removeListener(listener) }
    }

    suspend fun current(): ParkCoursesPush? {
        val uri = Uri.Builder().scheme("wear").path(PATH).build()
        val buffer = dataClient.getDataItems(uri).await()
        return try {
            buffer.firstOrNull()?.let { fromDataMap(DataMapItem.fromDataItem(it).dataMap) }
        } finally {
            buffer.release()
        }
    }

    companion object {
        const val PATH = "/park_courses"
        const val KEY_VERSION = "payload_version"
        const val KEY_COURSES = "courses_json"
        const val KEY_UPDATED_AT = "updated_at_ms"

        private val json = Json { ignoreUnknownKeys = true }

        /// Null when the item is not one this reader understands: another
        /// payload version, or no readable course list. Dropped, never read
        /// as "no courses", so a newer phone cannot clear an older watch.
        private fun fromDataMap(dm: DataMap): ParkCoursesPush? = parseParkCoursesPush(
            version = if (dm.containsKey(KEY_VERSION)) dm.getInt(KEY_VERSION) else null,
            coursesJson = dm.getString(KEY_COURSES),
            updatedAtMs = dm.getLong(KEY_UPDATED_AT),
        )

        internal fun parseParkCoursesPush(version: Int?, coursesJson: String?, updatedAtMs: Long): ParkCoursesPush? {
            if (version != PARK_COURSES_PAYLOAD_VERSION) return null
            val courses = parseParkCoursesJson(json, coursesJson ?: return null) ?: return null
            return ParkCoursesPush(courses, updatedAtMs)
        }
    }
}

private fun JsonElement?.num(): Double? {
    val p = this as? JsonPrimitive ?: return null
    if (p.isString) return null
    return p.doubleOrNull?.takeIf { it.isFinite() }
}

private fun JsonElement?.str(): String? {
    val p = this as? JsonPrimitive ?: return null
    if (!p.isString) return null
    return p.content.trim().takeIf { it.isNotEmpty() }
}

private fun point(el: JsonElement?): GatePoint? {
    val o = el as? JsonObject ?: return null
    val lat = o["lat"].num() ?: return null
    val lng = o["lng"].num() ?: return null
    if (abs(lat) >= 90.0 || abs(lng) > 180.0) return null
    return GatePoint(lat, lng)
}

private fun gate(el: JsonElement?): Gate? {
    val o = el as? JsonObject ?: return null
    val p = point(o) ?: return null
    val bearing = o["bearing_deg"].num() ?: return null
    val halfWidth = o["half_width_m"].num() ?: return null
    if (halfWidth < PARK_COURSE_MIN_HALF_WIDTH_M || halfWidth > PARK_COURSE_MAX_HALF_WIDTH_M) return null
    return Gate(lat = p.lat, lng = p.lng, bearingDeg = bearing, halfWidthM = halfWidth)
}

/// One course of a push, or null when any field the timer or the map needs
/// is missing or out of range: refused whole, never timed by a guess.
internal fun parseParkCourse(el: JsonElement): ParkCourse? {
    val o = el as? JsonObject ?: return null
    val id = o["id"].str() ?: return null
    val name = o["name"].str() ?: return null
    val routeId = when (val r = o["route_id"]) {
        null, is JsonNull -> null
        else -> r.str() ?: return null
    }
    val distance = o["distance_m"].num() ?: return null
    if (distance <= 0.0 || distance > PARK_COURSE_MAX_DISTANCE_M) return null
    val laps = when (val l = o["laps"]) {
        null, is JsonNull -> null
        else -> (l as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull?.takeIf { it in 1..1000 } ?: return null
    }
    val start = gate(o["start_gate"]) ?: return null
    val end = gate(o["end_gate"]) ?: return null
    val cpArr = o["checkpoints"] as? JsonArray ?: return null
    if (cpArr.size > PARK_COURSE_MAX_CHECKPOINTS) return null
    val checkpoints = cpArr.map { point(it) ?: return null }
    val wpArr = o["waypoints"] as? JsonArray ?: return null
    if (wpArr.size < 2 || wpArr.size > PARK_COURSE_MAX_WAYPOINTS) return null
    val waypoints = wpArr.map { w -> point(w)?.let { SavedRoute.Waypoint(it.lat, it.lng) } ?: return null }
    return ParkCourse(
        id = id,
        routeId = routeId,
        name = name,
        laps = laps,
        timing = CourseTimingSpec(distanceM = distance, startGate = start, endGate = end, checkpoints = checkpoints),
        waypoints = waypoints,
    )
}

/// The `courses_json` array: every readable course, a refused one left out,
/// the first id kept where two share one, at most [PARK_COURSES_MAX]. Null
/// when the text is not a JSON array at all.
internal fun parseParkCoursesJson(json: Json, raw: String): List<ParkCourse>? {
    val arr = try {
        json.parseToJsonElement(raw) as? JsonArray
    } catch (_: Throwable) {
        null
    } ?: return null
    val seen = HashSet<String>()
    return arr.mapNotNull { parseParkCourse(it) }
        .filter { seen.add(it.id) }
        .take(PARK_COURSES_MAX)
}

/// Whether a delivery stamped [incoming] should replace what the watch shows,
/// last applied at [lastAppliedMs]: strictly newer, as the routes push.
internal fun shouldApplyParkCoursesPush(lastAppliedMs: Long, incoming: Long): Boolean =
    shouldApplyRoutesPush(lastAppliedMs, incoming)
