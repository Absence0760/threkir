import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

// The plan_workouts update policies admit the owner and an athlete's active
// coach on a non-template plan. The pencil and the long-press used to open
// the edit sheet for anyone who could read the plan, including a library
// or template viewer whose save RLS then refused.

const _owner = 'owner-uuid';
const _viewer = 'viewer-uuid';
final DateTime _today = DateTime(2026, 3, 11);

class _GateTraining extends TrainingService {
  final bool template;
  final bool coaches;
  final List<String> coachLookups = [];
  _GateTraining({this.template = false, this.coaches = false});

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
      startDate: _today,
      endDate: _today.add(const Duration(days: 6)),
      daysPerWeek: 4,
      status: 'active',
      source: 'generated',
      isTemplate: template,
      isPublicTemplate: template,
    ),
    weeks: const [
      PlanWeekRow(
        id: 'w1',
        planId: 'plan-1',
        weekIndex: 0,
        phase: 'base',
        targetVolumeM: 30000,
      ),
    ],
    workouts: [
      PlanWorkoutRow(
        id: 'wo-tempo',
        weekId: 'w1',
        scheduledDate: _today.add(const Duration(days: 1)),
        kind: 'tempo',
        targetDistanceM: 8000,
        manuallyCompleted: false,
      ),
    ],
  );

  @override
  Future<List<TrainingPlanRow>> fetchMyPublishedPlans() async => const [];

  @override
  Future<bool> isActiveCoachOf(String athleteId) async {
    coachLookups.add(athleteId);
    return coaches;
  }
}

class _FakeSocial extends SocialService {
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async =>
      const [];
}

Future<void> _pump(WidgetTester tester, _GateTraining training,
    {required String viewerId}) async {
  tester.view.physicalSize = const Size(420, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanDetailScreen(
        training: training,
        planId: 'plan-1',
        social: _FakeSocial(),
        viewerIdOverride: viewerId,
        now: () => _today,
      ),
    ),
  );
  await pumpUntil(
    tester,
    () => !tester.any(find.byType(FullBodyLoader)),
    describe: 'the plan fetch to replace the full-body loader',
  );
  await tester.pump();
}

Finder get _pencil => find.byTooltip('Edit workout');

void main() {
  testWidgets('the owner gets the pencil', (tester) async {
    await _pump(tester, _GateTraining(), viewerId: _owner);
    expect(_pencil, findsWidgets);
  });

  testWidgets('a stranger on a template gets no pencil and no long-press',
      (tester) async {
    final training = _GateTraining(template: true, coaches: true);
    await _pump(tester, training, viewerId: _viewer);
    expect(_pencil, findsNothing);
    // A template has no coach path, so the lookup is not even made.
    expect(training.coachLookups, isEmpty);

    final row = find.ancestor(
      of: find.text('Tempo').last,
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(row.first).onLongPress, isNull);
  });

  testWidgets('a reader who does not coach the owner gets no pencil',
      (tester) async {
    final training = _GateTraining();
    await _pump(tester, training, viewerId: _viewer);
    expect(training.coachLookups, [_owner]);
    expect(_pencil, findsNothing);
  });

  testWidgets("the athlete's active coach gets the pencil", (tester) async {
    final training = _GateTraining(coaches: true);
    await _pump(tester, training, viewerId: _viewer);
    await tester.pump();
    expect(_pencil, findsWidgets);
  });
}
