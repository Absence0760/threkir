package com.runapp.watchwear.recording

import android.content.Context
import com.runapp.watchwear.GpsPoint
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import java.io.IOException
import java.io.PrintWriter
import java.time.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/// Append-only writer that streams GPS points to a JSON array on disk
/// as they arrive, so a 10-hour run doesn't hold a 36,000-element list
/// in memory.
///
/// The output file is a valid JSON array — opens with `[`, comma-
/// separates points, closes with `]`. Readers (both the Dart api_client
/// and anything else decoding the Storage track file) see the exact
/// same shape as the old in-memory `encodeTrack` produced, so nothing
/// downstream changes.
///
/// Flushes every 32 points so a crash loses at most ~30s of GPS at 1Hz
/// while avoiding a disk write on every single sample.
class TrackWriter(private val file: File) {
    private var writer: PrintWriter? = null
    private var count = 0
    private var segments = 0
    private var open = false

    val pointCount: Int get() = count
    /// The estimator segments the file holds: its first fix opens one and
    /// every fix written `segmentStart` another, which is how the server's
    /// replay counts them. Saved as `metadata.distance_segments`, so the
    /// server can tell a track that lost its marks on the way to storage
    /// (`docs/features/gps_distance.md` § Server recompute).
    val segmentCount: Int get() = segments
    val path: String get() = file.absolutePath

    fun open() {
        file.parentFile?.mkdirs()
        file.delete()
        val pw = PrintWriter(BufferedWriter(FileWriter(file, false), BUFFER_BYTES))
        pw.print("[")
        pw.flush()
        writer = pw
        count = 0
        segments = 0
        open = true
    }

    /// [distM] is the run's distance credited up to and including this fix,
    /// the axis splits and moving time are measured on
    /// (`docs/features/gps_distance.md` § Waypoint fields). [offTrack] marks a
    /// fix the distance estimator took past the 30 m track gate: stored so the
    /// server's replay sees every estimator input, written as `"offTrack":true`
    /// and omitted otherwise, and skipped by every reader that draws the line
    /// (`docs/features/gps_distance.md` § Stored track). [segmentStart] marks
    /// the first fix after a pause or a source switch closed the estimator's
    /// segment, written as `"segmentStart":true` and omitted otherwise, so the
    /// server replays each segment apart (spec v1.8).
    fun append(
        point: GpsPoint,
        distM: Double? = null,
        offTrack: Boolean = false,
        segmentStart: Boolean = false,
    ) {
        val w = writer ?: return
        if (count > 0) w.print(",")
        val ts = Instant.ofEpochMilli(point.epochMs)
        val ele = point.ele?.toString() ?: "null"
        w.print(
            "{\"lat\":${point.lat}," +
                "\"lng\":${point.lng}," +
                "\"ele\":$ele," +
                "\"ts\":\"$ts\"" +
                optionalField("accuracyMetres", point.accuracyM?.takeIf { it > 0 }) +
                optionalField("speedMps", point.speedMps?.takeIf { it >= 0 }) +
                optionalField("speedAccuracyMps", point.speedAccuracyMps?.takeIf { it > 0 }) +
                optionalField("bearingDeg", point.bearingDeg) +
                optionalField("distM", distM?.takeIf { it.isFinite() && it >= 0 }?.let { Math.round(it * 100) / 100.0 }) +
                (if (offTrack) ",\"offTrack\":true" else "") +
                (if (segmentStart) ",\"segmentStart\":true" else "") +
                "}"
        )
        if (count == 0 || segmentStart) segments++
        count++
        if (count % FLUSH_EVERY == 0) w.flush()
    }

    /// The estimator inputs, so the server can recompute distance from the
    /// stored track (`docs/features/gps_distance.md` § Waypoint fields). A key
    /// is omitted rather than written as null when the fix did not carry it.
    private fun optionalField(key: String, value: Double?): String =
        if (value != null && value.isFinite()) ",\"$key\":$value" else ""

    /// Close and return the finished file. Safe to call more than once;
    /// the file contents remain a valid JSON array once sealed.
    fun close(): File {
        val w = writer
        if (open && w != null) {
            w.print("]")
            w.flush()
            w.close()
        }
        writer = null
        open = false
        return file
    }

    companion object {
        private const val BUFFER_BYTES = 8192
        private const val FLUSH_EVERY = 32

        /// Return a file handle in the app's durable files dir for a given
        /// run id. Until the run has uploaded this file is the only copy of
        /// the trace, so it must not sit anywhere the platform may reclaim
        /// on its own — see [TrackStorage].
        fun fileFor(context: Context, runId: String): File =
            TrackStorage.fileFor(context, runId)
    }
}

/// The line of a stored track file's JSON [raw]: each point's lat / lng, in
/// order, skipping a fix written `"offTrack":true` (one the distance
/// estimator took past the track gate, stored only for the server's replay)
/// and any entry without a numeric coordinate. Throws on text that is not
/// JSON, as `Json.parseToJsonElement` does; a JSON value that is not an array
/// is an empty line.
fun trackLineLatLngs(raw: String): List<RouteMath.LatLng> {
    val arr = Json.parseToJsonElement(raw) as? JsonArray ?: return emptyList()
    return arr.mapNotNull { el ->
        val obj = el as? JsonObject ?: return@mapNotNull null
        if ((obj["offTrack"] as? JsonPrimitive)?.booleanOrNull == true) return@mapNotNull null
        val lat = (obj["lat"] as? JsonPrimitive)?.content?.toDoubleOrNull() ?: return@mapNotNull null
        val lng = (obj["lng"] as? JsonPrimitive)?.content?.toDoubleOrNull() ?: return@mapNotNull null
        RouteMath.LatLng(lat, lng)
    }
}

/// The estimator segments a stored track [file] holds, counted as the
/// server's replay counts them: the first point carrying a coordinate and a
/// timestamp opens one, and so does every later such point at or after a
/// `"segmentStart":true` (a mark on a point the replay skips carries to the
/// next it reads). [TrackWriter.segmentCount] gives the same figure while the
/// file is written; this is the count for a run recovered from a checkpoint,
/// whose file holds fixes the last checkpoint never saw. Streams one point at
/// a time, since a 100-hour track is tens of megabytes. Null when the file is
/// missing or a point does not parse, so the run omits
/// `metadata.distance_segments` and the server keeps its run-total rule.
fun trackFileSegmentCount(file: File): Int? {
    if (!file.exists()) return null
    return try {
        file.bufferedReader().use { reader ->
            var points = 0
            var segments = 0
            var markPending = false
            val open = ArrayDeque<Char>()
            var inString = false
            var escaped = false
            val point = StringBuilder()
            while (true) {
                val c = reader.read()
                if (c < 0) break
                val ch = c.toChar()
                if (open.size >= 2) point.append(ch)
                if (inString) {
                    when {
                        escaped -> escaped = false
                        ch == '\\' -> escaped = true
                        ch == '"' -> inString = false
                    }
                    continue
                }
                when (ch) {
                    '"' -> inString = true
                    '[', '{' -> {
                        open.addLast(ch)
                        if (open.size == 2) {
                            point.setLength(0)
                            point.append(ch)
                        }
                    }
                    ']', '}' -> {
                        // A point cut off mid-write and then sealed closes
                        // with the wrong bracket: its count is unknown.
                        if (open.removeLastOrNull() != (if (ch == ']') '[' else '{')) return null
                        if (open.size == 1 && ch == '}') {
                            val obj = Json.parseToJsonElement(point.toString()) as? JsonObject ?: return null
                            markPending = markPending ||
                                (obj["segmentStart"] as? JsonPrimitive)?.booleanOrNull == true
                            val placed = (obj["lat"] as? JsonPrimitive)?.content?.toDoubleOrNull() != null &&
                                (obj["lng"] as? JsonPrimitive)?.content?.toDoubleOrNull() != null &&
                                (obj["ts"] as? JsonPrimitive)?.isString == true
                            if (placed) {
                                if (points == 0 || markPending) segments++
                                markPending = false
                                points++
                            }
                        }
                    }
                }
            }
            if (open.isNotEmpty() || inString) null else segments
        }
    } catch (e: IOException) {
        null
    } catch (e: IllegalArgumentException) {
        // kotlinx.serialization's SerializationException: a point that is
        // not JSON.
        null
    }
}
