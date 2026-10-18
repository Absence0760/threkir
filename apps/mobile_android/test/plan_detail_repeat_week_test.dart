// Plan detail's "Too hard? Repeat this week": the walk-run offer card, the
// week ⋮ menu's "Repeat week" on this week and last week only, the confirm
// that names the new end date or the race day kept, and the refusals.

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_repeat_week.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

const _owner = 'owner-uuid';
final DateTime _today = DateTime(2026, 3, 11);
final DateTime _start = DateTime(2026, 2, 15);

TrainingPlanRow _plan({required bool race}) => TrainingPlanRow(
      id: 'plan-1',
      userId: _owner,
      name: race ? 'Spring 10K' : 'Couch to 5K',
      goalEvent: 'distance_5k',
      goalDistanceM: 5000,
      startDate: _start,
      endDate: race ? DateTime(2026, 3, 29) : DateTime(2026, 3, 21),
      daysPerWeek: 3,
      status: 'active',
      source: 'generated',
      rules: const [],
      isTemplate: false,
      isPublicTemplate: false,
    );

const _racePhases = ['base', 'build', 'build', 'build', 'peak', 'taper', 'race'];
const _walkPhases = ['base', 'base', 'base', 'base', 'base'];

class _FakeTraining extends TrainingService {
  final bool race;
  final Object? repeatError;
  final List<TrainingPlanRow> others;
  final repeatCalls = <(String, String, String?, String)>[];

  _FakeTraining({this.race = false, this.repeatError, this.others = const []});

  @override
  Future<
    ({
      TrainingPlanRow? plan,
      List<PlanWeekRow> weeks,
      List<PlanWorkoutRow> workouts,
    })
  >
  fetchPlan(String id) async {
    final phases = race ? _racePhases : _walkPhases;
    final workouts = <PlanWorkoutRow>[];
    for (var i = 0; i < phases.length; i++) {
      final days = race ? const [0] : const [0, 2, 4];
      for (final d in days) {
        final date = _start.add(Duration(days: 7 * i + d));
        final isRace = phases[i] == 'race';
        workouts.add(PlanWorkoutRow(
          id: 'wo-$i-$d',
          weekId: 'w$i',
          scheduledDate: date,
          kind: isRace ? 'race' : (race ? 'long' : 'walk_run'),
          targetDistanceM: isRace ? 10000 : 3000,
          targetDurationSeconds: race ? null : 1800,
          manuallyCompleted: date.isBefore(_today),
        ));
      }
    }
    return (
      plan: _plan(race: race),
      weeks: [
        for (var i = 0; i < phases.length; i++)
          PlanWeekRow(id: 'w$i', planId: 'plan-1', weekIndex: i, phase: phases[i])
      ],
      workouts: workouts,
    );
  }

  @override
  Future<List<TrainingPlanRow>> fetchMyPublishedPlans() async => const [];

  @override
  Future<List<TrainingPlanRow>> fetchActivePlans() async =>
      [_plan(race: race), ...others];

  @override
  Future<void> repeatPlanWeek(
      String planId, RepeatWeekChange change, String todayIso) async {
    repeatCalls.add((planId, change.weekId, change.dropWeekId, todayIso));
    final e = repeatError;
    if (e != null) throw e;
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

Future<void> _openWeekMenu(WidgetTester tester, int weekIndex) async {
  final menu = find.byKey(ValueKey('planDetailWeekMenu-$weekIndex'));
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await tester.pumpAndSettle();
}

String _dialogText(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(Text)))
    .map((t) => t.data ?? '')
    .join('\n');

Future<void> _drainBanner(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 4));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'a walk-run plan offers this week again and the confirm names the new end',
      (tester) async {
    final training = _FakeTraining();
    await _pump(tester, training);
    expect(find.byKey(const Key('planDetailRepeatWeekOffer')), findsOneWidget);
    expect(find.text('Too hard?'), findsOneWidget);

    final button = find.byKey(const Key('planDetailRepeatWeekOfferButton'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final text = _dialogText(tester);
    expect(text, contains('Repeat week 4?'));
    expect(text, contains('Week 4 runs again as week 5, from Mar 15.'));
    expect(text, contains('the plan now ends on Mar 28'));

    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Repeat week')));
    await tester.pumpAndSettle();
    expect(training.repeatCalls, [('plan-1', 'w3', null, '2026-03-11')]);
    expect(find.text('Week 4 runs again from Mar 15.'), findsOneWidget);
    await _drainBanner(tester);
  });

  testWidgets('the week menu offers Repeat week on this week and last week only',
      (tester) async {
    final training = _FakeTraining();
    await _pump(tester, training);
    final earlier = find.byKey(const Key('planDetailEarlierWeeks'));
    await tester.ensureVisible(earlier);
    await tester.tap(earlier);
    await tester.pumpAndSettle();

    await _openWeekMenu(tester, 1);
    expect(find.byKey(const ValueKey('planDetailRepeatWeek-1')), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await _openWeekMenu(tester, 2);
    await tester.tap(find.byKey(const ValueKey('planDetailRepeatWeek-2')));
    await tester.pumpAndSettle();
    expect(_dialogText(tester), contains('Week 3 runs again as week 5'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(training.repeatCalls, isEmpty, reason: 'nothing before the confirm');
  });

  testWidgets('a race plan keeps race day and shows no walk-run offer',
      (tester) async {
    final training = _FakeTraining(race: true);
    await _pump(tester, training);
    expect(find.byKey(const Key('planDetailRepeatWeekOffer')), findsNothing);

    await _openWeekMenu(tester, 3);
    await tester.tap(find.byKey(const ValueKey('planDetailRepeatWeek-3')));
    await tester.pumpAndSettle();
    expect(_dialogText(tester),
        contains('To keep race day on Mar 29, one later week before the taper comes out.'));
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Repeat week')));
    await tester.pumpAndSettle();
    expect(training.repeatCalls, [('plan-1', 'w3', 'w4', '2026-03-11')]);
    await _drainBanner(tester);
  });

  testWidgets('a later end that runs into another active plan is refused first',
      (tester) async {
    final next = TrainingPlanRow(
      id: 'plan-next',
      userId: _owner,
      name: 'Summer 10K',
      goalEvent: 'distance_10k',
      goalDistanceM: 10000,
      startDate: DateTime(2026, 3, 22),
      endDate: DateTime(2026, 5, 3),
      daysPerWeek: 3,
      status: 'active',
      source: 'generated',
      rules: const [],
      isTemplate: false,
      isPublicTemplate: false,
    );
    final training = _FakeTraining(others: [next]);
    await _pump(tester, training);
    final button = find.byKey(const Key('planDetailRepeatWeekOfferButton'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
        find.text(
            'Repeating this week would run the plan into another active plan. Move or end that plan first.'),
        findsOneWidget);
    expect(training.repeatCalls, isEmpty);
    await _drainBanner(tester);
  });

  testWidgets('a spent hourly budget reads as a wait', (tester) async {
    final training = _FakeTraining(
      repeatError: const PostgrestException(
        message: 'rate limit exceeded for repeat_plan_week, retry in 1800s',
        code: 'P0001',
      ),
    );
    await _pump(tester, training);
    final button = find.byKey(const Key('planDetailRepeatWeekOfferButton'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Repeat week')));
    await tester.pumpAndSettle();

    expect(
        find.text(
            "You're repeating plan weeks too quickly — please wait 30 minutes and try again."),
        findsOneWidget);
    await _drainBanner(tester);
  });
}
