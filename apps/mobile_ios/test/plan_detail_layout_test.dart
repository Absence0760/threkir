import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/disclosure_state.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/main.dart' show pendingStartWorkout;
import '../lib/run_stop_dock.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/current_week_strip.dart';
import '../lib/widgets/plan_calendar.dart';
import '../lib/widgets/todays_workout_card.dart';
import '../lib/widgets/loading_skeletons.dart';
import 'pump_until.dart';

const _owner = 'owner-uuid';

final DateTime _today = DateTime(2026, 3, 11);

DateTime get _monday =>
    _today.subtract(Duration(days: _today.weekday - DateTime.monday));

class _FakeTraining extends TrainingService {
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
      startDate: _monday,
      endDate: _monday.add(const Duration(days: 13)),
      daysPerWeek: 4,
      status: 'active',
      source: 'generated',
      rules: const ['Long run on Sunday'],
      isTemplate: false,
      isPublicTemplate: false,
    ),
    weeks: const [
      PlanWeekRow(
        id: 'w1',
        planId: 'plan-1',
        weekIndex: 0,
        phase: 'base',
        targetVolumeM: 30000,
      ),
      PlanWeekRow(
        id: 'w2',
        planId: 'plan-1',
        weekIndex: 1,
        phase: 'build',
        targetVolumeM: 34000,
      ),
    ],
    workouts: [
      PlanWorkoutRow(
        id: 'wo-today',
        weekId: 'w1',
        scheduledDate: _today,
        kind: 'easy',
        targetDistanceM: 8000,
        manuallyCompleted: false,
      ),
      PlanWorkoutRow(
        id: 'wo-long',
        weekId: 'w2',
        scheduledDate: _monday.add(const Duration(days: 13)),
        kind: 'long',
        targetDistanceM: 16000,
        manuallyCompleted: false,
      ),
    ],
  );
}

class _FakeSocial extends SocialService {
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async =>
      const [];
}

Future<void> _pump(WidgetTester tester, {String viewerId = _owner}) async {
  tester.view.physicalSize = const Size(420, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanDetailScreen(
        training: _FakeTraining(),
        planId: 'plan-1',
        social: _FakeSocial(),
        viewerIdOverride: viewerId,
        now: () => _today,
      ),
    ),
  );
  await pumpUntil(
    tester,
    () => !tester.any(find.byType(SectionedDetailSkeleton)),
    describe: 'the plan fetch to replace the full-body loader',
  );
  await tester.pump();
}

Future<String?> _storedBlob(WidgetTester tester, String userId) async {
  final prefs = await tester.runAsync(SharedPreferences.getInstance);
  return prefs!.getString(disclosureStorageKey('plan_detail', userId));
}

double _top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

const _sections = [
  'Plan progress',
  'Plan rules',
  'Calendar',
  'Week by week',
  'Share & publish',
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'today and this week lead, and every other section follows as a named '
    'expander in the web order',
    (tester) async {
      await _pump(tester);

      // Plan detail draws the same TodaysWorkoutCard as Home and the Run
      // tab, not a second treatment of its own (#1186).
      final today = _top(tester, find.byType(TodaysWorkoutCard));
      final week = _top(tester, find.byType(CurrentWeekStrip));
      expect(today, lessThan(week));

      var previous = week;
      for (final title in _sections) {
        final y = _top(tester, find.text(title));
        expect(y, greaterThan(previous), reason: '$title is out of order');
        previous = y;
      }
    },
  );

  // The current week was drawn three times (strip, calendar month, week
  // list) before every section below the strip started shut (#1186,
  // decisions § 2375).
  testWidgets('every expander starts shut, so the strip is the one week view',
      (tester) async {
    await _pump(tester);

    for (final title in _sections) {
      expect(find.text(title), findsOneWidget,
          reason: '$title keeps its name on screen while shut');
    }
    expect(find.byType(CurrentWeekStrip), findsOneWidget);
    expect(find.byType(PlanCalendar), findsNothing);
    expect(find.text('Long run on Sunday'), findsNothing);
    expect(find.text('Week 2'), findsNothing);
    expect(find.text('Publish to library'), findsNothing);
  });

  testWidgets(
    'an opened section shows its body, is remembered for the account, and '
    'stays open on the next visit',
    (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Calendar'));
      await tester.pump();
      expect(find.byType(PlanCalendar), findsOneWidget);
      expect(
        find.text('Week 2'),
        findsNothing,
        reason: 'opening one section leaves the others alone',
      );

      expect(await _storedBlob(tester, _owner), contains('"calendar":true'));

      await tester.pumpWidget(const SizedBox());
      await _pump(tester);
      await pumpUntil(
        tester,
        () => tester.any(find.byType(PlanCalendar)),
        describe: 'the stored open state to apply on the next visit',
      );

      await tester.tap(find.text('Calendar'));
      await tester.pump();
      expect(find.byType(PlanCalendar), findsNothing);
      expect(await _storedBlob(tester, _owner), contains('"calendar":false'));
    },
  );

  testWidgets('another account on the same device keeps its own layout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      disclosureStorageKey('plan_detail', 'someone-else'): '{"calendar":true}',
      disclosureStorageKey('plan_detail', _owner): '{"weeks":true}',
    });
    await _pump(tester);
    await pumpUntil(
      tester,
      () => tester.any(find.text('Week 2')),
      describe: "the owner's own stored open section to apply",
    );

    expect(
      find.byType(PlanCalendar),
      findsNothing,
      reason: "the other account's open section must not reach this one",
    );
  });

  testWidgets('a corrupt stored blob falls back to every section shut', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      disclosureStorageKey('plan_detail', _owner): '{not json',
    });
    await _pump(tester);

    expect(find.byType(PlanCalendar), findsNothing);
    expect(find.text('Long run on Sunday'), findsNothing);
    expect(find.text('Calendar'), findsOneWidget);
  });

  testWidgets(
    'publishing lives in the owner-only Share & publish section, not the '
    'app bar',
    (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Share & publish'));
      await tester.pump();
      expect(find.text('Publish as club template'), findsOneWidget);
      expect(find.text('Publish to library'), findsOneWidget);
      // The app bar's only control is the plan-actions menu, and publishing
      // is not one of its items.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(IconButton),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('planDetailMenu')));
      await tester.pumpAndSettle();
      expect(find.text('Delete plan'), findsOneWidget);
      expect(find.text('Publish to library'), findsOneWidget,
          reason: 'only the section copy, not a menu item');
      expect(find.text('Publish as club template'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await _pump(tester, viewerId: 'someone-else');
      expect(find.text('Share & publish'), findsNothing);
      expect(find.text('Publish as club template'), findsNothing);
    },
  );

  testWidgets(
    "the owner's today card starts the run with the workout armed (#1374)",
    (tester) async {
      await _pump(tester);
      addTearDown(() {
        pendingStartWorkout.value = null;
        runStartRequests.take();
      });
      final start = find.byKey(const Key('todaysWorkoutStart'));
      expect(start, findsOneWidget);
      await tester.tap(start);
      await tester.pump();
      expect(pendingStartWorkout.value?.id, 'wo-today');
      expect(runStartRequests.take(), RunStartRequest.start,
          reason: 'a Start starts the run, not only loads the workout');
    },
  );

  testWidgets('another viewer gets no Start on the today card', (tester) async {
    await _pump(tester, viewerId: 'someone-else');
    expect(find.byType(TodaysWorkoutCard), findsOneWidget);
    expect(find.byKey(const Key('todaysWorkoutStart')), findsNothing);
  });
}
