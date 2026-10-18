// Plan detail's "Restart plan…" (issue #1186, decisions § 2121): the
// owner-only menu entry, the confirm that names the copy's dates, opening the
// copy on success, and the refusals.

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

const _owner = 'owner-uuid';
final DateTime _today = DateTime(2026, 3, 11);

TrainingPlanRow _plan(String id, String status) => TrainingPlanRow(
      id: id,
      userId: _owner,
      name: id == 'plan-1' ? 'Spring Half' : 'Spring Half again',
      goalEvent: 'distance_half',
      goalDistanceM: 21097.5,
      goalTimeSeconds: 7200,
      startDate: DateTime(2026, 3, 9),
      endDate: DateTime(2026, 3, 22),
      daysPerWeek: 4,
      status: status,
      source: 'generated',
      rules: const [],
      isTemplate: false,
      isPublicTemplate: false,
    );

class _FakeTraining extends TrainingService {
  final String status;
  final DateTime raceDate;
  final Object? restartError;
  final restartCalls = <(String, String)>[];
  final fetched = <String>[];

  _FakeTraining({
    this.status = 'active',
    DateTime? raceDate,
    this.restartError,
  }) : raceDate = raceDate ?? DateTime(2026, 3, 10);

  @override
  Future<
    ({
      TrainingPlanRow? plan,
      List<PlanWeekRow> weeks,
      List<PlanWorkoutRow> workouts,
    })
  >
  fetchPlan(String id) async {
    fetched.add(id);
    return (
      plan: _plan(id, id == 'plan-1' ? status : 'active'),
      weeks: const [
        PlanWeekRow(id: 'w1', planId: 'plan-1', weekIndex: 0, phase: 'base'),
        PlanWeekRow(id: 'w2', planId: 'plan-1', weekIndex: 1, phase: 'race'),
      ],
      workouts: [
        PlanWorkoutRow(
          id: 'wo-race',
          weekId: 'w1',
          scheduledDate: raceDate,
          kind: 'race',
          targetDistanceM: 5000,
          manuallyCompleted: false,
        ),
        PlanWorkoutRow(
          id: 'wo-long',
          weekId: 'w2',
          scheduledDate: DateTime(2026, 3, 22),
          kind: 'long',
          targetDistanceM: 16000,
          manuallyCompleted: false,
        ),
      ],
    );
  }

  @override
  Future<List<TrainingPlanRow>> fetchMyPublishedPlans() async => const [];

  @override
  Future<String> restartPlan(String planId, String startIso) async {
    restartCalls.add((planId, startIso));
    final e = restartError;
    if (e != null) throw e;
    return 'plan-2';
  }
}

class _FakeSocial extends SocialService {
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async =>
      const [];
}

Future<void> _pump(WidgetTester tester, _FakeTraining training,
    {String viewerId = _owner}) async {
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
                viewerIdOverride: viewerId,
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

Future<void> _openRestart(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('planDetailMenu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Restart plan…'));
  await tester.pumpAndSettle();
}

Future<void> _drainBanner(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 4));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the owner menu offers Restart plan…', (tester) async {
    await _pump(tester, _FakeTraining());
    await tester.tap(find.byKey(const Key('planDetailMenu')));
    await tester.pumpAndSettle();
    expect(find.text('Restart plan…'), findsOneWidget);
  });

  testWidgets('another viewer has no menu to restart from', (tester) async {
    await _pump(tester, _FakeTraining(), viewerId: 'someone-else');
    expect(find.byKey(const Key('planDetailMenu')), findsNothing);
  });

  testWidgets('the confirm names the copy dates and what is retired',
      (tester) async {
    final training = _FakeTraining();
    await _pump(tester, training);
    await _openRestart(tester);

    final message = tester
        .widget<Text>(find.byKey(const Key('planDetailRestartMessage')))
        .data!;
    expect(message, contains('starts on Mar 23'));
    expect(message, contains('ends on Apr 5'));
    expect(message,
        contains('This plan, and any active plan those dates overlap, is retired as abandoned'));
    expect(message, contains('Race day moves to Mar 24.'));

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(training.restartCalls, isEmpty, reason: 'nothing before the confirm');
  });

  testWidgets('a completed plan says it keeps its history', (tester) async {
    await _pump(tester, _FakeTraining(status: 'completed'));
    await _openRestart(tester);
    final message = tester
        .widget<Text>(find.byKey(const Key('planDetailRestartMessage')))
        .data!;
    expect(message, contains('This plan keeps its weeks, workouts and run links.'));
  });

  testWidgets('confirming restarts on the default date and opens the copy',
      (tester) async {
    final training = _FakeTraining();
    await _pump(tester, training);
    await _openRestart(tester);
    await tester.tap(find.byKey(const Key('planDetailRestartConfirm')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => training.fetched.contains('plan-2'),
        describe: 'the copy to load');
    await tester.pumpAndSettle();

    expect(training.restartCalls, [('plan-1', '2026-03-23')]);
    expect(find.text('Plan restarted. This is your new copy.'), findsOneWidget);
    expect(find.text('Spring Half again'), findsWidgets);
    await _drainBanner(tester);
  });

  testWidgets('a failed restart stays on the plan and says so', (tester) async {
    final training = _FakeTraining(restartError: Exception('boom'));
    await _pump(tester, training);
    await _openRestart(tester);
    await tester.tap(find.byKey(const Key('planDetailRestartConfirm')));
    await tester.pumpAndSettle();

    expect(training.restartCalls, hasLength(1));
    expect(find.textContaining("Couldn't update the plan"), findsOneWidget);
    expect(training.fetched, isNot(contains('plan-2')));
    expect(find.text('Spring Half'), findsWidgets);
    await _drainBanner(tester);
  });

  testWidgets('the server refusing over a race ahead names the reason',
      (tester) async {
    final training =
        _FakeTraining(restartError: const PlanRestartRaceAheadError());
    await _pump(tester, training);
    await _openRestart(tester);
    await tester.tap(find.byKey(const Key('planDetailRestartConfirm')));
    await tester.pumpAndSettle();

    expect(find.text("This plan has a race still ahead, so it can't be restarted."),
        findsOneWidget);
    await _drainBanner(tester);
  });

  testWidgets('a plan whose race is still ahead is not offered a confirm',
      (tester) async {
    final training = _FakeTraining(raceDate: DateTime(2026, 3, 14));
    await _pump(tester, training);
    await _openRestart(tester);

    expect(find.textContaining('is still ahead'), findsOneWidget);
    expect(find.byKey(const Key('planDetailRestartConfirm')), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(training.restartCalls, isEmpty);
  });
}
