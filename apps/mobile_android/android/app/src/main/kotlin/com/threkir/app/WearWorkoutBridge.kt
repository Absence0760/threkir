package com.threkir.app

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Pushes today's planned workout to the paired Wear OS watch over the
/// Wearable Data Layer. The Dart side (`lib/watch_workout_push.dart`) builds
/// the JSON from the plan overview, already expanded into steps, and calls
/// `push`; the watch's `WorkoutBridge` listens at the same [PATH].
///
/// Sibling of [WearRoutesBridge]. One DataItem, overwritten on every push, so
/// the watch only ever sees the latest value, and a watch that pairs later
/// still finds it in the graph.
class WearWorkoutBridge(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, "run_app/wear_workout")
    private val dataClient = Wearable.getDataClient(context)

    init {
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "push" -> {
                @Suppress("UNCHECKED_CAST")
                val parsed = parseWearWorkoutPushArgs(
                    call.arguments as? Map<String, Any?>,
                    System.currentTimeMillis(),
                )
                if (parsed == null) {
                    result.error("bad_args", "push needs a workout_json string", null)
                    return
                }
                val req = PutDataMapRequest.create(PATH).apply {
                    dataMap.putString("workout_json", parsed.workoutJson)
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
        const val PATH = "/todays_workout"
    }
}

data class WearWorkoutPushArgs(
    val workoutJson: String,
    val updatedAtMs: Long,
)

/// Pure arg parser for `run_app/wear_workout` `push`.
///
/// Unlike the routes push, a missing `workout_json` is refused rather than
/// defaulted: there is no value this side could invent that means the same as
/// the phone's, and the explicit "nothing today" payload is one the Dart
/// writer always sends. `updated_at_ms` falls back to [nowMs], as the routes
/// bridge's does, so the watch's stale-push gate still has an order to keep.
internal fun parseWearWorkoutPushArgs(
    args: Map<String, Any?>?,
    nowMs: Long,
): WearWorkoutPushArgs? {
    if (args == null) return null
    val json = args["workout_json"] as? String ?: return null
    if (json.isBlank()) return null
    val updatedAtMs = (args["updated_at_ms"] as? Number)?.toLong() ?: nowMs
    return WearWorkoutPushArgs(json, updatedAtMs)
}
