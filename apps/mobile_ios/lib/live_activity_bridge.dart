import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One frame of what the iOS Live Activity shows.
///
/// Every string is already localized and unit-formatted by the caller, so the
/// widget extension renders values and never formats or translates. That is
/// what keeps the lock screen and the run screen from ever disagreeing, and it
/// is why the extension ships with no String Catalog of its own.
@immutable
class LiveActivityFrame {
  const LiveActivityFrame({
    required this.title,
    required this.paused,
    required this.elapsed,
    required this.elapsedText,
    required this.timeLabel,
    required this.distanceLabel,
    required this.distanceText,
    required this.paceLabel,
    required this.paceText,
  });

  /// Lock-screen header. Carries the paused state in words, exactly as the
  /// Android ongoing notification's title does.
  final String title;
  final bool paused;

  /// Time the run has been running for, excluding pauses. Never sent as a
  /// number: it is turned into an anchor date the widget counts up from, so
  /// the clock ticks on-device between updates and costs no ActivityKit
  /// traffic at all.
  final Duration elapsed;

  /// The frozen clock shown while [paused], where a self-ticking timer would
  /// be a lie.
  final String elapsedText;

  final String timeLabel;
  final String distanceLabel;
  final String distanceText;
  final String paceLabel;
  final String paceText;

  /// [elapsed] and [elapsedText] are deliberately absent: the widget renders
  /// the running clock itself, so a tick is not a reason to spend an update,
  /// and a paused clock does not advance. Comparing them would push once a
  /// second forever and defeat [LiveActivityCadence] entirely.
  @override
  bool operator ==(Object other) =>
      other is LiveActivityFrame &&
      other.title == title &&
      other.paused == paused &&
      other.timeLabel == timeLabel &&
      other.distanceLabel == distanceLabel &&
      other.distanceText == distanceText &&
      other.paceLabel == paceLabel &&
      other.paceText == paceText;

  @override
  int get hashCode => Object.hash(
        title,
        paused,
        timeLabel,
        distanceLabel,
        distanceText,
        paceLabel,
        paceText,
      );
}

/// Decides whether a frame is worth an ActivityKit update. Pure: it holds the
/// last admitted frame and when it went out, and every verdict is a function
/// of that plus the caller's clock.
///
/// The recording stack offers a frame about once a second, which is the right
/// cadence for Android's `NotificationManager` and the wrong one for
/// ActivityKit — the system throttles frequent updates, and each one costs
/// battery on a run that can last a day. So: at most one update per
/// [minInterval], none at all when nothing rendered has changed, and a
/// pause/resume goes out immediately because a lock screen that disagrees
/// with the button the runner just pressed is the one failure they will
/// notice.
class LiveActivityCadence {
  LiveActivityCadence({this.minInterval = const Duration(seconds: 10)});

  final Duration minInterval;

  LiveActivityFrame? _last;
  DateTime? _lastAt;

  LiveActivityFrame? get lastFrame => _last;

  /// Pure query — [record] is what commits.
  bool shouldPush(LiveActivityFrame next, DateTime now) {
    final last = _last;
    final lastAt = _lastAt;
    if (last == null || lastAt == null) return true;
    if (next.paused != last.paused) return true;
    final since = now.difference(lastAt);
    // A negative interval means the wall clock stepped backwards (NTP, a
    // timezone change). Treating that as "not yet" would wedge the activity
    // until the clock caught up, so it counts as elapsed.
    if (!since.isNegative && since < minInterval) return false;
    return next != last;
  }

  void record(LiveActivityFrame frame, DateTime now) {
    _last = frame;
    _lastAt = now;
  }

  void reset() {
    _last = null;
    _lastAt = null;
  }
}

/// Signature of the platform call [LiveActivityBridge] makes. Injectable so
/// the bridge's own behaviour can be exercised without a platform channel,
/// the same seam idiom as `RouteNavigator.playOffRouteHaptic` on watchOS.
typedef LiveActivityInvoke = Future<bool?> Function(
  String method,
  Map<String, Object?> args,
);

/// Dart client for the native `LiveActivityBridge` method channel — the iOS
/// lock-screen / Dynamic Island live run, and the counterpart to Android's
/// ongoing foreground-service notification.
///
/// L4 by the layering contract (docs/features/run_recording.md § Layering):
/// every method swallows its own failure with a log, returns rather than
/// throws, and touches no recording state. ActivityKit is unavailable below
/// iOS 16.2, when the runner has turned Live Activities off, and when the
/// system has hit its activity ceiling — all three are ordinary outcomes
/// here, not errors.
///
/// Native side: `apps/mobile_ios/ios/Runner/LiveActivityBridge.swift`.
class LiveActivityBridge {
  LiveActivityBridge({
    LiveActivityInvoke? invoke,
    bool? supported,
    DateTime Function()? clock,
    Duration minInterval = const Duration(seconds: 10),
  })  : _invoke = invoke ?? _channelInvoke,
        // Platform dispatch inside the unified file, per the twin invariant
        // (decisions.md § 39): the Android build compiles this and no-ops.
        _supported = supported ?? Platform.isIOS,
        _clock = clock ?? DateTime.now,
        _cadence = LiveActivityCadence(minInterval: minInterval);

  static const _channel = MethodChannel('run_app/live_activity');

  static Future<bool?> _channelInvoke(
    String method,
    Map<String, Object?> args,
  ) {
    return _channel.invokeMethod<bool>(method, args);
  }

  final LiveActivityInvoke _invoke;
  final bool _supported;
  final DateTime Function() _clock;
  final LiveActivityCadence _cadence;

  bool _running = false;

  /// The instant the widget's self-ticking clock counts up from. Held rather
  /// than recomputed per push so the lock-screen clock does not jitter by the
  /// sub-second skew between the recorder's monotonic stopwatch and the wall
  /// clock; re-derived when the run resumes or when it has drifted past
  /// [_anchorTolerance] (a crash-recovered run restores an elapsed offset
  /// that moves it by minutes).
  DateTime? _anchor;

  static const _anchorTolerance = Duration(milliseconds: 1500);

  bool get isRunning => _running;

  /// Show the activity. A no-op on Android and a false return anywhere
  /// ActivityKit declines; the caller is not expected to react either way.
  Future<void> start(LiveActivityFrame frame) async {
    if (!_supported || _running) return;
    final now = _clock();
    _anchor = now.subtract(frame.elapsed);
    try {
      final started = await _invoke('start', _payload(frame));
      _running = started ?? false;
      if (_running) _cadence.record(frame, now);
    } catch (e) {
      debugPrint('LiveActivityBridge.start failed: $e');
      _running = false;
    }
  }

  /// Offer a frame. Drops it when [LiveActivityCadence] says it is not worth
  /// an update, so the recording stack can call this at its own rate.
  Future<void> update(LiveActivityFrame frame) async {
    if (!_supported || !_running) return;
    final now = _clock();
    if (!_cadence.shouldPush(frame, now)) return;
    _reanchor(frame, now);
    // Recorded before the await so a slow platform call cannot let a burst of
    // frames queue up behind it and all pass the interval at once.
    _cadence.record(frame, now);
    try {
      await _invoke('update', _payload(frame));
    } catch (e) {
      debugPrint('LiveActivityBridge.update failed: $e');
    }
  }

  /// End the activity and clear it from the lock screen. Safe to call when
  /// none is running — the native side also ends any it finds, so a run the
  /// process died during cannot leave one stranded.
  Future<void> stop() async {
    if (!_supported) return;
    _running = false;
    _anchor = null;
    _cadence.reset();
    try {
      await _invoke('stop', const <String, Object?>{});
    } catch (e) {
      debugPrint('LiveActivityBridge.stop failed: $e');
    }
  }

  void _reanchor(LiveActivityFrame frame, DateTime now) {
    final implied = now.subtract(frame.elapsed);
    final anchor = _anchor;
    if (anchor == null) {
      _anchor = implied;
      return;
    }
    if (frame.paused) return;
    final drift = implied.difference(anchor).abs();
    if (drift >= _anchorTolerance) _anchor = implied;
  }

  Map<String, Object?> _payload(LiveActivityFrame frame) {
    final anchor = _anchor ?? _clock().subtract(frame.elapsed);
    return <String, Object?>{
      'title': frame.title,
      'paused': frame.paused,
      'timer_start_epoch_ms': anchor.millisecondsSinceEpoch,
      'elapsed_text': frame.elapsedText,
      'time_label': frame.timeLabel,
      'distance_label': frame.distanceLabel,
      'distance_text': frame.distanceText,
      'pace_label': frame.paceLabel,
      'pace_text': frame.paceText,
    };
  }
}
