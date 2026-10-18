import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_recap.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/plan_recap_card.dart';
import 'pump_until.dart';

// The end-of-plan recap on mobile plan detail (issue #1186): a completed plan
// recaps its block and offers the next plan; an active plan shows no recap.

const _owner = 'owner-uuid';
final DateTime _now = DateTime(2026, 4, 27, 9);

TrainingPlanRow _plan({String status = 'completed', DateTime? trimmedAt}) =>
    TrainingPlanRow(
      id: 'plan-1',
      userId: _owner,
      name: 'Spring Half',
      goalEvent: 'distance_half',
      goalDistanceM: 21097.5,
      startDate: DateTime(2026, 3, 1),
      endDate: DateTime(2026, 4, 26),
      daysPerWeek: 3,
      status: status,
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
      trimmedAt: trimmedAt,
    );

PlanWorkoutRow _wo(String id, DateTime date, String kind,
        {double? metres,
        String? runId,
        bool manual = false,
        DateTime? skippedAt,
        String? raceName}) =>
    PlanWorkoutRow(
      id: id,
      weekId: 'w1',
      scheduledDate: date,
      kind: kind,
      targetDistanceM: metres,
      completedRunId: runId,
      manuallyCompleted: manual,
      skippedAt: skippedAt,
      raceName: raceName,
    );

final _workouts = [
  _wo('l1', DateTime(2026, 3, 8), 'long', metres: 12000, manual: true),
  _wo('l2', DateTime(2026, 4, 12), 'long', metres: 18000, runId: 'r-long'),
  _wo('e1', DateTime(2026, 4, 14), 'easy', metres: 6000),
  _wo('e2', DateTime(2026, 4, 16), 'easy',
      metres: 6000, skippedAt: DateTime.utc(2026, 4, 16, 8)),
  _wo('race', DateTime(2026, 4, 26), 'race',
      metres: 21097.5, runId: 'r-race', raceName: 'Spring Half race'),
];

const _sources = (
  runs: [
    PlanRecapRun(
        id: 'r-long', date: '2026-04-12', distanceM: 19000, durationS: 6600),
    PlanRecapRun(
        id: 'r-race', date: '2026-04-26', distanceM: 21097.5, durationS: 5400),
  ],
  records: [
    PlanRecapRecord(
        distance: 'half_marathon', timeS: 5400, date: '2026-04-26'),
  ],
);

class _Training extends TrainingService {
  _Training({this.failures = 0, this.status = 'completed'});
  int failures;
  final String status;
  int calls = 0;

  @override
  Future<({List<PlanRecapRun> runs, List<PlanRecapRecord> records})>
      fetchPlanRecapSources(String startIso, String endIso) async {
    calls += 1;
    if (failures > 0) {
      failures -= 1;
      throw Exception('offline');
    }
    return _sources;
  }

  @override
  Future<
      ({
        TrainingPlanRow? plan,
        List<PlanWeekRow> weeks,
        List<PlanWorkoutRow> workouts,
      })> fetchPlan(String id) async => (
        plan: _plan(status: status),
        weeks: const [
          PlanWeekRow(
              id: 'w1',
              planId: 'plan-1',
              weekIndex: 0,
              phase: 'race',
              targetVolumeM: 40000),
        ],
        workouts: _workouts,
      );

  @override
  Future<List<TrainingPlanRow>> fetchMyPublishedPlans() async => const [];

  @override
  Future<bool> isActiveCoachOf(String athleteId) async => false;
}

class _Social extends SocialService {
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async =>
      const [];
}

Future<void> _pumpCard(
  WidgetTester tester,
  _Training training, {
  TrainingPlanRow? plan,
  List<PlanWorkoutRow>? workouts,
  void Function(String startIso, int? seed)? onBuildNext,
}) async {
  tester.view.physicalSize = const Size(420, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: PlanRecapCard(
          training: training,
          plan: plan ?? _plan(),
          workouts: workouts ?? _workouts,
          now: _now,
          onBuildNext: onBuildNext ?? (_, __) {},
        ),
      ),
    ),
  ));
  await tester.pump();
}

String _texts(WidgetTester tester, Key key) => tester
    .widgetList<Text>(
        find.descendant(of: find.byKey(key), matching: find.byType(Text)))
    .map((t) => t.data)
    .join(' | ');

void main() {
  setUpAll(() => initializeDateFormatting());

  test('shows only for a completed plan that is not a template', () {
    expect(PlanRecapCard.shows(status: 'completed', isTemplate: false), isTrue);
    expect(PlanRecapCard.shows(status: 'active', isTemplate: false), isFalse);
    expect(PlanRecapCard.shows(status: 'abandoned', isTemplate: false), isFalse);
    expect(PlanRecapCard.shows(status: 'completed', isTemplate: true), isFalse);
  });

  testWidgets('a completed plan recaps its block and seeds the next plan',
      (tester) async {
    String? start;
    int? seed;
    await _pumpCard(tester, _Training(), onBuildNext: (s, k) {
      start = s;
      seed = k;
    });
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.planRecapTitle('Spring Half')), findsOneWidget);

    final sessions = _texts(tester, const Key('planRecapSessions'));
    expect(sessions, contains('3 of 4'));
    expect(sessions, contains('75% done'));
    expect(sessions, contains('1 missed'));
    expect(sessions, contains('1 skipped'));
    final longRuns = _texts(tester, const Key('planRecapLongRuns'));
    expect(longRuns, contains('2 of 2'));
    expect(longRuns, contains('From 12.0 km up to 19.0 km'));
    final race = _texts(tester, const Key('planRecapRace'));
    expect(race, contains('Spring Half race'));
    expect(race, contains('1:30:00'));
    expect(race, contains('VDOT 51.0'));
    expect(find.text('Half marathon  1:30:00'), findsOneWidget);
    expect(find.byKey(const Key('planRecapRecovery')), findsOneWidget);

    await tester.tap(find.byKey(const Key('planRecapNextPlan')));
    expect(start, '2026-05-10');
    expect(seed, fiveKSecondsAtVdot(51));
  });

  testWidgets('an empty plan recaps to zeros with no long runs, race or records',
      (tester) async {
    final training = _Training();
    String? start;
    await _pumpCard(
      tester,
      training,
      plan: _plan(trimmedAt: DateTime.utc(2026, 3, 2, 10)),
      workouts: const [],
      onBuildNext: (s, _) => start = s,
    );
    expect(_texts(tester, const Key('planRecapSessions')), contains('0 of 0'));
    expect(find.byKey(const Key('planRecapLongRuns')), findsNothing);
    expect(find.byKey(const Key('planRecapRace')), findsNothing);
    expect(find.byKey(const Key('planRecapRecovery')), findsNothing);
    await tester.tap(find.byKey(const Key('planRecapNextPlan')));
    expect(start, '2026-05-10');
  });

  testWidgets('a failed load says so, and Try again recovers', (tester) async {
    final training = _Training(failures: 1);
    await _pumpCard(tester, training);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.planRecapLoadFailed), findsOneWidget);
    expect(find.byKey(const Key('planRecapSessions')), findsNothing);

    await tester.tap(find.byKey(const Key('planRecapRetry')));
    await tester.pump();
    expect(training.calls, 2);
    expect(find.text(l10n.planRecapLoadFailed), findsNothing);
    expect(find.byKey(const Key('planRecapSessions')), findsOneWidget);
  });

  Future<void> pumpDetail(WidgetTester tester, String status) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(420, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanDetailScreen(
        training: _Training(status: status),
        planId: 'plan-1',
        social: _Social(),
        viewerIdOverride: _owner,
        now: () => _now,
      ),
    ));
    await pumpUntil(
      tester,
      () => !tester.any(find.byType(FullBodyLoader)),
      describe: 'the plan fetch to replace the full-body loader',
    );
    await tester.pump();
  }

  testWidgets('plan detail shows the recap on a completed plan',
      (tester) async {
    await pumpDetail(tester, 'completed');
    expect(find.byType(PlanRecapCard), findsOneWidget);
    expect(find.byKey(const Key('planDetailFinishPlan')), findsNothing);
  });

  testWidgets('plan detail shows no recap on an active plan, only Finish plan',
      (tester) async {
    await pumpDetail(tester, 'active');
    expect(find.byType(PlanRecapCard), findsNothing);
    expect(find.byKey(const Key('planDetailFinishPlan')), findsOneWidget);
  });
}
