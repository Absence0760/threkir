import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

const _uid = 'owner-uuid';

DateTime _mondayThisWeek() {
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

class _FakeTraining extends TrainingService {
  final TrainingPlanRow plan;
  final List<PlanWeekRow> weeks;
  final List<PlanWorkoutRow> workouts;
  final List<String> paused = [];
  final List<String> resumed = [];
  final Map<String, double> updated = {};
  Map<String, Map<String, Object?>>? taperPatches;
  String? taperPlanId;
  int fetchCount = 0;

  /// Makes `applyRaceTaper` fail the way a refused RPC would.
  Object? taperError;
  String? replanPlanId;

  /// Makes `applyReplan` fail the way a refused RPC would.
  Object? replanError;

  /// Makes `resumePlan` refuse the way the one-active index would.
  bool resumeBlocked = false;

  _FakeTraining(this.plan, this.weeks, this.workouts);

  @override
  Future<
      ({
        TrainingPlanRow? plan,
        List<PlanWeekRow> weeks,
        List<PlanWorkoutRow> workouts
      })> fetchPlan(String id) async {
    fetchCount++;
    return (plan: plan, weeks: weeks, workouts: workouts);
  }

  @override
  Future<void> pausePlan(String id) async => paused.add(id);

  @override
  Future<void> resumePlan(String id) async {
    if (resumeBlocked) throw const ActivePlanExistsError();
    resumed.add(id);
  }

  @override
  Future<void> updateWorkout(
    String workoutId, {
    String? kind,
    String? fromKind,
    PlanWorkoutTargets? targets,
    String? notes,
    PlanWorkoutRaceFields? race,
  }) async {
    final distanceM = targets?.distanceM;
    if (distanceM != null) updated[workoutId] = distanceM;
  }

  @override
  Future<void> applyReplan({
    required String planId,
    required Map<String, double> distances,
  }) async {
    if (replanError != null) throw replanError!;
    replanPlanId = planId;
    updated.addAll(distances);
  }

  @override
  Future<void> applyRaceTaper({
    required String planId,
    required Map<String, Map<String, Object?>> patches,
  }) async {
    if (taperError != null) throw taperError!;
    taperPlanId = planId;
    taperPatches = patches;
  }
}

class _FakeSocial extends SocialService {
  final List<RecentRunRow> runs;
  _FakeSocial(this.runs);
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async => runs;
}

TrainingPlanRow _plan(DateTime start, {String status = 'active'}) =>
    TrainingPlanRow(
      id: 'plan-1',
      userId: _uid,
      name: 'Test Plan',
      goalEvent: 'distance_half',
      goalDistanceM: 21097.5,
      startDate: start,
      endDate: start.add(const Duration(days: 56)),
      daysPerWeek: 4,
      status: status,
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
    );

PlanWeekRow _week(String id, int idx, String phase, double vol) => PlanWeekRow(
    id: id, planId: 'plan-1', weekIndex: idx, phase: phase, targetVolumeM: vol);

PlanWorkoutRow _wo(String id, String weekId, DateTime date, String kind,
        double? dist,
        {String? raceName,
        String? racePriority,
        int? durationS,
        Object? structure,
        String? notes}) =>
    PlanWorkoutRow(
      id: id,
      weekId: weekId,
      scheduledDate: date,
      kind: kind,
      targetDistanceM: dist,
      targetDurationSeconds: durationS,
      structure: structure,
      notes: notes,
      manuallyCompleted: false,
      raceName: raceName,
      racePriority: racePriority,
    );

Future<void> _pump(
  WidgetTester tester, {
  required _FakeTraining training,
  required _FakeSocial social,
  String? viewerId = _uid,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanDetailScreen(
        training: training,
        planId: 'plan-1',
        social: social,
        viewerIdOverride: viewerId,
      ),
    ),
  );
  await pumpUntil(tester, () => !tester.any(find.byType(FullBodyLoader)),
      describe: 'the plan fetch to replace the full-body loader');
  await tester.pump();
}

/// Route transitions only — never `pumpAndSettle`, which a shown top banner's
/// pending timer keeps from ever settling.
Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openAdjust(WidgetTester tester) async {
  await tester.tap(find.text('Adjust plan'));
  await _settleRoute(tester);
}

/// The dialog title and the page's button share the "Adjust plan" string, and
/// two options carry the same words as their descriptions, so every in-dialog
/// finder is scoped to the dialog.
Finder _inDialog(Finder f) =>
    find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> _chooseAdjustment(WidgetTester tester, String label) async {
  final option = _inDialog(find.text(label));
  await tester.ensureVisible(option);
  await tester.tap(option);
  await _settleRoute(tester);
}

/// The preview renders below the hero and the races card, past the bottom of
/// the 800x600 test surface. `ensureVisible` only schedules the scroll, so
/// the frame has to be pumped before the tap reads the button's position.
Future<void> _tapApply(WidgetTester tester, {Finder? within}) async {
  final apply = within == null
      ? find.text('Apply changes')
      : find.descendant(of: within, matching: find.text('Apply changes'));
  await tester.ensureVisible(apply);
  await tester.pump();
  await tester.tap(apply);
}

/// A plan whose week 0 is finished and missed its long run, with a later long
/// run left to bump — the shape `replanRemaining` proposes a make-up for.
_FakeTraining _missedLongPlan({String status = 'active'}) {
  final start = _mondayThisWeek().subtract(const Duration(days: 14));
  return _FakeTraining(
    _plan(start, status: status),
    [
      _week('w0', 0, 'build', 40000),
      _week('w1', 1, 'build', 42000),
      _week('w2', 2, 'build', 44000),
    ],
    [
      _wo('missed', 'w0', start.add(const Duration(days: 1)), 'long', 28000),
      _wo('next', 'w2', _mondayThisWeek().add(const Duration(days: 9)), 'long',
          22000),
    ],
  );
}

/// A plan whose next race is a B race ten days out, with an interval five
/// days before it (its notes describe the intervals) and a one-hour tempo two
/// days before it — the shape `raceTaperProposals` eases and cuts to a
/// shakeout, clearing the interval's notes and shortening the tempo's time.
_FakeTraining _bRacePlan() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = today.subtract(const Duration(days: 7));
  return _FakeTraining(
    TrainingPlanRow(
      id: 'plan-1',
      userId: _uid,
      name: 'Test Plan',
      goalEvent: 'distance_marathon',
      goalDistanceM: 42195,
      startDate: start,
      endDate: start.add(const Duration(days: 69)),
      daysPerWeek: 4,
      status: 'active',
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
    ),
    [_week('w0', 0, 'build', 40000), _week('w1', 1, 'build', 42000)],
    [
      _wo('int', 'w0', today.add(const Duration(days: 5)), 'interval', 10000,
          notes: '6x800 at 5K pace'),
      _wo('tempo', 'w1', today.add(const Duration(days: 8)), 'tempo', 12000,
          durationS: 3600),
      _wo('b-race', 'w1', today.add(const Duration(days: 10)), 'race', 21097.5,
          raceName: 'Two Oceans Half', racePriority: 'B'),
    ],
  );
}

void main() {
  group('PlanDetailScreen — taper around B/C races', () {
    testWidgets('not offered when the plan has no future B or C race',
        (tester) async {
      final training = _missedLongPlan();
      await _pump(tester, training: training, social: _FakeSocial(const []));
      await _openAdjust(tester);

      expect(_inDialog(find.text('Taper around B/C races')), findsNothing);
    });

    testWidgets('previews the taper before a B race and applies its patches',
        (tester) async {
      final training = _bRacePlan();
      await _pump(tester, training: training, social: _FakeSocial(const []));
      await _openAdjust(tester);
      expect(_inDialog(find.textContaining('Your A race and its taper')),
          findsOneWidget);
      await _chooseAdjustment(tester, 'Taper around B/C races');

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Proposed taper and recovery'), findsOneWidget);
      expect(find.textContaining('taper for Two Oceans Half'), findsOneWidget);
      expect(find.textContaining('shakeout before Two Oceans Half'),
          findsOneWidget);
      // The tempo's hour shrinks with its distance: 5000 / 12000 of 3600 s.
      expect(find.textContaining('1:00:00 → '), findsOneWidget);
      expect(find.textContaining('25:00 — shakeout'), findsOneWidget);
      expect(find.byKey(const Key('planDetailRaceTaperNotesCleared-int')),
          findsOneWidget);
      expect(find.byKey(const Key('planDetailRaceTaperNotesCleared-tempo')),
          findsNothing);
      expect(training.taperPatches, isNull);

      await _tapApply(tester,
          within: find.byKey(const Key('planDetailRaceTaperPreview')));
      await pumpUntil(tester, () => training.taperPatches != null,
          describe: 'the taper to write its patches');
      expect(training.taperPatches!['int'], {
        'kind': 'easy',
        'target_distance_m': 6500,
        'target_pace_sec_per_km': null,
        'target_pace_tolerance_sec': null,
        'structure': null,
        'notes': null,
      });
      expect(training.taperPatches!['tempo']!['target_distance_m'], 5000);
      expect(
          training.taperPatches!['tempo']!['target_duration_seconds'], 1500);
      expect(training.taperPatches!.containsKey('b-race'), isFalse);
      expect(training.taperPlanId, 'plan-1');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'a failed taper shows the error and re-fetches the plan, dropping the preview',
        (tester) async {
      final training = _bRacePlan()..taperError = Exception('boom');
      await _pump(tester, training: training, social: _FakeSocial(const []));
      await _openAdjust(tester);
      await _chooseAdjustment(tester, 'Taper around B/C races');
      expect(find.byKey(const Key('planDetailRaceTaperPreview')),
          findsOneWidget);
      final fetchesBefore = training.fetchCount;

      await _tapApply(tester,
          within: find.byKey(const Key('planDetailRaceTaperPreview')));
      // The fake's fetchPlan counts synchronously, so the count alone is
      // already true before a frame is pumped; wait for what the runner sees.
      await pumpUntil(
          tester,
          () =>
              training.fetchCount > fetchesBefore &&
              tester.any(find.textContaining("Couldn't update the plan")) &&
              !tester.any(find.byType(FullBodyLoader)),
          describe: 'the failed taper to say so and re-fetch the plan');
      expect(find.textContaining("Couldn't update the plan"), findsOneWidget);
      expect(find.byKey(const Key('planDetailRaceTaperPreview')), findsNothing);
      expect(training.taperPatches, isNull);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('the hero names the next race and shows its distance',
        (tester) async {
      final training = _bRacePlan();
      await _pump(tester, training: training, social: _FakeSocial(const []));

      final next = find.byKey(const Key('planDetailHeroNextRace'));
      expect(next, findsOneWidget);
      expect(tester.widget<Text>(next).data, 'Next race: Two Oceans Half');
      expect(find.textContaining('21.1'), findsWidgets);
    });

    testWidgets('the hero keeps the plan goal while the A race is next',
        (tester) async {
      final training = _missedLongPlan();
      await _pump(tester, training: training, social: _FakeSocial(const []));

      expect(find.byKey(const Key('planDetailHeroNextRace')), findsNothing);
    });
  });


  group('PlanDetailScreen — Adjust plan dialog', () {
    testWidgets('the page offers one entry point, not the bare controls',
        (tester) async {
      final training = _missedLongPlan();
      await _pump(tester, training: training, social: _FakeSocial(const []));

      expect(find.text('Adjust plan'), findsOneWidget);
      expect(find.text('Re-plan remaining weeks'), findsNothing);
      expect(find.text('Adaptive re-plan'), findsNothing);
    });

    testWidgets('every choice is named and explained', (tester) async {
      final training = _missedLongPlan();
      await _pump(tester, training: training, social: _FakeSocial(const []));
      await _openAdjust(tester);

      expect(_inDialog(find.text('Re-plan remaining weeks')), findsOneWidget);
      expect(
          _inDialog(find.textContaining('Makes up a missed long run')),
          findsOneWidget);
      expect(_inDialog(find.text('Adaptive re-plan')), findsOneWidget);
      expect(
          _inDialog(find.textContaining('last three finished weeks')),
          findsOneWidget);
      expect(_inDialog(find.text('Pause plan')), findsOneWidget);
      expect(
          _inDialog(find.textContaining('without deleting anything')),
          findsOneWidget);
    });

    testWidgets('a paused plan offers Resume in place of Pause',
        (tester) async {
      final training = _missedLongPlan(status: 'paused');
      await _pump(tester, training: training, social: _FakeSocial(const []));
      await _openAdjust(tester);

      expect(_inDialog(find.text('Resume plan')), findsOneWidget);
      expect(_inDialog(find.text('Pause plan')), findsNothing);
      expect(
          _inDialog(find.textContaining('your active plan again')),
          findsOneWidget);
    });

    testWidgets('Re-plan opens the preview — its Apply is the only guard',
        (tester) async {
      final training = _missedLongPlan();
      await _pump(tester, training: training, social: _FakeSocial(const []));
      await _openAdjust(tester);
      await _chooseAdjustment(tester, 'Re-plan remaining weeks');

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Proposed changes'), findsOneWidget);
      expect(training.updated, isEmpty);

      await _tapApply(tester);
      await pumpUntil(tester, () => training.updated.isNotEmpty,
          describe: 'the re-plan to write its week updates');
      expect(training.updated['next'], (22000 * 1.15).round());
      expect(training.replanPlanId, 'plan-1');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'a failed re-plan shows the error and re-fetches the plan, dropping the preview',
        (tester) async {
      final training = _missedLongPlan()..replanError = Exception('boom');
      await _pump(tester, training: training, social: _FakeSocial(const []));
      await _openAdjust(tester);
      await _chooseAdjustment(tester, 'Re-plan remaining weeks');
      expect(find.text('Proposed changes'), findsOneWidget);
      final fetchesBefore = training.fetchCount;

      await _tapApply(tester);
      // The fake's fetchPlan counts synchronously, so the count alone is
      // already true before a frame is pumped; wait for what the runner sees.
      await pumpUntil(
          tester,
          () =>
              training.fetchCount > fetchesBefore &&
              tester.any(find.textContaining("Couldn't update the plan")) &&
              !tester.any(find.byType(FullBodyLoader)),
          describe: 'the failed re-plan to say so and re-fetch the plan');
      expect(find.textContaining("Couldn't update the plan"), findsOneWidget);
      expect(find.text('Proposed changes'), findsNothing);
      expect(training.updated, isEmpty);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Adaptive re-plan is reachable from the same dialog',
        (tester) async {
      final training = _missedLongPlan();
      await _pump(tester, training: training, social: _FakeSocial(const []));
      await _openAdjust(tester);
      await _chooseAdjustment(tester, 'Adaptive re-plan');

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Proposed changes'), findsOneWidget);
      // The trend badge is what says the adaptive path produced this preview
      // rather than the manual re-plan sitting above it in the same dialog.
      expect(find.textContaining('Based on a trend'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Pause applies without a second dialog', (tester) async {
      final training = _missedLongPlan();
      await _pump(tester, training: training, social: _FakeSocial(const []));
      await _openAdjust(tester);
      await _chooseAdjustment(tester, 'Pause plan');

      expect(find.byType(AlertDialog), findsNothing);
      await pumpUntil(tester, () => training.paused.isNotEmpty,
          describe: 'the pause to reach the service');
      expect(training.paused, ['plan-1']);
      expect(find.text('Plan paused.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a blocked Resume says which plan is in the way',
        (tester) async {
      final training = _missedLongPlan(status: 'paused')
        ..resumeBlocked = true;
      await _pump(tester, training: training, social: _FakeSocial(const []));
      await _openAdjust(tester);
      await _chooseAdjustment(tester, 'Resume plan');

      await pumpUntil(
          tester,
          () => tester.any(
              find.textContaining('Another active plan overlaps these dates')),
          describe: 'the blocked-resume banner');
      expect(training.resumed, isEmpty);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('hidden from a non-owner viewer', (tester) async {
      final training = _missedLongPlan();
      await _pump(tester,
          training: training,
          social: _FakeSocial(const []),
          viewerId: 'someone-else');

      expect(find.text('Adjust plan'), findsNothing);
    });
  });
}
