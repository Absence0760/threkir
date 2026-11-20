package com.threkir.app

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Puts the park courses the runner navigated on the paired Wear OS watch
/// over the Wearable Data Layer, for live course timing on the wrist (#1446).
/// The Dart side (`lib/watch_park_courses.dart`) builds `courses_json` and
/// calls `push`; the watch's `ParkCourseBridge` listens at the same [PATH]
/// and holds the contract `fixtures/wear_park_courses_payload.json`.
///
/// Sibling of [WearWorkoutBridge]: one DataItem, overwritten on every push,
/// so a watch that pairs later still finds the list in the graph. An empty
/// array is a value, the phone saying "none", which clears the watch's rows.
class WearParkCoursesBridge(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, "run_app/wear_park_courses")
    private val dataClient = Wearable.getDataClient(context)

    init {
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "push" -> {
                @Suppress("UNCHECKED_CAST")
                val parsed = parseWearParkCoursesPushArgs(
                    call.arguments as? Map<String, Any?>,
                    System.currentTimeMillis(),
                )
                if (parsed == null) {
                    result.error("bad_args", "push needs a courses_json array", null)
                    return
                }
                val req = PutDataMapRequest.create(PATH).apply {
                    dataMap.putInt("payload_version", PAYLOAD_VERSION)
                    dataMap.putString("courses_json", parsed.coursesJson)
                    dataMap.putLong("updated_at_ms", parsed.updatedAtMs)
                }
                dataClient.putDataItem(req.asPutDataRequest().setUrgent())
                    .addOnSuccessListener { result.success(null) }
                    .addOnFailureListener { result.error("put_failed", it.message, null) }
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val PATH = "/park_courses"

        /// The version the watch reads (`PARK_COURSES_PAYLOAD_VERSION`); it
        /// drops any other whole rather than reading it as no courses.
        const val PAYLOAD_VERSION = 1
    }
}

data class WearParkCoursesPushArgs(
    val coursesJson: String,
    val updatedAtMs: Long,
)

/// Pure arg parser for `run_app/wear_park_courses` `push`.
///
/// A `courses_json` that is not text starting a JSON array is refused, not
/// defaulted: the watch drops such an item whole, and an empty list has its
/// own meaning (clear) that this side must never invent. `updated_at_ms`
/// falls back to [nowMs], as the other bridges' do, so the watch's
/// stale-push gate still has an order to keep.
internal fun parseWearParkCoursesPushArgs(
    args: Map<String, Any?>?,
    nowMs: Long,
): WearParkCoursesPushArgs? {
    if (args == null) return null
    val json = args["courses_json"] as? String ?: return null
    if (!json.trimStart().startsWith("[")) return null
    val updatedAtMs = (args["updated_at_ms"] as? Number)?.toLong() ?: nowMs
    return WearParkCoursesPushArgs(json, updatedAtMs)
}
