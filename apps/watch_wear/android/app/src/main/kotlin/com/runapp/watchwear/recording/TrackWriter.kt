package com.runapp.watchwear.recording

import android.content.Context
import com.runapp.watchwear.GpsPoint
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
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
    private var open = false

    val pointCount: Int get() = count
    val path: String get() = file.absolutePath

    fun open() {
        file.parentFile?.mkdirs()
        file.delete()
        val pw = PrintWriter(BufferedWriter(FileWriter(file, false), BUFFER_BYTES))
        pw.print("[")
        pw.flush()
        writer = pw
        count = 0
        open = true
    }

    /// [distM] is the run's distance credited up to and including this fix,
    /// the axis splits and moving time are measured on
    /// (`docs/features/gps_distance.md` § Waypoint fields). [offTrack] marks a
    /// fix the distance estimator took past the 30 m track gate: stored so the
    /// server's replay sees every estimator input, written as `"offTrack":true`
    /// and omitted otherwise, and skipped by every reader that draws the line
    /// (`docs/features/gps_distance.md` § Stored track).
    fun append(point: GpsPoint, distM: Double? = null, offTrack: Boolean = false) {
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
                "}"
        )
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
