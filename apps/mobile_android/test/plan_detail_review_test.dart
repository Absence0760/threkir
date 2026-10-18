import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

/// Home's plan card lands on the plan with `openReview` (decisions § 2125):
/// the plan's own preview opens as if picked from Adjust plan. And a done
/// workout run long carries "+3 km" in the week rows and the today card
/// (decisions § 2126).

const _uid = 'owner-uuid';

/// Wednesday 2026-06-24; the plan started Monday 2026-06-01, so weeks 0-2
/// are complete and week 3 is current.
final _now = DateTime(2026, 6, 24, 9);
final _start = DateTime(2026, 6, 1);
DateTime _day(int week, int d) => _start.add(Duration(days: week * 7 + d));

class _FakeTraining extends TrainingService {
  final TrainingPlanRow plan;
  final List<PlanWeekRow> weeks;
  final List<PlanWorkoutRow> workouts;
  final Map<String, double> distances;
  final bool distancesFail;
  final Map<String, double> updated = {};

  _FakeTraining(this.plan, this.weeks, this.workouts,
      {this.distances = const {}, this.distancesFail = false});

  @override
  Future<
      ({
        TrainingPlanRow? plan,
        List<PlanWeekRow> weeks,
        List<PlanWorkoutRow> workouts
      })> fetchPlan(String id) async =>
      (plan: plan, weeks: weeks, workouts: workouts);

  @override
  Future<Map<String, double>> fetchRunDistances(List<String> ids) async {
    if (distancesFail) throw Exception('runs read refused');
    return {for (final id in ids) if (distances[id] != null) id: distances[id]!};
  }

  @override
  Future<void> applyReplan({
    required String planId,
    required Map<String, double> distances,
  }) async =>
      updated.addAll(distances);
}

class _FakeSocial extends SocialService {
  final List<RecentRunRow> runs;
  _FakeSocial(this.runs);
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async => runs;
}

TrainingPlanRow _plan({String status = 'active'}) => TrainingPlanRow(
      id: 'plan-1',
      userId: _uid,
      name: 'Review Plan',
      goalEvent: 'distance_half',
      goalDistanceM: 21097.5,
      startDate: _start,
      endDate: _day(5, -1),
      daysPerWeek: 3,
      status: status,
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
    );

/// Five weeks of an easy run on day 3 and a long run on day 6.
_FakeTraining _training({
  List<double> volumes = const [28000, 28000, 28000, 28000, 28000],
  double firstLongM = 20000,
  double laterLongM = 20000,
  bool longsDone = true,
  String status = 'active',
  PlanWorkoutRow? today,
  Map<String, double> distances = const {},
  bool distancesFail = false,
}) {
  final weeks = <PlanWeekRow>[];
  final workouts = <PlanWorkoutRow>[];
  for (var k = 0; k < 5; k++) {
    weeks.add(PlanWeekRow(
        id: 'w$k',
        planId: 'plan-1',
        weekIndex: k,
        phase: 'build',
        targetVolumeM: volumes[k]));
    workouts.add(PlanWorkoutRow(
      id: 'easy$k',
      weekId: 'w$k',
      scheduledDate: _day(k, 3),
      kind: 'easy',
      targetDistanceM: 8000,
      manuallyCompleted: false,
    ));
    workouts.add(PlanWorkoutRow(
      id: 'long$k',
      weekId: 'w$k',
      scheduledDate: _day(k, 6),
      kind: 'long',
      targetDistanceM: k == 0 ? firstLongM : (k >= 3 ? laterLongM : 20000),
      manuallyCompleted: longsDone && k < 3 && k > 0,
    ));
  }
  if (today != null) workouts.add(today);
  return _FakeTraining(_plan(status: status), weeks, workouts,
      distances: distances, distancesFail: distancesFail);
}

RecentRunRow _run(String id, DateTime day, double metres) => RecentRunRow(
      id: id,
      startedAt: DateTime(day.year, day.month, day.day, 12),
      durationS: 3600,
      distanceM: metres,
      activityType: 'run',
    );

Future<void> _pump(
  WidgetTester tester, {
  required _FakeTraining training,
  List<RecentRunRow> runs = const [],
  PlanReview? openReview,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: PlanDetailScreen(
      training: training,
      planId: 'plan-1',
      social: _FakeSocial(runs),
      viewerIdOverride: _uid,
      now: () => _now,
      openReview: openReview,
    ),
  ));
  await pumpUntil(tester, () => !tester.any(find.byType(FullBodyLoader)),
      describe: 'the plan fetch to replace the full-body loader');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('openReview: replan opens the ease-off preview and applies it',
      (tester) async {
    final training = _training(longsDone: true);
    await _pump(tester,
        training: training,
        openReview: PlanReview.replan,
        runs: [
          _run('r0', _day(0, 6), 28000),
          _run('r1', _day(1, 6), 28000),
          _run('r2', _day(2, 6), 36000),
        ]);
    await pumpUntil(tester, () => tester.any(find.text('Proposed changes')),
        describe: 'the re-plan preview to open');
    expect(
        find.text('8.0 km → 6.8 km — ease off after over-running',
            skipOffstage: false),
        findsOneWidget);
    final apply = find.text('Apply changes');
    await tester.ensureVisible(apply);
    await tester.pump();
    await tester.tap(apply);
    await pumpUntil(tester, () => training.updated.isNotEmpty,
        describe: 'the eased week to be written');
    expect(training.updated, {'easy3': 6800});
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('openReview: adaptive opens the trend-badged preview',
      (tester) async {
    final training = _training(
      volumes: const [40000, 40000, 28000, 40000, 40000],
      firstLongM: 26000,
      laterLongM: 22000,
    );
    await _pump(tester,
        training: training,
        openReview: PlanReview.adaptive,
        runs: [
          _run('a', _day(1, 3), 8000),
          _run('b', _day(1, 6), 20000),
          _run('c', _day(2, 3), 8000),
          _run('d', _day(2, 6), 20000),
        ]);
    await pumpUntil(tester, () => tester.any(find.text('Proposed changes')),
        describe: 'the adaptive preview to open');
    expect(
        find.textContaining('under your plan for multiple weeks',
            skipOffstage: false),
        findsOneWidget);
    expect(training.updated, isEmpty);
  });

  testWidgets('openReview does nothing on a paused plan', (tester) async {
    final training = _training(status: 'paused');
    await _pump(tester,
        training: training,
        openReview: PlanReview.replan,
        runs: [
          _run('r0', _day(0, 6), 28000),
          _run('r1', _day(1, 6), 28000),
          _run('r2', _day(2, 6), 36000),
        ]);
    expect(find.text('Proposed changes', skipOffstage: false), findsNothing);
  });

  testWidgets('a done workout run 3 km long shows +3 km on its row and today',
      (tester) async {
    final today = PlanWorkoutRow(
      id: 'today',
      weekId: 'w3',
      scheduledDate: _day(3, 2),
      kind: 'tempo',
      targetDistanceM: 10000,
      completedRunId: 'run-today',
      manuallyCompleted: false,
    );
    final training =
        _training(today: today, distances: {'run-today': 13000});
    await _pump(tester, training: training);
    await pumpUntil(
        tester,
        () => tester
            .any(find.text('DONE TODAY · +3 km', skipOffstage: false)),
        describe: 'the linked run distance to reach the today card');
    final row = find.byKey(const ValueKey('planDetailOverrun-today'));
    await tester.scrollUntilVisible(row, 300,
        scrollable: find.byType(Scrollable).first);
    expect(row, findsOneWidget);
    expect(tester.widget<Text>(row).data, '+3 km');
    expect(
        find.bySemanticsLabel(
            RegExp(r'Tempo.*, 3 km more than planned$')),
        findsOneWidget);
  });

  testWidgets('a refused run read leaves the plain status', (tester) async {
    final today = PlanWorkoutRow(
      id: 'today',
      weekId: 'w3',
      scheduledDate: _day(3, 2),
      kind: 'tempo',
      targetDistanceM: 10000,
      completedRunId: 'run-today',
      manuallyCompleted: false,
    );
    final training = _training(
        today: today, distances: {'run-today': 13000}, distancesFail: true);
    await _pump(tester, training: training);
    expect(find.text('DONE TODAY', skipOffstage: false), findsOneWidget);
    expect(
        find.byKey(const ValueKey('planDetailOverrun-today'),
            skipOffstage: false),
        findsNothing);
  });
}
