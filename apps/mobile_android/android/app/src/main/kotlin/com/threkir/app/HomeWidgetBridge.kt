package com.threkir.app

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Native half of `run_app/home_widget`. The Dart side
/// (`lib/today_widget.dart`) owns the snapshot, its strings and its units;
/// this side stores the text as given and asks every today's-workout widget
/// to redraw from it.
class HomeWidgetBridge(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val appContext = context.applicationContext
    private val methodChannel = MethodChannel(messenger, CHANNEL)

    init {
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "update" -> {
                @Suppress("UNCHECKED_CAST")
                val json = parseHomeWidgetUpdateArgs(call.arguments as? Map<String, Any?>)
                if (json == null) {
                    result.error("bad_args", "update needs a snapshot_json string", null)
                    return
                }
                TodayWorkoutWidgetProvider.store(appContext, json)
                TodayWorkoutWidgetProvider.redrawAll(appContext)
                result.success(null)
            }
            "clear" -> {
                TodayWorkoutWidgetProvider.store(appContext, null)
                TodayWorkoutWidgetProvider.redrawAll(appContext)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "run_app/home_widget"
    }
}
