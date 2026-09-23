import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/disclosure_state.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/current_week_strip.dart';
import '../lib/widgets/plan_calendar.dart';
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

  @override
  Future<List<TrainingPlanRow>> fetchMyPublishedPlans() async => const [];
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
    () => !tester.any(find.byType(FullBodyLoader)),
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

      final today = _top(tester, find.text('TODAY').first);
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

  testWidgets('every expander defaults open', (tester) async {
    await _pump(tester);

    expect(find.byType(PlanCalendar), findsOneWidget);
    expect(find.text('Long run on Sunday'), findsOneWidget);
    expect(find.text('Week 2'), findsOneWidget);
    expect(find.text('Publish to library'), findsOneWidget);
  });

  testWidgets(
    'a collapsed section hides its body, is remembered for the account, and '
    'stays shut on the next visit',
    (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Calendar'));
      await tester.pump();
      expect(find.byType(PlanCalendar), findsNothing);
      expect(
        find.text('Week 2'),
        findsOneWidget,
        reason: 'collapsing one section leaves the others alone',
      );

      expect(await _storedBlob(tester, _owner), contains('"calendar":false'));

      await tester.pumpWidget(const SizedBox());
      await _pump(tester);
      await pumpUntil(
        tester,
        () => !tester.any(find.byType(PlanCalendar)),
        describe: 'the stored collapse to apply on the next visit',
      );
      expect(
        find.text('Calendar'),
        findsOneWidget,
        reason: 'a collapsed section keeps its name on screen',
      );
    },
  );

  testWidgets('another account on the same device keeps its own layout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      disclosureStorageKey('plan_detail', 'someone-else'): '{"calendar":false}',
      disclosureStorageKey('plan_detail', _owner): '{"weeks":false}',
    });
    await _pump(tester);
    await pumpUntil(
      tester,
      () => !tester.any(find.text('Week 2')),
      describe: "the owner's own stored collapse to apply",
    );

    expect(
      find.byType(PlanCalendar),
      findsOneWidget,
      reason: "the other account's collapse must not reach this one",
    );
  });

  testWidgets('a corrupt stored blob falls back to every section open', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      disclosureStorageKey('plan_detail', _owner): '{not json',
    });
    await _pump(tester);

    expect(find.byType(PlanCalendar), findsOneWidget);
    expect(find.text('Long run on Sunday'), findsOneWidget);
  });

  testWidgets(
    'publishing lives in the owner-only Share & publish section, not the '
    'app bar',
    (tester) async {
      await _pump(tester);
      expect(find.text('Publish as club template'), findsOneWidget);
      expect(find.text('Publish to library'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox());
      await _pump(tester, viewerId: 'someone-else');
      expect(find.text('Share & publish'), findsNothing);
      expect(find.text('Publish as club template'), findsNothing);
    },
  );
}
