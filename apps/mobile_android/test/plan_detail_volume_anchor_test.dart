import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_resume.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

/// The comeback ramp on the plan screen (decisions § 2090, § 2207). With
/// `ADAPTIVE_FITNESS_GATE` on, a week well under plan makes "Re-plan remaining
/// weeks" build the weeks ahead back from what was run, and the preview says
/// so; with it off, the same plan reads as on track, as it always has. The rules are
/// pinned in plan_volume_anchor_test.

const _uid = 'owner-uuid';

DateTime _mondayThisWeek() {
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

class _FakeTraining extends TrainingService {
  final TrainingPlanRow Function(String status) planWith;
  final List<PlanWeekRow> weeks;
  final List<PlanWorkoutRow> workouts;
  String status;
  _FakeTraining(this.planWith, this.weeks, this.workouts, this.status);

  @override
  Future<
    ({
      TrainingPlanRow? plan,
      List<PlanWeekRow> weeks,
      List<PlanWorkoutRow> workouts,
    })
  >
  fetchPlan(String id) async {
    return (plan: planWith(status), weeks: weeks, workouts: workouts);
  }

  @override
  Future<void> resumePlan(String id, {ResumeShift? shift}) async {
    status = 'active';
  }
}

class _FakeSocial extends SocialService {
  final List<RecentRunRow> runs;
  _FakeSocial(this.runs);
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async => runs;
}

/// Weeks 0-2 complete, week 3 this week with nothing planned, week 4 next
/// week with an 8 km easy run and a 20 km long run. Weeks 0 and 1 ran 28 km
/// as planned; week 2 ran 10 km and missed its long run.
({_FakeTraining training, _FakeSocial social}) _shortWeekPlan({
  String status = 'active',
}) {
  final start = _mondayThisWeek().subtract(const Duration(days: 21));
  DateTime day(int week, int d) => start.add(Duration(days: week * 7 + d));
  final weeks = [
    for (var k = 0; k < 5; k++)
      PlanWeekRow(
        id: 'w$k',
        planId: 'plan-1',
        weekIndex: k,
        phase: 'build',
        targetVolumeM: 28000,
      ),
  ];
  final workouts = <PlanWorkoutRow>[
    for (final k in [0, 1, 2, 4]) ...[
      PlanWorkoutRow(
        id: 'easy$k',
        weekId: 'w$k',
        scheduledDate: day(k, 3),
        kind: 'easy',
        targetDistanceM: 8000,
        manuallyCompleted: k < 2,
      ),
      PlanWorkoutRow(
        id: 'long$k',
        weekId: 'w$k',
        scheduledDate: day(k, 6),
        kind: 'long',
        targetDistanceM: 20000,
        manuallyCompleted: k < 2,
      ),
    ],
  ];
  RecentRunRow run(String id, DateTime d, double m) => RecentRunRow(
    id: id,
    startedAt: DateTime(d.year, d.month, d.day, 12),
    durationS: (m * 0.33).round(),
    distanceM: m,
    activityType: 'run',
  );
  TrainingPlanRow planWith(String status) => TrainingPlanRow(
    id: 'plan-1',
    userId: _uid,
    name: 'Test Plan',
    goalEvent: 'distance_half',
    goalDistanceM: 21097.5,
    startDate: start,
    endDate: day(5, -1),
    daysPerWeek: 3,
    status: status,
    source: 'generated',
    isTemplate: false,
    isPublicTemplate: false,
  );
  return (
    training: _FakeTraining(planWith, weeks, workouts, status),
    social: _FakeSocial([
      run('r0', day(0, 6), 28000),
      run('r1', day(1, 6), 28000),
      run('r2', day(2, 5), 10000),
    ]),
  );
}

Future<void> _pump(WidgetTester tester, {String status = 'active'}) async {
  final p = _shortWeekPlan(status: status);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanDetailScreen(
        training: p.training,
        planId: 'plan-1',
        social: p.social,
        viewerIdOverride: _uid,
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

/// Route transitions only: a shown top banner leaves a pending timer, and
/// `pumpAndSettle` would never settle on it.
Future<void> _adjust(WidgetTester tester, String label) async {
  await tester.tap(find.text('Adjust plan'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  final option = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text('Re-plan remaining weeks'),
  );
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  tearDown(dotenv.clean);

  testWidgets(
    'gate on: a short week builds the weeks ahead back from what was run',
    (tester) async {
      dotenv.loadFromString(envString: 'ADAPTIVE_FITNESS_GATE=true');
      await _pump(tester);
      await _adjust(tester, 'Re-plan remaining weeks');

      expect(find.text('Proposed changes'), findsOneWidget);
      final note = find.byKey(const Key('planDetailReplanAnchorNote'));
      expect(note, findsOneWidget);
      expect(
        tester.widget<Text>(note).data,
        contains('Your last week of running came in at 10'),
      );
      // Next week may ask for 11 km: its 8 + 20 km scale by 11/28 to the 100 m.
      expect(
        find.textContaining('build back from what you ran'),
        findsNWidgets(2),
      );
      expect(find.textContaining('3.1'), findsOneWidget);
      expect(find.textContaining('7.8'), findsOneWidget);
      expect(find.textContaining('make up a missed long run'), findsNothing);
    },
  );

  testWidgets('gate off: the same week changes nothing, as before the ramp', (
    tester,
  ) async {
    await _pump(tester);
    await _adjust(tester, 'Re-plan remaining weeks');

    expect(
      find.text("Your plan's on track — nothing to adjust."),
      findsOneWidget,
    );
    expect(find.text('Proposed changes'), findsNothing);
    expect(find.byKey(const Key('planDetailReplanAnchorNote')), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('gate on: resuming offers the weeks ahead re-anchored, through '
      'the same preview', (tester) async {
    dotenv.loadFromString(envString: 'ADAPTIVE_FITNESS_GATE=true');
    await _pump(tester, status: 'paused');
    await _adjust(tester, 'Resume plan');
    await pumpUntil(
      tester,
      () => tester.any(find.byKey(const Key('planDetailReplanAnchorNote'))),
      describe: 'the re-anchor preview after the resume',
    );
    expect(find.text('Proposed changes'), findsOneWidget);
    expect(
      find.textContaining('build back from what you ran'),
      findsNWidgets(2),
    );
    await tester.pump(const Duration(seconds: 4));
  });
}
