// The break card (decisions § 2128): when it shows, the preview it confirms,
// what it sends, the dismissal it stores, the failures it reports, and that
// the plan screen hosts it for the owner only. Web twin:
// apps/web/tests-e2e/plans/break-reschedule.spec.ts.

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;

import '../lib/l10n/date_format.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_break.dart';
import '../lib/plan_bulk_ops.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training.dart' show parseIsoDate;
import '../lib/training_service.dart';
import '../lib/widgets/plan_break_card.dart';
import 'pump_until.dart';

// The plan_break pair's fixture: ten weeks from Sunday 2026-06-07, base 0-1,
// build 2-5, peak 6-7, taper 8, race 9 on the end date; week 1's long run was
// the last thing done and today is week 4's Tuesday, 22 quiet days later.
const _owner = 'owner-uuid';
const _s = '2026-06-07';
final _start = DateTime(2026, 6, 7);
final _today = DateTime(2026, 7, 7, 9);
const _racePhases = [
  'base', 'base', 'build', 'build', 'build', 'build', 'peak', 'peak', 'taper', 'race'
];
const _freePhases = [
  'base', 'base', 'build', 'build', 'build', 'build', 'build', 'build', 'build', 'build'
];

TrainingPlanRow _plan({bool race = true, String status = 'active'}) =>
    TrainingPlanRow(
      id: 'plan-1',
      userId: _owner,
      name: 'Autumn Half',
      goalEvent: 'distance_half',
      goalDistanceM: 21097.5,
      startDate: _start,
      endDate: _start.add(Duration(days: race ? 63 : 69)),
      daysPerWeek: 3,
      status: status,
      source: 'generated',
      rules: const [],
      isTemplate: false,
      isPublicTemplate: false,
    );

List<PlanWeekRow> _weeks({bool race = true}) {
  final phases = race ? _racePhases : _freePhases;
  return [
    for (var i = 0; i < phases.length; i++)
      PlanWeekRow(id: 'w$i', planId: 'plan-1', weekIndex: i, phase: phases[i]),
  ];
}

List<PlanWorkoutRow> _workouts({bool race = true}) {
  final phases = race ? _racePhases : _freePhases;
  return [
    for (var i = 0; i < phases.length; i++) ...[
      PlanWorkoutRow(
        id: phases[i] == 'race' ? 'race' : 'long$i',
        weekId: 'w$i',
        scheduledDate: _start.add(Duration(days: 7 * i)),
        kind: phases[i] == 'race' ? 'race' : 'long',
        targetDistanceM: 12000,
        manuallyCompleted: i <= 1,
      ),
      if (phases[i] != 'race')
        PlanWorkoutRow(
          id: 'easy$i',
          weekId: 'w$i',
          scheduledDate: _start.add(Duration(days: 7 * i + 3)),
          kind: 'easy',
          targetDistanceM: 6000,
          manuallyCompleted: false,
        ),
    ],
  ];
}

class _Training extends TrainingService {
  _Training({this.error, this.race = true});
  final Object? error;
  final bool race;
  final calls = <(String, BreakChange, String, String)>[];

  @override
  Future<void> reschedulePlanAfterBreak(String planId, BreakChange change,
      String breakFromIso, String todayIso) async {
    calls.add((planId, change, breakFromIso, todayIso));
    if (error != null) throw error!;
  }

  @override
  Future<
    ({
      TrainingPlanRow? plan,
      List<PlanWeekRow> weeks,
      List<PlanWorkoutRow> workouts,
    })
  >
  fetchPlan(String id) async => (
        plan: _plan(race: race),
        weeks: _weeks(race: race),
        workouts: _workouts(race: race),
      );

  @override
  Future<List<TrainingPlanRow>> fetchMyPublishedPlans() async => const [];
}

class _Social extends SocialService {
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async =>
      const [];
}

/// The dismissal store the card reads and writes, in place of the app's
/// settings bag.
class _Prefs {
  bool loaded = true;
  Object? value;
  Object? failWith;
  final writes = <Map<String, dynamic>>[];

  void install() {
    planBreakDismissalReader = () => (loaded: loaded, value: value);
    planBreakDismissalWriter = (v) async {
      if (failWith != null) throw failWith!;
      writes.add(v);
      value = v;
    };
  }
}

late AppLocalizations _l10n;

Future<void> _pump(WidgetTester tester, _Training training,
    {bool race = true, List<DateTime>? runStarts = const [], void Function()? onApplied}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: PlanBreakCard(
          training: training,
          plan: _plan(race: race),
          weeks: _weeks(race: race),
          workouts: _workouts(race: race),
          runStarts: runStarts,
          now: _today,
          onApplied: () async => onApplied?.call(),
        ),
      ),
    ),
  ));
}

String _med(String iso) => formatDateMed(parseIsoDate(iso), 'en');

Future<void> _settleBanner(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 6));

void main() {
  late _Prefs prefs;

  setUpAll(() async {
    await initializeDateFormatting();
    _l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() {
    prefs = _Prefs()..install();
  });

  test('shows only with a break, known runs, a loaded bag and no answer yet', () {
    bool shows({List<DateTime>? runStarts = const []}) => PlanBreakCard.shows(
          plan: _plan(),
          weeks: _weeks(),
          workouts: _workouts(),
          runStarts: runStarts,
          now: _today,
        );
    expect(shows(), isTrue);
    expect(shows(runStarts: null), isFalse);
    expect(shows(runStarts: [DateTime(2026, 7, 4, 8)]), isFalse);
    prefs.loaded = false;
    expect(shows(), isFalse);
    prefs.loaded = true;
    prefs.value = {'plan_id': 'plan-1', 'from': shiftIsoDate(_s, 8)};
    expect(shows(), isFalse);
    prefs.value = {'plan_id': 'plan-1', 'from': '2026-05-01'};
    expect(shows(), isTrue);
  });

  testWidgets('Repeat this week previews, applies and records the answer',
      (tester) async {
    final training = _Training();
    var applied = 0;
    await _pump(tester, training, onApplied: () => applied++);
    expect(find.text(_l10n.planBreakTitle), findsOneWidget);
    expect(find.text(_l10n.planBreakBody(22, _med(shiftIsoDate(_s, 8)))),
        findsOneWidget);
    expect(find.text(_l10n.planBreakShortenBuild), findsOneWidget);

    await tester.tap(find.byKey(const Key('planBreakRepeat')));
    await tester.pumpAndSettle();
    final raceDay = _med(shiftIsoDate(_s, 63));
    expect(
        find.text([
          _l10n.planBreakPreviewRepeat(1),
          _l10n.planBreakPreviewDropped(1),
          _l10n.planBreakPreviewRaceDay(raceDay),
          _l10n.planBreakPreviewPast,
        ].join(' ')),
        findsOneWidget);
    await tester.tap(find.text(_l10n.planBreakConfirmApply));
    await tester.pumpAndSettle();

    expect(training.calls, hasLength(1));
    final (planId, change, from, today) = training.calls.single;
    expect(planId, 'plan-1');
    expect(change.repeatWeekIds, ['w4']);
    expect(change.dropWeekIds, ['w5']);
    expect(from, shiftIsoDate(_s, 8));
    expect(today, '2026-07-07');
    expect(prefs.writes, [
      {'plan_id': 'plan-1', 'from': shiftIsoDate(_s, 8)}
    ]);
    expect(applied, 1);
    expect(find.text(_l10n.planBreakApplied(raceDay)), findsOneWidget);
    expect(find.byKey(const Key('planBreakCard')), findsNothing);
    await _settleBanner(tester);
  });

  testWidgets('cancelling the preview sends nothing', (tester) async {
    final training = _Training();
    await _pump(tester, training);
    await tester.tap(find.byKey(const Key('planBreakRepeat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(training.calls, isEmpty);
    expect(prefs.writes, isEmpty);
    expect(find.byKey(const Key('planBreakCard')), findsOneWidget);
  });

  testWidgets('Shorten the build sends the weeks the stepper chose',
      (tester) async {
    final training = _Training();
    await _pump(tester, training);
    expect(find.text('3'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('planBreakWeeksPlus')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const Key('planBreakWeeksMinus')));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('planBreakMore')));
    await tester.pumpAndSettle();
    expect(find.textContaining(_l10n.planBreakPreviewRepeat(2)), findsOneWidget);
    expect(find.textContaining(_l10n.planBreakPreviewDropped(2)), findsOneWidget);
    await tester.tap(find.text(_l10n.planBreakConfirmApply));
    await tester.pumpAndSettle();
    final change = training.calls.single.$2;
    expect(change.repeatWeekIds, ['w3', 'w4']);
    expect(change.dropWeekIds, ['w5', 'w7']);
    await _settleBanner(tester);
  });

  testWidgets('a plan without a race is pushed back and its end moves',
      (tester) async {
    final training = _Training(race: false);
    await _pump(tester, training, race: false);
    expect(find.text(_l10n.planBreakPushBack), findsOneWidget);
    expect(find.text(_l10n.planBreakHintNoRace), findsOneWidget);
    await tester.tap(find.byKey(const Key('planBreakMore')));
    await tester.pumpAndSettle();
    final end = _med(shiftIsoDate(_s, 69 + 21));
    expect(find.textContaining(_l10n.planBreakPreviewEnd(end)), findsOneWidget);
    await tester.tap(find.text(_l10n.planBreakConfirmApply));
    await tester.pumpAndSettle();
    final change = training.calls.single.$2;
    expect(change.repeatWeekIds, ['w2', 'w3', 'w4']);
    expect(change.dropWeekIds, isEmpty);
    expect(change.endIso, shiftIsoDate(_s, 90));
    await _settleBanner(tester);
  });

  testWidgets('a refused change says so and keeps the card', (tester) async {
    final training = _Training(error: Exception('boom'));
    var applied = 0;
    await _pump(tester, training, onApplied: () => applied++);
    await tester.tap(find.byKey(const Key('planBreakRepeat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.planBreakConfirmApply));
    await tester.pumpAndSettle();
    expect(find.textContaining('Couldn\'t change the plan'), findsOneWidget);
    expect(find.byKey(const Key('planBreakCard')), findsOneWidget);
    expect(prefs.writes, isEmpty);
    expect(applied, 0);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('planBreakRepeat')))
            .onPressed,
        isNotNull);
    await _settleBanner(tester);
  });

  testWidgets('a later end that runs into another plan names the overlap',
      (tester) async {
    final training =
        _Training(error: const ActivePlanExistsError(), race: false);
    await _pump(tester, training, race: false);
    await tester.tap(find.byKey(const Key('planBreakRepeat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.planBreakConfirmApply));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.planOverlapConflict), findsOneWidget);
    expect(find.byKey(const Key('planBreakCard')), findsOneWidget);
    await _settleBanner(tester);
  });

  testWidgets('Keep the plan as it is stores the answer and hides the card',
      (tester) async {
    final training = _Training();
    await _pump(tester, training);
    await tester.tap(find.byKey(const Key('planBreakDismiss')));
    await tester.pumpAndSettle();
    expect(prefs.writes, [
      {'plan_id': 'plan-1', 'from': shiftIsoDate(_s, 8)}
    ]);
    expect(training.calls, isEmpty);
    expect(find.byKey(const Key('planBreakCard')), findsNothing);
  });

  testWidgets('a dismissal that cannot be saved says so', (tester) async {
    prefs.failWith = Exception('no bag');
    await _pump(tester, _Training());
    await tester.tap(find.byKey(const Key('planBreakDismiss')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Couldn\'t save that'), findsOneWidget);
    expect(find.byKey(const Key('planBreakCard')), findsOneWidget);
    await _settleBanner(tester);
  });

  testWidgets('no card while the runs are unknown or a run ended the break',
      (tester) async {
    await _pump(tester, _Training(), runStarts: null);
    expect(find.byKey(const Key('planBreakCard')), findsNothing);
    await _pump(tester, _Training(), runStarts: [DateTime(2026, 7, 5, 7)]);
    expect(find.byKey(const Key('planBreakCard')), findsNothing);
  });

  group('the plan screen', () {
    Future<void> open(WidgetTester tester, String viewer) async {
      tester.view.physicalSize = const Size(420, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PlanDetailScreen(
          training: _Training(),
          planId: 'plan-1',
          social: _Social(),
          viewerIdOverride: viewer,
          now: () => _today,
        ),
      ));
      await pumpUntil(
        tester,
        () => !tester.any(find.byType(FullBodyLoader)),
        describe: 'the plan fetch to settle',
      );
      await tester.pump();
    }

    testWidgets('offers the break to the plan owner', (tester) async {
      await open(tester, _owner);
      await pumpUntil(
        tester,
        () => tester.any(find.byKey(const Key('planDetailPlanBreak'))),
        describe: 'the break card',
      );
      expect(find.text(_l10n.planBreakTitle), findsOneWidget);
    });

    testWidgets('offers nothing to a coach reading the plan', (tester) async {
      await open(tester, 'coach-uuid');
      await tester.pump();
      expect(find.text('Autumn Half'), findsWidgets);
      expect(find.byKey(const Key('planDetailPlanBreak')), findsNothing);
    });
  });
}
