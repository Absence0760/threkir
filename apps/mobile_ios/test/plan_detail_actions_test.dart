// Plan detail's action menus (#1186 Plan actions): the app-bar menu (Adjust,
// Shift dates, Export, Delete) and the per-week menu (Duplicate, Make
// recovery week).

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/cycle_plan.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_serialize.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training.dart' show GoalEvent, WorkoutKind;
import '../lib/training_service.dart';
import 'pump_until.dart';

const _owner = 'owner-uuid';
final DateTime _today = DateTime(2026, 3, 11);

TrainingPlanRow _plan({bool template = false}) => TrainingPlanRow(
      id: 'plan-1',
      userId: _owner,
      name: 'Spring Half',
      goalEvent: 'distance_half',
      goalDistanceM: 21097.5,
      goalTimeSeconds: 7200,
      startDate: DateTime(2026, 3, 9),
      endDate: DateTime(2026, 3, 22),
      daysPerWeek: 4,
      status: template ? 'template' : 'active',
      source: 'generated',
      rules: const [],
      isTemplate: template,
      isPublicTemplate: false,
    );

final _workouts = [
  PlanWorkoutRow(
    id: 'wo-tempo',
    weekId: 'w1',
    scheduledDate: DateTime(2026, 3, 10),
    kind: 'tempo',
    targetDistanceM: 10000,
    targetPaceSecPerKm: 270,
    manuallyCompleted: false,
  ),
  PlanWorkoutRow(
    id: 'wo-long',
    weekId: 'w2',
    scheduledDate: DateTime(2026, 3, 22),
    kind: 'long',
    targetDistanceM: 16000,
    targetPaceSecPerKm: 330,
    manuallyCompleted: false,
  ),
];

class _FakeTraining extends TrainingService {
  final bool template;

  /// What each shift call does, in order: null succeeds, an object throws.
  final List<Object?> shiftOutcomes;
  final shiftCalls = <(int, bool)>[];
  final recoveryCalls = <List<String>>[];
  final deleted = <String>[];
  int fetchCalls = 0;

  _FakeTraining({this.template = false, this.shiftOutcomes = const [null]});

  @override
  Future<
    ({
      TrainingPlanRow? plan,
      List<PlanWeekRow> weeks,
      List<PlanWorkoutRow> workouts,
    })
  >
  fetchPlan(String id) async {
    fetchCalls++;
    return (
      plan: _plan(template: template),
      weeks: const [
        PlanWeekRow(id: 'w1', planId: 'plan-1', weekIndex: 0, phase: 'base'),
        PlanWeekRow(id: 'w2', planId: 'plan-1', weekIndex: 1, phase: 'build'),
      ],
      workouts: _workouts,
    );
  }

  @override
  Future<List<TrainingPlanRow>> fetchMyPublishedPlans() async => const [];

  @override
  Future<void> shiftTrainingPlan(String planId, int days,
      {bool shiftFollowing = false}) async {
    final outcome =
        shiftOutcomes[shiftCalls.length.clamp(0, shiftOutcomes.length - 1)];
    shiftCalls.add((days, shiftFollowing));
    if (outcome != null) throw outcome;
  }

  @override
  Future<int> markWeekRecovery(
      String planId, List<PlanWorkoutRow> workouts) async {
    recoveryCalls.add([for (final w in workouts) w.id]);
    return workouts.length;
  }

  @override
  Future<void> deletePlan(String id) async => deleted.add(id);

  final metaCalls = <(String, String?, int, List<String>?)>[];
  final goalCalls = <(int?, double?, List<Map<String, Object?>>)>[];

  @override
  Future<void> updatePlanMeta(String planId,
          {required String name,
          required String? notes,
          required int daysPerWeek,
          required List<String>? rules}) async =>
      metaCalls.add((name, notes, daysPerWeek, rules));

  final cycleCalls = <(CyclePlanMode, String, int)>[];
  int cycleChanges = 2;

  @override
  Future<int> applyCycleAdjustment(String planId,
      List<PlanWorkoutRow> workouts, CyclePlanConfig cfg, String todayIso) async {
    cycleCalls.add((cfg.mode, todayIso, workouts.length));
    return cycleChanges;
  }

  @override
  Future<void> setPlanGoalTime(String planId, int? goalTimeSec, double? vdot,
          List<Map<String, Object?>> changes) async =>
      goalCalls.add((goalTimeSec, vdot, changes));
}

class _FakeSocial extends SocialService {
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async =>
      const [];
}

class _RecordingSharePlatform extends SharePlatform {
  final calls = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    calls.add(params);
    return const ShareResult('recorded', ShareResultStatus.success);
  }
}

late _RecordingSharePlatform _share;

Future<void> _pump(WidgetTester tester, _FakeTraining training,
    {String viewerId = _owner, CyclePlanConfig? cycleConfig}) async {
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
                cyclePlanConfig: () => cycleConfig,
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

Future<void> _openPlanMenu(WidgetTester tester, String item) async {
  await tester.tap(find.byKey(const Key('planDetailMenu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

Future<void> _shiftBy(WidgetTester tester, String days) async {
  await _openPlanMenu(tester, 'Shift dates…');
  await tester.enterText(find.byKey(const Key('planDetailShiftDays')), days);
  await tester.tap(find.widgetWithText(FilledButton, 'Shift dates'));
  await tester.pumpAndSettle();
}

Future<void> _drainBanner(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 4));

void main() {
  setUpAll(() {
    _share = _RecordingSharePlatform();
    SharePlatform.instance = _share;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _share.calls.clear();
  });

  group('who gets the menus', () {
    testWidgets('the owner gets the plan menu and a menu on each week',
        (tester) async {
      await _pump(tester, _FakeTraining());
      expect(find.byKey(const Key('planDetailMenu')), findsOneWidget);
      expect(find.byTooltip('Week 1 actions'), findsOneWidget);
      expect(find.byTooltip('Week 2 actions'), findsOneWidget);
    });

    testWidgets('another viewer gets neither', (tester) async {
      await _pump(tester, _FakeTraining(), viewerId: 'someone-else');
      expect(find.byKey(const Key('planDetailMenu')), findsNothing);
      expect(find.byTooltip('Week 1 actions'), findsNothing);
    });

    testWidgets('a template gets neither', (tester) async {
      await _pump(tester, _FakeTraining(template: true));
      expect(find.byKey(const Key('planDetailMenu')), findsNothing);
      expect(find.byTooltip('Week 1 actions'), findsNothing);
    });
  });

  group('shift dates', () {
    testWidgets('moves the plan by the typed days and reloads', (tester) async {
      final training = _FakeTraining();
      await _pump(tester, training);
      final loads = training.fetchCalls;

      await _shiftBy(tester, '-3');

      expect(training.shiftCalls, [(-3, false)]);
      expect(find.text('Plan shifted by 3 days'), findsOneWidget);
      expect(training.fetchCalls, greaterThan(loads));
      await _drainBanner(tester);
    });

    testWidgets('zero or out of range is refused in the field', (tester) async {
      final training = _FakeTraining();
      await _pump(tester, training);

      for (final bad in ['0', '400', 'abc']) {
        if (bad == '0') {
          await _openPlanMenu(tester, 'Shift dates…');
        }
        await tester.enterText(
            find.byKey(const Key('planDetailShiftDays')), bad);
        await tester.tap(find.widgetWithText(FilledButton, 'Shift dates'));
        await tester.pumpAndSettle();
        expect(find.textContaining('whole number of days'), findsOneWidget,
            reason: '"$bad" must not reach the RPC');
      }
      expect(training.shiftCalls, isEmpty);
    });

    testWidgets(
        'a forward shift into the next plan offers to move it too, and does',
        (tester) async {
      final training =
          _FakeTraining(shiftOutcomes: [const ActivePlanExistsError(), null]);
      await _pump(tester, training);

      await _shiftBy(tester, '7');
      expect(find.text('Move the plans after this one too?'), findsOneWidget);
      expect(training.shiftCalls, [(7, false)]);

      await tester.tap(find.text('Move them too'));
      await tester.pumpAndSettle();
      expect(training.shiftCalls, [(7, false), (7, true)]);
      expect(find.text('Plan shifted by 7 days'), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('declining to move the next plan changes nothing',
        (tester) async {
      final training =
          _FakeTraining(shiftOutcomes: [const ActivePlanExistsError()]);
      await _pump(tester, training);

      await _shiftBy(tester, '7');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(training.shiftCalls, [(7, false)]);
      expect(find.textContaining('Plan shifted'), findsNothing);
    });

    testWidgets('a backward shift into an earlier plan says what to do',
        (tester) async {
      final training =
          _FakeTraining(shiftOutcomes: [const ActivePlanExistsError()]);
      await _pump(tester, training);

      await _shiftBy(tester, '-7');
      expect(training.shiftCalls, [(-7, false)]);
      expect(find.textContaining('comes before this one'), findsOneWidget);
      expect(find.text('Move the plans after this one too?'), findsNothing);
      await _drainBanner(tester);
    });
  });

  group('recovery week', () {
    testWidgets('confirms, then eases that week only', (tester) async {
      final training = _FakeTraining();
      await _pump(tester, training);

      await tester.tap(find.byTooltip('Week 1 actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make recovery week').last);
      await tester.pumpAndSettle();
      expect(find.text('Make this a recovery week?'), findsOneWidget);
      expect(training.recoveryCalls, isEmpty);

      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Make recovery week')));
      await tester.pumpAndSettle();
      expect(training.recoveryCalls, [
        ['wo-tempo']
      ]);
      expect(find.text('Week eased to a recovery week'), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('cancelling the confirm changes nothing', (tester) async {
      final training = _FakeTraining();
      await _pump(tester, training);

      await tester.tap(find.byTooltip('Week 2 actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make recovery week').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(training.recoveryCalls, isEmpty);
    });
  });

  group('export', () {
    testWidgets('Markdown shares the table web exports', (tester) async {
      await _pump(tester, _FakeTraining());
      await _openPlanMenu(tester, 'Export as Markdown');

      expect(_share.calls, hasLength(1));
      final text = _share.calls.single.text!;
      expect(text, startsWith('# Spring Half'));
      final parsed = parsePlanMarkdown(text);
      expect(parsed.name, 'Spring Half');
      expect(
          parsed.generated.weeks.expand((w) => w.workouts).map((w) => w.kind),
          [WorkoutKind.tempo, WorkoutKind.long]);
    });

    testWidgets('JSON shares the export the import reads back', (tester) async {
      await _pump(tester, _FakeTraining());
      await _openPlanMenu(tester, 'Export as JSON');

      final text = _share.calls.single.text!;
      expect(text, contains('"target_distance_m": 10000,'));
      final parsed = parsePlanJson(text);
      expect(parsed.goalEvent, GoalEvent.distanceHalf);
      expect(parsed.generated.weeks.expand((w) => w.workouts), hasLength(2));
    });
  });

  group('edit plan details', () {
    Future<void> openSheet(WidgetTester tester) async {
      await _openPlanMenu(tester, 'Edit plan details');
      expect(find.byKey(const Key('planDetailsSave')), findsOneWidget);
    }

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('planDetailsSave')));
      await tester.tap(find.byKey(const Key('planDetailsSave')));
      await tester.pumpAndSettle();
    }

    testWidgets('a rename writes the details and leaves the paces alone',
        (tester) async {
      final training = _FakeTraining();
      await _pump(tester, training);
      await openSheet(tester);

      await tester.enterText(find.byKey(const Key('planDetailsName')), 'Autumn Half');
      await save(tester);

      expect(training.metaCalls, [('Autumn Half', null, 4, null)]);
      expect(training.goalCalls, isEmpty,
          reason: 'an unchanged goal time re-derives nothing');
      expect(find.text('Plan updated.'), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('a faster goal re-derives the paces still ahead with it',
        (tester) async {
      final training = _FakeTraining();
      await _pump(tester, training);
      await openSheet(tester);

      await tester.enterText(find.byKey(const Key('planDetailsGoalHours')), '1');
      await tester.enterText(find.byKey(const Key('planDetailsGoalMinutes')), '48');
      await save(tester);

      final (goal, vdot, changes) = training.goalCalls.single;
      expect(goal, 6480);
      expect(vdot, isNotNull, reason: 'a goal-anchored plan takes the new VDOT');
      expect(changes, [
        {'id': 'wo-long', 'target_pace_sec_per_km': 297}
      ], reason: 'the past tempo keeps its pace; 1:48 / 2:00 is 0.9');
      expect(training.metaCalls, hasLength(1));
      expect(find.text('Plan updated. Paces re-derived for 1 upcoming workout.'),
          findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('an impossible goal time or an empty name is refused in the sheet',
        (tester) async {
      final training = _FakeTraining();
      await _pump(tester, training);
      await openSheet(tester);

      await tester.enterText(find.byKey(const Key('planDetailsGoalMinutes')), '75');
      await tester.enterText(find.byKey(const Key('planDetailsName')), '  ');
      await save(tester);

      expect(find.textContaining('minutes and seconds up to 59'), findsOneWidget);
      expect(find.text('Add a plan name.'), findsOneWidget);
      expect(training.metaCalls, isEmpty);
      expect(training.goalCalls, isEmpty);
    });
  });

  group('cycle / pregnancy adjustment', () {
    Future<void> openAdjust(WidgetTester tester) =>
        _openPlanMenu(tester, 'Adjust plan');

    testWidgets('no config, no option', (tester) async {
      await _pump(tester, _FakeTraining());
      await openAdjust(tester);
      expect(find.text('Adjust for my cycle'), findsNothing);
      expect(find.text('Adjust for pregnancy'), findsNothing);
    });

    testWidgets('a pregnancy config offers it, confirms, then applies from today',
        (tester) async {
      final training = _FakeTraining();
      await _pump(tester, training,
          cycleConfig: const CyclePlanConfig.pregnancy(dueDateIso: '2026-09-01'));
      await openAdjust(tester);

      await tester.tap(find.text('Adjust for pregnancy'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This is not medical advice'), findsOneWidget);
      expect(training.cycleCalls, isEmpty, reason: 'nothing before the confirm');

      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Adjust for pregnancy')));
      await tester.pumpAndSettle();
      expect(training.cycleCalls, [(CyclePlanMode.pregnancy, '2026-03-11', 2)]);
      expect(find.text('Upcoming weeks adjusted.'), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('nothing to change says so', (tester) async {
      final training = _FakeTraining()..cycleChanges = 0;
      await _pump(tester, training,
          cycleConfig: const CyclePlanConfig.cycle(
              cycleLengthDays: 28, lastPeriodStartIso: '2026-03-01'));
      await openAdjust(tester);
      await tester.tap(find.text('Adjust for my cycle'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Adjust for my cycle')));
      await tester.pumpAndSettle();
      expect(find.text('No upcoming workouts needed adjusting.'), findsOneWidget);
      await _drainBanner(tester);
    });
  });

  group('delete', () {
    testWidgets('confirms, deletes and leaves the screen', (tester) async {
      final training = _FakeTraining();
      await _pump(tester, training);

      await _openPlanMenu(tester, 'Delete plan');
      expect(training.deleted, isEmpty, reason: 'nothing before the confirm');
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Delete')));
      await tester.pumpAndSettle();

      expect(training.deleted, ['plan-1']);
      expect(find.byType(PlanDetailScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('cancelling keeps the plan', (tester) async {
      final training = _FakeTraining();
      await _pump(tester, training);

      await _openPlanMenu(tester, 'Delete plan');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(training.deleted, isEmpty);
      expect(find.byType(PlanDetailScreen), findsOneWidget);
    });
  });
}
