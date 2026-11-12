package com.threkir.app

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Drives the vibration motor for run cues over `run_app/haptics`. Dart side:
/// `lib/run_haptics_bridge.dart`.
///
/// Flutter's `HapticFeedback` goes through `View.performHapticFeedback`, which
/// Android ignores once the screen is off — and the screen is off for most of
/// a run. This calls the Vibrator directly, from a process the location
/// foreground service keeps at foreground-service importance.
///
/// Usage is NOTIFICATION, not ALARM. Both are on the list Android still lets a
/// backgrounded app vibrate with, should the service ever be gone. ALARM would
/// also override the runner's own ring mode and Do Not Disturb, which is the
/// right call for a wake-up and the wrong one for "rep 3 starts now": a runner
/// who silenced the phone gets silence. NOTIFICATION follows their
/// notification-vibration intensity setting instead.
class RunHapticsBridge(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
            ?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    init {
        MethodChannel(messenger, "run_app/haptics").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "play") {
            result.notImplemented()
            return
        }
        val pattern = RunHapticPatterns.byName[call.arguments as? String]
        if (pattern == null) {
            result.error("bad_args", "unknown haptic pattern: ${call.arguments}", null)
            return
        }
        val v = vibrator
        if (v == null || !v.hasVibrator()) {
            result.success(false)
            return
        }
        val effect = if (v.hasAmplitudeControl()) {
            VibrationEffect.createWaveform(pattern.timingsMs, pattern.amplitudes, -1)
        } else {
            VibrationEffect.createWaveform(pattern.timingsMs, -1)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            v.vibrate(
                effect,
                VibrationAttributes.createForUsage(VibrationAttributes.USAGE_NOTIFICATION),
            )
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(
                effect,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        result.success(true)
    }
}
