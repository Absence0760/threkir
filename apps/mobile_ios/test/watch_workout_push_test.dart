// Today's planned workout, phone to wrist: the payload the phone builds for
// Wear OS and the Apple Watch, held to the fixture both watches decode
// (`fixtures/watch_workout_payload.json`), and the bridge that delivers it.

import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_workout_steps.dart';
import '../lib/training_service.dart';
import '../lib/watch_workout_push.dart';

final Map<String, dynamic> _fixture = jsonDecode(
  File('../../fixtures/watch_workout_payload.json').readAsStringSync(),
) as Map<String, dynamic>;

/// Round-trip through JSON text so the comparison is of what reaches the
/// channel, not of Dart map identity (`int` vs `double` included).
dynamic _wire(Object value) => jsonDecode(jsonEncode(value));

PlanWorkoutRow _workout({
  String id = 'pw-1',
  required DateTime date,
  String kind = 'easy',
  double? distanceM = 8000,
  int? paceSecPerKm = 345,
  String? completedRunId,
  DateTime? skippedAt,
  Object? structure,
}) =>
    PlanWorkoutRow(
      id: id,
      weekId: 'wk-1',
      scheduledDate: date,
      kind: kind,
      targetDistanceM: distanceM,
      targetPaceSecPerKm: paceSecPerKm,
      structure: structure,
      completedRunId: completedRunId,
      skippedAt: skippedAt,
      manuallyCompleted: false,
    );

ActivePlanOverview _overview(List<PlanWorkoutRow> workouts, DateTime now) =>
    ActivePlanOverview(
      plan: TrainingPlanRow(
        id: 'plan-1',
        userId: 'u1',
        name: 'Autumn 10k',
        goalEvent: '10k',
        goalDistanceM: 10000,
        startDate: now.subtract(const Duration(days: 14)),
        endDate: now.add(const Duration(days: 42)),
        daysPerWeek: 4,
        status: 'active',
        source: 'app',
        isTemplate: false,
        isPublicTemplate: false,
      ),
      weeks: const [],
      workouts: workouts,
      todayWorkout: null,
      completionPct: 0,
      currentWeekIndex: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('payload matches the cross-platform fixture', () {
    for (final c in (_fixture['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final workout =
            PlanWorkoutRow.fromJson(c['workout'] as Map<String, dynamic>);
        final paces = (c['paces'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt()));
        final steps = expandPlanWorkoutSteps(workout, paces: paces);
        expect(
          _wire(watchWorkoutPayloadFor(workout, steps)),
          c['payload'],
        );
      });
    }
  });

  group('buildWatchWorkoutPayload', () {
    final now = DateTime(2026, 10, 16, 7, 30);
    const none = {'v': kWatchWorkoutPayloadVersion};

    test('no plan is the explicit nothing-today value', () {
      expect(buildWatchWorkoutPayload(null, now), none);
    });

    test("today's open workout is pushed with its steps", () {
      final today = _workout(date: DateTime(2026, 10, 16));
      final payload = _wire(buildWatchWorkoutPayload(
        _overview([_workout(id: 'yesterday', date: DateTime(2026, 10, 15)), today], now),
        now,
      )) as Map<String, dynamic>;
      expect(payload['plan_workout_id'], 'pw-1');
      expect(payload['scheduled_date'], '2026-10-16');
      expect(payload['steps'], [
        {'kind': 'steady', 'distance_m': 8000, 'pace_s_per_km': 345, 'tolerance_s_per_km': 10},
      ]);
    });

    test('a workout already done, skipped, or a rest day is not offered', () {
      final date = DateTime(2026, 10, 16);
      for (final w in [
        _workout(date: date, completedRunId: 'run-1'),
        _workout(date: date, skippedAt: now),
        _workout(date: date, kind: 'rest'),
      ]) {
        expect(buildWatchWorkoutPayload(_overview([w], now), now), none);
      }
    });

    test('a workout on another day is not offered', () {
      final w = _workout(date: DateTime(2026, 10, 17));
      expect(buildWatchWorkoutPayload(_overview([w], now), now), none);
    });

    test('a session the WKT1 gate refuses is offered on no wrist', () {
      // 30 s/km is outside the 2:00-99:00 /km plausibility band every
      // watch enforces, so no rail would run it.
      final w = _workout(date: DateTime(2026, 10, 16), paceSecPerKm: 30);
      expect(buildWatchWorkoutPayload(_overview([w], now), now), none);
    });
  });

  group('WatchWorkoutBridge', () {
    final calls = <(String, MethodCall)>[];
    Object? throwOnCall;

    void install(String channel) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (call) async {
        calls.add((channel, call));
        final t = throwOnCall;
        if (t != null) throw t;
        return null;
      });
    }

    setUp(() {
      calls.clear();
      throwOnCall = null;
      WatchWorkoutBridge().resetForTest();
      install(WatchWorkoutBridge.wearChannelName);
      install(WatchWorkoutBridge.appleChannelName);
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      for (final c in [
        WatchWorkoutBridge.wearChannelName,
        WatchWorkoutBridge.appleChannelName,
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MethodChannel(c), null);
      }
    });

    final now = DateTime(2026, 10, 16, 7, 30);
    final overview = _overview([_workout(date: DateTime(2026, 10, 16))], now);

    test('Android writes the Data Layer item, once per distinct payload',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await WatchWorkoutBridge().publish(overview, now: now);
      await WatchWorkoutBridge().publish(overview, now: now);
      expect(calls, hasLength(1));
      final (channel, call) = calls.single;
      expect(channel, WatchWorkoutBridge.wearChannelName);
      expect(call.method, 'push');
      final args = call.arguments as Map;
      expect(jsonDecode(args['workout_json'] as String)['plan_workout_id'], 'pw-1');
      expect(args['updated_at_ms'], isA<int>());
    });

    test('iOS queues the same JSON text for transferUserInfo', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await WatchWorkoutBridge().publish(overview, now: now);
      final (channel, call) = calls.single;
      expect(channel, WatchWorkoutBridge.appleChannelName);
      expect(call.method, 'push_workout');
      expect(
        (call.arguments as Map)['workout_json'],
        jsonEncode(buildWatchWorkoutPayload(overview, now)),
      );
    });

    test('a refused push is not remembered, so the next read retries it',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      throwOnCall = PlatformException(code: 'put_failed');
      await WatchWorkoutBridge().publish(overview, now: now);
      throwOnCall = null;
      await WatchWorkoutBridge().publish(overview, now: now);
      expect(calls, hasLength(2));
    });

    test('the plan going away pushes the nothing-today value', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await WatchWorkoutBridge().publish(overview, now: now);
      await WatchWorkoutBridge().publish(null, now: now);
      expect(calls, hasLength(2));
      expect(
        jsonDecode((calls.last.$2.arguments as Map)['workout_json'] as String),
        {'v': 1},
      );
    });

    test('other platforms push nothing', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await WatchWorkoutBridge().publish(overview, now: now);
      expect(calls, isEmpty);
    });
  });
}
