import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local flag: this phone's runner has completed a hold-to-stop at
/// least once, so the one-time "Hold to stop" hint on the Stop button is
/// retired (issue #1253). A gesture hint is about the device in hand, so it
/// lives in raw SharedPreferences and never roams through the settings bags.
const kHoldToStopLearnedKey = 'hold_to_stop_learned';

/// Whether the hold-to-stop gesture has been learned on this device.
///
/// A storage failure reads as learned: a hint that cannot record its own
/// retirement would otherwise replay on every run for the life of the
/// install, and the stop control works the same either way.
Future<bool> holdToStopLearned() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kHoldToStopLearnedKey) ?? false;
  } catch (e) {
    debugPrint('hold-to-stop hint: reading the learned flag failed: $e');
    return true;
  }
}

/// Records that a hold-to-stop completed on this device. Never throws: it
/// runs right after the stop it follows and must not be able to disturb it.
Future<void> markHoldToStopLearned() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kHoldToStopLearnedKey, true);
  } catch (e) {
    debugPrint('hold-to-stop hint: saving the learned flag failed: $e');
  }
}
