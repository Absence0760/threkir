import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_nudges.dart';
import '../lib/preferences.dart';
import '../lib/settings_sync.dart';
import '../lib/training_service.dart';
import '../lib/widgets/plan_nudge_card.dart';
import 'pump_until.dart';

/// Home's plan card (decisions § 2125). Which occurrence fires is pinned in
/// plan_nudges_test; this pins the card: what it says, that Review hands the
/// occurrence to the host and files it, that Dismiss files it in the prefs
/// bag and hides the card, and that a refused dismissal keeps the card and
/// says so.

class _FakeSettingsService extends SettingsService {
  _FakeSettingsService(this.values)
      : super(deviceId: 'test-device', platform: 'android');
  final Map<String, dynamic> values;

  @override
  T? effective<T>(String key, {T? fallback}) =>
      values.containsKey(key) ? values[key] as T? : fallback;
}

class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(this._service) : super(preferences: Preferences());
  final _FakeSettingsService _service;
  final List<Map<String, dynamic>> writes = [];
  Object? writeError;

  @override
  SettingsService? get service => _service;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    if (writeError != null) throw writeError!;
    writes.add(changes);
    _service.values.addAll(changes);
  }
}

/// Today is Wednesday 2026-06-24; the plan started Monday 2026-06-01, so
/// weeks 0-2 are complete and week 3 is current. Each week plans an easy run
/// on day 3 and a long run on day 6.
final _now = DateTime(2026, 6, 24, 9);
final _start = DateTime(2026, 6, 1);

DateTime _day(int week, int d) => _start.add(Duration(days: week * 7 + d));

ActivePlanOverview _overview({String status = 'active'}) {
  final weeks = <PlanWeekRow>[];
  final workouts = <PlanWorkoutRow>[];
  for (var k = 0; k < 5; k++) {
    weeks.add(PlanWeekRow(
        id: 'w$k',
        planId: 'plan-1',
        weekIndex: k,
        phase: 'build',
        targetVolumeM: 28000));
    workouts.add(PlanWorkoutRow(
      id: 'e$k',
      weekId: 'w$k',
      scheduledDate: _day(k, 3),
      kind: 'easy',
      targetDistanceM: 8000,
      manuallyCompleted: false,
    ));
    workouts.add(PlanWorkoutRow(
      id: 'l$k',
      weekId: 'w$k',
      scheduledDate: _day(k, 6),
      kind: 'long',
      targetDistanceM: 20000,
      manuallyCompleted: k < 3,
    ));
  }
  return ActivePlanOverview(
    plan: TrainingPlanRow(
      id: 'plan-1',
      userId: 'u',
      name: 'Plan',
      goalEvent: 'distance_half',
      goalDistanceM: 21097.5,
      startDate: _start,
      endDate: _day(5, -1),
      daysPerWeek: 3,
      status: status,
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
    ),
    weeks: weeks,
    workouts: workouts,
    todayWorkout: null,
    completionPct: 0,
    currentWeekIndex: 3,
  );
}

Run _run(String id, DateTime day, double metres) => Run(
      id: id,
      startedAt: DateTime(day.year, day.month, day.day, 12),
      duration: const Duration(minutes: 60),
      distanceMetres: metres,
      source: RunSource.app,
    );

/// Weeks 0 and 1 on plan, week 2 run 36 km against 28 km: the ease-off.
final _overRuns = [
  _run('r0', _day(0, 6), 28000),
  _run('r1', _day(1, 6), 28000),
  _run('r2', _day(2, 6), 36000),
];

/// On plan every week, but runs on a rest day in weeks 0 and 1.
final _restRuns = [
  _run('r0', _day(0, 6), 20000),
  _run('r0b', _day(0, 0), 8000),
  _run('r1', _day(1, 6), 20000),
  _run('r1b', _day(1, 1), 8000),
  _run('r2', _day(2, 6), 20000),
  _run('r2b', _day(2, 3), 8000),
];

Future<List<PlanNudge>> _pump(
  WidgetTester tester, {
  required ActivePlanOverview overview,
  required List<Run> runs,
  required _FakeSettingsSync sync,
}) async {
  final reviewed = <PlanNudge>[];
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: PlanNudgeCard(
        overview: overview,
        runs: runs,
        settingsSync: sync,
        now: _now,
        onReview: reviewed.add,
      ),
    ),
  ));
  await tester.pump();
  return reviewed;
}

void main() {
  testWidgets('a week well over plan shows the ease-off card with Review',
      (tester) async {
    final sync = _FakeSettingsSync(_FakeSettingsService({}));
    await _pump(tester, overview: _overview(), runs: _overRuns, sync: sync);
    expect(find.text('A big week'), findsOneWidget);
    expect(
        find.text(
            "You ran well over plan last week. Easing next week's shorter runs helps your body absorb it."),
        findsOneWidget);
    expect(find.byKey(const Key('planNudgeReview')), findsOneWidget);
    expect(find.byKey(const Key('planNudgeDismiss')), findsOneWidget);
  });

  testWidgets('the rest-day note names the weeks and offers no Review',
      (tester) async {
    final sync = _FakeSettingsSync(_FakeSettingsService({}));
    await _pump(tester, overview: _overview(), runs: _restRuns, sync: sync);
    expect(find.text('Running on rest days'), findsOneWidget);
    expect(
        find.textContaining("You've run on rest days in 2 of the last 3 weeks."),
        findsOneWidget);
    expect(find.byKey(const Key('planNudgeReview')), findsNothing);
  });

  testWidgets('an occurrence already in the prefs bag shows nothing',
      (tester) async {
    final sync = _FakeSettingsSync(_FakeSettingsService({
      dismissedNudgesKey: ['plan-1:ease_over:2'],
    }));
    await _pump(tester, overview: _overview(), runs: _overRuns, sync: sync);
    expect(find.byKey(const Key('planNudgeCard')), findsNothing);
    expect(
        PlanNudgeCard.nudgeFor(
          overview: _overview(),
          runs: _overRuns,
          dismissed: PlanNudgeCard.dismissedIn(sync),
          now: _now,
        ),
        isNull);
  });

  testWidgets('a paused plan shows nothing', (tester) async {
    final sync = _FakeSettingsSync(_FakeSettingsService({}));
    await _pump(tester,
        overview: _overview(status: 'paused'), runs: _overRuns, sync: sync);
    expect(find.byKey(const Key('planNudgeCard')), findsNothing);
  });

  testWidgets('Dismiss files the occurrence and hides the card',
      (tester) async {
    final sync = _FakeSettingsSync(_FakeSettingsService({}));
    await _pump(tester, overview: _overview(), runs: _overRuns, sync: sync);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('planNudgeDismiss')));
    });
    await pumpUntil(tester, () => sync.writes.isNotEmpty,
        describe: 'the dismissal to reach the prefs bag');
    await tester.pump();
    expect(sync.writes.single, {
      dismissedNudgesKey: ['plan-1:ease_over:2'],
    });
    expect(find.byKey(const Key('planNudgeCard')), findsNothing);
  });

  testWidgets('a refused dismissal keeps the card and says so',
      (tester) async {
    final sync = _FakeSettingsSync(_FakeSettingsService({}))
      ..writeError = Exception('permission denied');
    await _pump(tester, overview: _overview(), runs: _overRuns, sync: sync);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('planNudgeDismiss')));
    });
    await pumpUntil(
        tester,
        () => tester
            .any(find.text("Couldn't hide that suggestion. Try again.")),
        describe: 'the refusal banner');
    expect(find.text('A big week'), findsOneWidget);
    expect(sync.writes, isEmpty);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('Review hands the occurrence to the host and files it',
      (tester) async {
    final sync = _FakeSettingsSync(_FakeSettingsService({}));
    final reviewed =
        await _pump(tester, overview: _overview(), runs: _overRuns, sync: sync);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('planNudgeReview')));
    });
    await pumpUntil(tester, () => sync.writes.isNotEmpty,
        describe: 'the reviewed occurrence to be filed');
    expect(reviewed.single.kind, PlanNudgeKind.easeOver);
    expect(reviewed.single.key, 'plan-1:ease_over:2');
    expect(sync.writes.single[dismissedNudgesKey], ['plan-1:ease_over:2']);
  });
}
