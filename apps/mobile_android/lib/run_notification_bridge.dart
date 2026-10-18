import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'live_activity_bridge.dart' show LiveActivityFrame;

/// What the ongoing notification shows for one [LiveActivityFrame] — the
/// same frame the iOS Live Activity renders, so the two lock screens agree.
///
/// On a structured workout the step takes the title, because the collapsed
/// row is a title and one line and the step is what the runner acts on; the
/// stats keep the line. A paused run keeps its paused title, since the state
/// of the button just pressed matters more than the step, and the step moves
/// to the top of the expanded text instead of disappearing.
({String title, String text, String bigText}) runNotificationContent(
  LiveActivityFrame frame,
) {
  final stats =
      '${frame.elapsedText}  •  ${frame.distanceText}  •  ${frame.paceText}';
  final statsBig = '${frame.timeLabel}: ${frame.elapsedText}\n'
      '${frame.distanceLabel}: ${frame.distanceText}\n'
      '${frame.paceLabel}: ${frame.paceText}';
  final step = frame.step;
  if (step == null) {
    return (title: frame.title, text: stats, bigText: statsBig);
  }
  if (frame.paused) {
    return (
      title: frame.title,
      text: stats,
      bigText: '${step.line}\n$statsBig',
    );
  }
  return (title: step.line, text: stats, bigText: statsBig);
}

/// Dart client for the native `RunNotificationBridge` method channel.
///
/// Overrides the geolocator foreground-service notification with live run
/// stats, so the lock screen shows time / distance / pace during a run.
/// See `android/app/src/main/kotlin/com/threkir/app/RunNotificationBridge.kt`
/// for the Android side (the native receiver reposts on geolocator's
/// channel id + notification id to replace rather than duplicate).
class RunNotificationBridge {
  static const _channel = MethodChannel('run_app/run_notification');

  /// Lock-screen action callbacks (Android #14). The native side renders
  /// Pause/Resume + Stop buttons on the foreground-service notification;
  /// tapping one launches MainActivity with a `run_action` extra, which
  /// forwards here over the same channel. The run screen wires these to
  /// the recorder. Null on iOS (the channel has no native handler there,
  /// so the buttons never exist and these never fire).
  void Function()? onPause;
  void Function()? onResume;
  void Function()? onStop;

  RunNotificationBridge() {
    _channel.setMethodCallHandler(_handleNativeCall);
    // Tell the native side the Dart handler is live so any action that
    // arrived during a cold start (process relaunched by tapping the
    // notification) is flushed now instead of dropped.
    _channel.invokeMethod<void>('ready').catchError((Object _) {});
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'action') {
      switch (call.arguments as String?) {
        case 'pause':
          onPause?.call();
          break;
        case 'resume':
          onResume?.call();
          break;
        case 'stop':
          onStop?.call();
          break;
      }
    }
    return null;
  }

  /// Update the notification with the supplied stats. Safe to call from
  /// every snapshot — the native side just calls `NotificationManager.notify`
  /// which dedupes by id, and the phone's notification shade redraws
  /// cheaply. [bigText] is optional multi-line content shown when the
  /// user expands the notification. [paused] flips the Pause action to
  /// Resume so the lock-screen control matches the recorder state.
  Future<void> update({
    required String title,
    required String text,
    String? bigText,
    bool paused = false,
  }) async {
    try {
      await _channel.invokeMethod<void>('update', {
        'title': title,
        'text': text,
        if (bigText != null) 'big_text': bigText,
        'paused': paused,
      });
    } catch (e) {
      debugPrint('RunNotificationBridge.update failed: $e');
    }
  }

  /// Cancel the replacement notification. Called from `_stop` and
  /// `_discard` in `run_screen` so the lock-screen row disappears the
  /// moment the run ends, even if the geolocator foreground-service
  /// teardown races the UI transition. The native side also cancels
  /// the split row so a finished run leaves nothing in the shade.
  Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } catch (e) {
      debugPrint('RunNotificationBridge.clear failed: $e');
    }
  }

  /// Post the per-split notification. The native side uses a single
  /// fixed id (distinct from the ongoing-run row) so each new split
  /// replaces the previous one instead of stacking one notification
  /// per kilometre, and marks it auto-cancelling + timed-out so it
  /// never needs a manual swipe (#303).
  Future<void> updateSplit({
    required String title,
    required String text,
  }) async {
    try {
      await _channel.invokeMethod<void>('update_split', {
        'title': title,
        'text': text,
      });
    } catch (e) {
      debugPrint('RunNotificationBridge.updateSplit failed: $e');
    }
  }

  /// Cancel any leftover split notification. Called when a run starts
  /// so a previous run's split row can't linger into the next session
  /// (#303) — `clear` covers the stop/discard side.
  Future<void> clearSplit() async {
    try {
      await _channel.invokeMethod<void>('clear_split');
    } catch (e) {
      debugPrint('RunNotificationBridge.clearSplit failed: $e');
    }
  }
}
