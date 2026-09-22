import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/live_activity_bridge.dart';

LiveActivityFrame frame({
  String title = 'Run',
  bool paused = false,
  Duration elapsed = const Duration(minutes: 1),
  String distance = '1.20 km',
  String pace = '5:30 /km',
}) {
  return LiveActivityFrame(
    title: title,
    paused: paused,
    elapsed: elapsed,
    elapsedText: '${elapsed.inMinutes}:00',
    timeLabel: 'Time',
    distanceLabel: 'Distance',
    distanceText: distance,
    paceLabel: 'Pace',
    paceText: pace,
  );
}

/// Records what crossed the seam, and can be made to fail or refuse.
class _FakeChannel {
  _FakeChannel({this.startAnswer = true, this.throws = false});

  final bool startAnswer;
  final bool throws;
  final calls = <(String, Map<String, Object?>)>[];

  Future<bool?> invoke(String method, Map<String, Object?> args) async {
    calls.add((method, args));
    if (throws) throw PlatformException(code: 'unavailable');
    return method == 'start' ? startAnswer : true;
  }

  List<String> get methods => calls.map((c) => c.$1).toList();
}

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 8);

  group('LiveActivityFrame equality', () {
    test('ignores the clock, which the widget renders itself', () {
      expect(
        frame(elapsed: const Duration(minutes: 1)),
        frame(elapsed: const Duration(minutes: 9)),
        reason: 'a tick is not a reason to spend an ActivityKit update — the '
            'widget counts up from an anchor date on its own',
      );
    });

    test('tracks every value the widget actually draws', () {
      expect(frame(distance: '1.20 km'), isNot(frame(distance: '1.21 km')));
      expect(frame(pace: '5:30 /km'), isNot(frame(pace: '5:31 /km')));
      expect(frame(title: 'Run'), isNot(frame(title: 'Ride')));
      expect(frame(paused: false), isNot(frame(paused: true)));
    });
  });

  group('LiveActivityCadence', () {
    test('admits the first frame — nothing is on screen yet', () {
      final c = LiveActivityCadence();
      expect(c.shouldPush(frame(), t0), isTrue);
    });

    test('drops everything inside the interval', () {
      final c = LiveActivityCadence()..record(frame(), t0);
      expect(
        c.shouldPush(frame(distance: '1.30 km'), t0.add(const Duration(seconds: 9))),
        isFalse,
      );
    });

    test('drops an unchanged frame even once the interval has passed', () {
      final c = LiveActivityCadence()..record(frame(), t0);
      expect(c.shouldPush(frame(), t0.add(const Duration(minutes: 5))), isFalse);
    });

    test('admits a changed frame once the interval has passed', () {
      final c = LiveActivityCadence()..record(frame(), t0);
      expect(
        c.shouldPush(frame(distance: '1.30 km'), t0.add(const Duration(seconds: 10))),
        isTrue,
      );
    });

    test('a pause jumps the interval', () {
      final c = LiveActivityCadence()..record(frame(), t0);
      expect(
        c.shouldPush(frame(paused: true), t0.add(const Duration(milliseconds: 20))),
        isTrue,
        reason: 'a lock screen that disagrees with the button just pressed is '
            'the one failure a runner notices',
      );
    });

    test('a wall clock that stepped backwards does not wedge it', () {
      final c = LiveActivityCadence()..record(frame(), t0);
      expect(
        c.shouldPush(frame(distance: '1.30 km'), t0.subtract(const Duration(hours: 1))),
        isTrue,
      );
    });
  });

  group('LiveActivityBridge', () {
    test('makes no platform call at all where ActivityKit does not exist', () async {
      final ch = _FakeChannel();
      final bridge = LiveActivityBridge(invoke: ch.invoke, supported: false);
      await bridge.start(frame());
      await bridge.update(frame(distance: '2.00 km'));
      await bridge.stop();
      expect(ch.calls, isEmpty);
      expect(bridge.isRunning, isFalse);
    });

    test('starts once, then updates at the cadence', () async {
      final ch = _FakeChannel();
      var now = t0;
      final bridge = LiveActivityBridge(
        invoke: ch.invoke,
        supported: true,
        clock: () => now,
      );
      await bridge.start(frame());
      expect(bridge.isRunning, isTrue);

      now = t0.add(const Duration(seconds: 3));
      await bridge.update(frame(distance: '1.30 km'));
      now = t0.add(const Duration(seconds: 12));
      await bridge.update(frame(distance: '1.40 km'));

      expect(ch.methods, ['start', 'update']);
      expect(ch.calls.last.$2['distance_text'], '1.40 km');
    });

    test('a refused start is not retried for the rest of the run', () async {
      final ch = _FakeChannel(startAnswer: false);
      final bridge = LiveActivityBridge(invoke: ch.invoke, supported: true);
      await bridge.start(frame());
      expect(bridge.isRunning, isFalse);
      await bridge.update(frame(distance: '2.00 km'));
      expect(ch.methods, ['start'],
          reason: 'areActivitiesEnabled is a setting, not a transient — '
              'hammering Activity.request is the battery cost this avoids');
    });

    test('a throwing platform call is swallowed and leaves no activity (L4)',
        () async {
      final ch = _FakeChannel(throws: true);
      final bridge = LiveActivityBridge(invoke: ch.invoke, supported: true);
      await bridge.start(frame());
      expect(bridge.isRunning, isFalse);
      await bridge.update(frame());
      await bridge.stop();
      expect(ch.methods, ['start', 'stop']);
    });

    test('holds the clock anchor still while the run runs', () async {
      final ch = _FakeChannel();
      var now = t0;
      final bridge = LiveActivityBridge(
        invoke: ch.invoke,
        supported: true,
        clock: () => now,
      );
      await bridge.start(frame(elapsed: Duration.zero));
      now = t0.add(const Duration(seconds: 30, milliseconds: 400));
      // A second off the wall clock, as the recorder's monotonic stopwatch
      // and DateTime.now() drift apart.
      await bridge.update(
        frame(elapsed: const Duration(seconds: 30), distance: '2.00 km'),
      );
      final anchors =
          ch.calls.map((c) => c.$2['timer_start_epoch_ms']).toSet();
      expect(anchors, hasLength(1),
          reason: 'a re-derived anchor makes the lock-screen clock jitter');
    });

    test('re-derives the anchor across a pause, so resuming is not backdated',
        () async {
      final ch = _FakeChannel();
      var now = t0;
      final bridge = LiveActivityBridge(
        invoke: ch.invoke,
        supported: true,
        clock: () => now,
      );
      await bridge.start(frame(elapsed: Duration.zero));
      now = t0.add(const Duration(seconds: 20));
      await bridge.update(frame(elapsed: const Duration(seconds: 20), paused: true));
      // Five minutes standing still, none of which is running time.
      now = t0.add(const Duration(minutes: 5, seconds: 20));
      await bridge.update(frame(elapsed: const Duration(seconds: 21)));

      final resumed = ch.calls.last.$2['timer_start_epoch_ms']! as int;
      expect(
        DateTime.fromMillisecondsSinceEpoch(resumed, isUtc: true),
        now.subtract(const Duration(seconds: 21)),
      );
    });

    test('a second run starts a fresh activity after stop', () async {
      final ch = _FakeChannel();
      final bridge = LiveActivityBridge(invoke: ch.invoke, supported: true);
      await bridge.start(frame());
      await bridge.stop();
      expect(bridge.isRunning, isFalse);
      await bridge.start(frame());
      expect(ch.methods, ['start', 'stop', 'start']);
      expect(bridge.isRunning, isTrue);
    });
  });
}
