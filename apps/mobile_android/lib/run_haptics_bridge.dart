import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'step_haptics.dart';

/// Plays a [RunHapticPattern] on the phone's vibration motor over
/// `run_app/haptics` (Android `RunHapticsBridge.kt`, iOS `RunHapticsBridge`
/// in `AppDelegate.swift`).
///
/// Not `HapticFeedback`: that is a view-level touch effect, which Android
/// drops while the screen is off and which is too faint to feel through a
/// pocket anyway — and the screen is off for most of a run. The native side
/// drives the vibrator directly so the cue lands from the background.
///
/// An L4 auxiliary effect: every failure is logged and swallowed, so a
/// missing vibrator or an absent handler can never reach the recorder.
class RunHapticsBridge {
  const RunHapticsBridge();

  static const channelName = 'run_app/haptics';
  static const _channel = MethodChannel(channelName);

  Future<void> play(RunHapticPattern pattern) async {
    try {
      await _channel.invokeMethod<void>('play', pattern.wireName);
    } catch (e) {
      debugPrint('run haptic ${pattern.wireName} failed: $e');
    }
  }
}
