import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_new_screen.dart';
import '../lib/screens/season_plan_screen.dart';
import '../lib/social_service.dart';
import '../lib/training.dart';
import '../lib/training_service.dart';

class _FakeTraining extends TrainingService {
  ({String name, GoalEvent goal, int days, DateTime start})? created;
  PlanOverlapAction? overlap;

  @override
  Future<List<TrainingPlanRow>> fetchActivePlans() async => const [];

  @override
  Future<TrainingGender> fetchViewerGender() async => null;

  @override
  Future<int?> fetchViewerAge() async => null;

  @override
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async => [];

  @override
  Future<
      ({
        TrainingPlanRow? plan,
        List<PlanWeekRow> weeks,
        List<PlanWorkoutRow> workouts
      })> fetchPlan(String id) async =>
      (plan: null, weeks: <PlanWeekRow>[], workouts: <PlanWorkoutRow>[]);

  @override
  Future<TrainingPlanRow> createPlan({
    required String name,
    required GoalEvent goalEvent,
    required double goalDistanceM,
    int? goalTimeSec,
    int? recent5kSec,
    required DateTime startDate,
    required int daysPerWeek,
    String? notes,
    required GeneratedPlan generated,
    PlanOverlapAction onOverlap = PlanOverlapAction.refuse,
  }) async {
    created =
        (name: name, goal: goalEvent, days: daysPerWeek, start: startDate);
    overlap = onOverlap;
    return TrainingPlanRow(
      id: 'new-plan',
      userId: 'u',
      name: name,
      goalEvent: goalEventDbValue(goalEvent),
      goalDistanceM: goalDistanceM,
      startDate: startDate,
      endDate: startDate.add(const Duration(days: 84)),
      daysPerWeek: daysPerWeek,
      status: 'active',
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
    );
  }
}

class _FakeSocial extends SocialService {
  @override
  Future<List<ClubView>> fetchMyClubs() async => [];
}

Widget _host(TrainingService t, SocialService s) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanNewScreen(training: t, social: s),
    );

void main() {
  testWidgets('one ready-made card opens every starter with what it asks',
      (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t, _FakeSocial()));
    await tester.pump();

    expect(find.text('Start from a ready-made plan'), findsOneWidget);
    await tester.tap(find.text('Browse ready-made plans'));
    await tester.pumpAndSettle();

    expect(find.text('Built-in plans'), findsOneWidget);
    expect(find.text('Couch to 5K (beginner walk-run)'), findsOneWidget);
    expect(find.text('Half Marathon — 12 weeks'), findsOneWidget);
    expect(find.text('Marathon — 16 weeks'), findsOneWidget);
    expect(
        find.textContaining(
            RegExp(r'^9 weeks · 3 days a week · \d+–\d+ min a session$')),
        findsOneWidget);
    expect(find.text('16 weeks · 5 days a week'), findsOneWidget);
    // No club templates, so no club section.
    expect(find.text('From your clubs'), findsNothing);
  });

  testWidgets('picking a starter creates a plan from its preset', (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t, _FakeSocial()));
    await tester.pump();

    await tester.tap(find.text('Browse ready-made plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marathon — 16 weeks'));
    await tester.pump();

    expect(t.created, isNotNull);
    expect(t.created!.name, 'Marathon — 16 weeks');
    expect(t.created!.goal, GoalEvent.distanceFull);
    expect(t.created!.days, 5);
    expect(t.created!.start.weekday, DateTime.sunday);
    expect(t.overlap, PlanOverlapAction.refuse);
  });

  testWidgets('Couch to 5K starts tomorrow, not on the next Sunday',
      (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t, _FakeSocial()));
    await tester.pump();

    await tester.tap(find.text('Browse ready-made plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Couch to 5K (beginner walk-run)'));
    await tester.pump();

    final now = DateTime.now();
    expect(t.created!.start, DateTime(now.year, now.month, now.day + 1));
    expect(t.created!.days, 3);
  });

  testWidgets('Plan a season opens the season planner', (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t, _FakeSocial()));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('planNewSeason')));
    await tester.tap(find.byKey(const Key('planNewSeason')));
    await tester.pumpAndSettle();

    expect(find.byType(SeasonPlanScreen), findsOneWidget);
    expect(find.text('Your races'), findsOneWidget);
  });
}
