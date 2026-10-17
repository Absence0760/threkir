import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/current_week_strip.dart';
import '../lib/widgets/todays_workout_card.dart';
import 'pump_until.dart';

// Plan detail answers "where am I in my plan?": week of N, the countdown, a
// paused plan, who assigned it, what is next when nothing is due today, and
// the finished weeks folded out of the way (issue #1186).

const _owner = 'owner-uuid';

// A Monday-started, three-week plan: 2026-03-02 .. 2026-03-22.
final DateTime _start = DateTime(2026, 3, 2);

PlanWorkoutRow _wo(String id, String weekId, DateTime date, String kind,
        {double? km, bool done = false}) =>
    PlanWorkoutRow(
      id: id,
      weekId: weekId,
      scheduledDate: date,
      kind: kind,
      targetDistanceM: km == null ? null : km * 1000,
      completedRunId: done ? 'run-$id' : null,
      manuallyCompleted: false,
    );

class _FakeTraining extends TrainingService {
  final String status;
  final String? coachId;
  _FakeTraining({this.status = 'active', this.coachId});

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
      name: 'Spring 10K',
      goalEvent: 'distance_10k',
      goalDistanceM: 10000,
      startDate: _start,
      endDate: DateTime(2026, 3, 22),
      daysPerWeek: 3,
      status: status,
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
      assignedByCoachId: coachId,
    ),
    weeks: const [
      PlanWeekRow(id: 'w1', planId: 'plan-1', weekIndex: 0, phase: 'base', targetVolumeM: 20000),
      PlanWeekRow(id: 'w2', planId: 'plan-1', weekIndex: 1, phase: 'build', targetVolumeM: 24000),
      PlanWeekRow(id: 'w3', planId: 'plan-1', weekIndex: 2, phase: 'taper', targetVolumeM: 16000),
    ],
    workouts: [
      _wo('a', 'w1', DateTime(2026, 3, 3), 'easy', km: 5, done: true),
      _wo('b', 'w1', DateTime(2026, 3, 5), 'tempo', km: 6),
      _wo('c', 'w2', DateTime(2026, 3, 10), 'easy', km: 6, done: true),
      _wo('d', 'w2', DateTime(2026, 3, 12), 'interval', km: 7, done: true),
      _wo('e', 'w3', DateTime(2026, 3, 17), 'easy', km: 5),
      _wo('f', 'w3', DateTime(2026, 3, 22), 'race', km: 10),
    ],
  );

  @override
  Future<List<TrainingPlanRow>> fetchMyPublishedPlans() async => const [];

  @override
  Future<String?> fetchDisplayName(String userId) async =>
      userId == 'coach-1' ? 'Carla' : null;

  @override
  Future<bool> isActiveCoachOf(String athleteId) async => false;
}

class _FakeSocial extends SocialService {
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async =>
      const [];
}

Future<void> _pump(WidgetTester tester, DateTime today,
    {String status = 'active', String? coachId}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(420, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanDetailScreen(
        training: _FakeTraining(status: status, coachId: coachId),
        planId: 'plan-1',
        social: _FakeSocial(),
        viewerIdOverride: _owner,
        now: () => today,
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

String _text(WidgetTester tester, Key key) {
  final w = tester.widget(find.byKey(key));
  if (w is Text) return w.data!;
  return tester
      .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
      .map((t) => t.data)
      .join(' ');
}

void main() {
  testWidgets('the header says which week it is and how far the race is, in '
      'localized dates', (tester) async {
    await _pump(tester, DateTime(2026, 3, 11));
    expect(_text(tester, const Key('planDetailWeekOfN')), 'Week 2 of 3');
    expect(_text(tester, const Key('planDetailCountdown')), 'Race in 11 days');
    expect(_text(tester, const Key('planDetailDateRange')),
        startsWith('Mar 2 → Mar 22, 2026'));
    expect(find.textContaining('2026-03-'), findsNothing);
  });

  testWidgets('before the start date nothing is "this week": the strip names '
      'the first week, the countdown names the start, and the next session '
      'leads', (tester) async {
    await _pump(tester, DateTime(2026, 2, 26));
    expect(find.byKey(const Key('planDetailWeekOfN')), findsNothing);
    expect(_text(tester, const Key('planDetailCountdown')), 'Starts in 4 days');
    expect(
      find.descendant(
          of: find.byType(CurrentWeekStrip), matching: find.text('First week')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('planDetailTodayNextUp')), findsOneWidget);
    expect(find.byKey(const Key('planDetailEarlierWeeks')), findsNothing);
  });

  testWidgets('a day with no session shows what is next instead of nothing',
      (tester) async {
    await _pump(tester, DateTime(2026, 3, 11));
    expect(find.byType(TodaysWorkoutCard), findsNothing);
    final next = find.byKey(const Key('planDetailTodayNextUp'));
    expect(next, findsOneWidget);
    expect(find.descendant(of: next, matching: find.text('Intervals')),
        findsOneWidget);
  });

  testWidgets('race day says so when the race is the only thing left',
      (tester) async {
    await _pump(tester, DateTime(2026, 3, 22));
    expect(find.byType(TodaysWorkoutCard), findsOneWidget,
        reason: 'the race is today\'s workout');
    expect(_text(tester, const Key('planDetailCountdown')), 'Race day');
  });

  testWidgets('finished weeks fold into one row with their tally, and open on '
      'tap', (tester) async {
    await _pump(tester, DateTime(2026, 3, 18));
    final row = find.byKey(const Key('planDetailEarlierWeeks'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('2 earlier weeks')),
        findsOneWidget);
    // a, c, d done of a, b, c, d.
    expect(find.descendant(of: row, matching: find.text('3 / 4 done')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('planDetailWeek-0')), findsNothing);
    expect(find.byKey(const ValueKey('planDetailWeek-2')), findsOneWidget);
    expect(_text(tester, const ValueKey('planDetailWeekCount-2')), '0 / 2 done');

    await tester.tap(row);
    await tester.pump();
    expect(find.byKey(const ValueKey('planDetailWeek-0')), findsOneWidget);
  });

  testWidgets('a past workout left open reads as missed to a screen reader',
      (tester) async {
    await _pump(tester, DateTime(2026, 3, 18));
    await tester.tap(find.byKey(const Key('planDetailEarlierWeeks')));
    await tester.pump();
    expect(
      find.byWidgetPredicate((w) =>
          w is Semantics &&
          (w.properties.label ?? '').endsWith('Tempo, 6.0 km, missed')),
      findsWidgets,
    );
  });

  testWidgets('a paused plan says so in the header', (tester) async {
    await _pump(tester, DateTime(2026, 3, 11), status: 'paused');
    expect(_text(tester, const Key('planDetailPaused')), 'Paused');
  });

  testWidgets('a coach-assigned plan names the coach', (tester) async {
    await _pump(tester, DateTime(2026, 3, 11), coachId: 'coach-1');
    await pumpUntil(
      tester,
      () => find.text('Assigned by Carla').evaluate().isNotEmpty,
      describe: "the coach's name to load",
    );
  });

  testWidgets("the runner's own plan carries no assigned-by chip",
      (tester) async {
    await _pump(tester, DateTime(2026, 3, 11));
    expect(find.byKey(const Key('planDetailAssignedBy')), findsNothing);
  });
}
