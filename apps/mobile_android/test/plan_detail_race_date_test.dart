// Plan detail's "Change race date…" (issue #1186, decisions § 2120): the
// owner's app-bar entry, the date picker, the confirm that says what changes,
// the refusal of a day too close for the taper, and the overlap error.

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_race_date.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

const _owner = 'owner-uuid';
final DateTime _today = DateTime(2026, 3, 11);
final DateTime _start = DateTime(2026, 2, 22);
const _phases = ['base', 'base', 'build', 'build', 'build', 'peak', 'taper', 'race'];

class _FakeTraining extends TrainingService {
  final bool walkRun;
  final Object? changeError;
  final changeCalls = <(RaceDateChange, String)>[];

  _FakeTraining({this.walkRun = false, this.changeError});

  @override
  Future<
    ({
      TrainingPlanRow? plan,
      List<PlanWeekRow> weeks,
      List<PlanWorkoutRow> workouts,
    })
  >
  fetchPlan(String id) async => (
        plan: TrainingPlanRow(
          id: 'plan-1',
          userId: _owner,
          name: 'Spring Half',
          goalEvent: 'distance_half',
          goalDistanceM: 21097.5,
          startDate: _start,
          endDate: _start.add(const Duration(days: 55)),
          daysPerWeek: 4,
          status: 'active',
          source: 'generated',
          rules: const [],
          isTemplate: false,
          isPublicTemplate: false,
        ),
        weeks: [
          for (var i = 0; i < _phases.length; i++)
            PlanWeekRow(
                id: 'w$i',
                planId: 'plan-1',
                weekIndex: i,
                phase: walkRun && i == 7 ? 'graduation' : _phases[i]),
        ],
        workouts: [
          for (var i = 0; i < _phases.length; i++)
            PlanWorkoutRow(
              id: i == 7 ? 'race' : 'long$i',
              weekId: 'w$i',
              scheduledDate: _start.add(Duration(days: 7 * i)),
              kind: i == 7 && !walkRun ? 'race' : 'long',
              targetDistanceM: 14000,
              manuallyCompleted: false,
            ),
        ],
      );

  @override
  Future<List<TrainingPlanRow>> fetchMyPublishedPlans() async => const [];

  @override
  Future<void> changePlanRaceDate(
      String planId, RaceDateChange change, String todayIso) async {
    changeCalls.add((change, todayIso));
    if (changeError != null) throw changeError!;
  }
}

class _FakeSocial extends SocialService {
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async =>
      const [];
}

Future<void> _pump(WidgetTester tester, _FakeTraining training) async {
  tester.view.physicalSize = const Size(420, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => PlanDetailScreen(
                training: training,
                planId: 'plan-1',
                social: _FakeSocial(),
                viewerIdOverride: _owner,
                now: () => _today,
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await pumpUntil(
    tester,
    () => !tester.any(find.byType(FullBodyLoader)),
    describe: 'the plan fetch to settle',
  );
  await tester.pump();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('planDetailMenu')));
  await tester.pumpAndSettle();
}

/// Opens "Change race date…" and types [mmddyyyy] into the picker's input mode.
Future<void> _pickRaceDate(WidgetTester tester, String mmddyyyy) async {
  await _openMenu(tester);
  await tester.tap(find.byKey(const Key('planDetailChangeRaceDate')));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Switch to input'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, mmddyyyy);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _drainBanner(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 4));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the owner of a race plan gets the entry', (tester) async {
    await _pump(tester, _FakeTraining());
    await _openMenu(tester);
    expect(find.text('Change race date…'), findsOneWidget);
  });

  testWidgets('a plan without a race does not offer it', (tester) async {
    await _pump(tester, _FakeTraining(walkRun: true));
    await _openMenu(tester);
    expect(find.text('Shift dates…'), findsOneWidget);
    expect(find.text('Change race date…'), findsNothing);
  });

  testWidgets('a later race confirms the added build weeks, then applies',
      (tester) async {
    final training = _FakeTraining();
    await _pump(tester, training);

    await _pickRaceDate(tester, '04/26/2026');
    expect(find.text('Change race date?'), findsOneWidget);
    expect(find.textContaining('2 build weeks are added before the taper'),
        findsOneWidget);
    expect(training.changeCalls, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Change race date'));
    await tester.pumpAndSettle();
    expect(training.changeCalls, hasLength(1));
    final (change, todayIso) = training.changeCalls.single;
    expect(todayIso, '2026-03-11');
    expect(change.raceDateIso, '2026-04-26');
    expect(change.insertAt, 5);
    expect(change.insertCount, 2);
    expect(change.repeatWeekId, 'w4');
    expect(change.raceWorkoutId, 'race');
    expect(find.textContaining('Race date changed to'), findsOneWidget);
    await _drainBanner(tester);
  });

  testWidgets('cancelling the confirm changes nothing', (tester) async {
    final training = _FakeTraining();
    await _pump(tester, training);

    await _pickRaceDate(tester, '04/26/2026');
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(training.changeCalls, isEmpty);
  });

  testWidgets('a day too close for the taper is refused before any confirm',
      (tester) async {
    final training = _FakeTraining();
    await _pump(tester, training);

    await _pickRaceDate(tester, '03/15/2026');
    expect(find.text('Change race date?'), findsNothing);
    expect(find.textContaining('too soon to keep your taper'), findsOneWidget);
    expect(training.changeCalls, isEmpty);
    await _drainBanner(tester);
  });

  testWidgets('a later race that runs into another plan says so',
      (tester) async {
    final training =
        _FakeTraining(changeError: const ActivePlanExistsError());
    await _pump(tester, training);

    await _pickRaceDate(tester, '04/26/2026');
    await tester.tap(find.widgetWithText(TextButton, 'Change race date'));
    await tester.pumpAndSettle();
    expect(training.changeCalls, hasLength(1));
    expect(find.textContaining('runs into another active plan'), findsOneWidget);
    await _drainBanner(tester);
  });
}
