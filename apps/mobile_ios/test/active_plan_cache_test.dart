// The saved active plan that answers Home, the Run tab and the dashboard
// offline (#1186 Robustness: "store the active plan on disk").

import 'dart:io';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/active_plan_cache.dart';
import '../lib/training_service.dart';

final _start = DateTime(2026, 3, 9); // a Monday

final _plan = TrainingPlanRow(
  id: 'plan-1',
  userId: 'user-a',
  name: 'Spring Half',
  goalEvent: 'distance_half',
  goalDistanceM: 21097.5,
  startDate: _start,
  endDate: _start.add(const Duration(days: 13)),
  daysPerWeek: 4,
  status: 'active',
  source: 'generated',
  rules: const [],
  isTemplate: false,
  isPublicTemplate: false,
);

PlanWorkoutRow _wo(String id, String weekId, int day, {String kind = 'easy'}) =>
    PlanWorkoutRow(
      id: id,
      weekId: weekId,
      scheduledDate: _start.add(Duration(days: day)),
      kind: kind,
      targetDistanceM: 8000,
      manuallyCompleted: false,
    );

final _snapshot = ActivePlanSnapshot(
  activePlans: [_plan],
  detail: (
    plan: _plan,
    weeks: const [
      PlanWeekRow(id: 'w1', planId: 'plan-1', weekIndex: 0, phase: 'base'),
      PlanWeekRow(id: 'w2', planId: 'plan-1', weekIndex: 1, phase: 'build'),
    ],
    workouts: [
      _wo('mon', 'w1', 0),
      _wo('tue', 'w1', 1, kind: 'rest'),
      _wo('wed', 'w1', 2),
      _wo('next-mon', 'w2', 7),
    ],
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a saved plan reads back for the same account', () async {
    await writeActivePlanCache('user-a', _snapshot);
    final back = await readActivePlanCache('user-a');

    expect(back, isNotNull);
    expect(back!.activePlans.single.id, 'plan-1');
    expect(back.detail!.weeks.map((w) => w.id), ['w1', 'w2']);
    expect(back.detail!.workouts.map((w) => w.id),
        ['mon', 'tue', 'wed', 'next-mon']);
    expect(back.detail!.workouts.first.scheduledDate, _start,
        reason: 'the date survives the round trip');
  });

  test('another account never reads it', () async {
    await writeActivePlanCache('user-a', _snapshot);
    expect(await readActivePlanCache('user-b'), isNull);
  });

  test('sign-out clears it', () async {
    await writeActivePlanCache('user-a', _snapshot);
    await clearActivePlanCache();
    expect(await readActivePlanCache('user-a'), isNull);
  });

  test('a copy that no longer parses reads as none, not a throw', () async {
    SharedPreferences.setMockInitialValues(
        {kActivePlanCacheKey: '{"user_id":"user-a","active_plans":[{"id":1}]}'});
    expect(await readActivePlanCache('user-a'), isNull);
  });

  group('activeOverviewFrom', () {
    test('derives today at read time, so an old copy names today', () {
      final wed = activeOverviewFrom(_snapshot, _start.add(const Duration(days: 2, hours: 7)));
      expect(wed!.todayWorkout?.id, 'wed');
      expect(wed.currentWeekIndex, 0);

      final nextMon =
          activeOverviewFrom(_snapshot, _start.add(const Duration(days: 7, hours: 7)));
      expect(nextMon!.todayWorkout?.id, 'next-mon');
      expect(nextMon.currentWeekIndex, 1);
    });

    test('a rest day is not today\'s workout', () {
      final tue = activeOverviewFrom(_snapshot, _start.add(const Duration(days: 1, hours: 7)));
      expect(tue!.todayWorkout, isNull);
    });

    test('no active plan, or no detail for it, is no overview', () {
      expect(
          activeOverviewFrom(
              const ActivePlanSnapshot(activePlans: [], detail: null), _start),
          isNull);
      expect(
          activeOverviewFrom(
              ActivePlanSnapshot(activePlans: [_plan], detail: null), _start),
          isNull);
    });
  });

  test('the sign-out handler clears the saved plan', () {
    final main = File('lib/main.dart').readAsStringSync();
    final signedOut = main.indexOf('event.event == AuthChangeEvent.signedOut');
    expect(signedOut, greaterThan(0));
    final next = main.indexOf('} else if (event.event ==', signedOut + 1);
    final branch = main.substring(signedOut, next > 0 ? next : main.length);
    expect(branch, contains('clearActivePlanCache()'),
        reason: "the departing account's plan must not outlive sign-out");
  });
}
