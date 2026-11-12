package com.threkir.app

import android.app.Activity
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Full brightness while the parkrun barcode is on screen. Overrides only this
/// activity's window, never the system setting, so leaving the app or closing
/// the activity hands the screen back to whatever the runner had. Dart side:
/// `lib/screen_brightness_bridge.dart` over `run_app/screen_brightness`.
class ScreenBrightnessBridge(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, "run_app/screen_brightness")

    init {
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val brightness = when (call.method) {
            "setMax" -> WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
            "restore" -> WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
            else -> {
                result.notImplemented()
                return
            }
        }
        val window = activity.window
        val params = window.attributes
        params.screenBrightness = brightness
        window.attributes = params
        result.success(null)
    }
}
