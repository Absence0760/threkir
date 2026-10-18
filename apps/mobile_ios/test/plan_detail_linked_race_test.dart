import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/race_service.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

const _owner = 'owner-uuid';
const _listingId = '11111111-1111-4111-8111-111111111111';

final DateTime _today = DateTime(2026, 3, 11);

DateTime get _monday =>
    _today.subtract(Duration(days: _today.weekday - DateTime.monday));

class _FakeTraining extends TrainingService {
  final String? raceListingId;

  _FakeTraining({this.raceListingId});

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
      name: 'Richmond build',
      goalEvent: 'distance_full',
      goalDistanceM: 42195,
      startDate: _monday,
      endDate: _monday.add(const Duration(days: 13)),
      daysPerWeek: 4,
      status: 'active',
      source: 'generated',
      rules: const [],
      isTemplate: false,
      isPublicTemplate: false,
      raceListingId: raceListingId,
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
        id: 'wo-today',
        weekId: 'w1',
        scheduledDate: _today,
        kind: 'easy',
        targetDistanceM: 8000,
        manuallyCompleted: false,
      ),
    ],
  );

  @override
  Future<List<TrainingPlanRow>> fetchMyPublishedPlans() async => const [];

  @override
  Future<List<TrainingPlanRow>> fetchMyPlans() async => const [];

  @override
  Future<PlanRunHistory?> fetchPlanRunHistory() async => null;
}

class _FakeSocial extends SocialService {
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async =>
      const [];
}

class _FakeRaces extends RaceService {
  final bool fail;
  int calls = 0;

  _FakeRaces({this.fail = false});

  @override
  Future<RaceListingView?> fetchRaceListing(String id) async {
    calls++;
    if (fail) throw Exception('network down');
    return const RaceListingView(
      id: _listingId,
      provider: 'runsignup',
      providerRaceId: null,
      name: 'Richmond Marathon',
      raceDate: '2026-11-14',
      distanceM: 42195,
      locationLabel: 'Richmond, VA, US',
      entryUrl: null,
      resultsUrl: null,
      isVerified: true,
      distanceMAway: null,
    );
  }

  @override
  Future<List<RaceListingRun>> fetchMyRunsAtRace(String listingId) async =>
      const [];
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeTraining training,
  required _FakeRaces races,
  void Function(BuildContext context, String listingId)? openRace,
}) async {
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
        viewerIdOverride: _owner,
        now: () => _today,
        raceService: races,
        openRaceOverride: openRace,
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a plan built for a race names the race and opens it',
      (tester) async {
    final races = _FakeRaces();
    String? opened;
    await _pump(
      tester,
      training: _FakeTraining(raceListingId: _listingId),
      races: races,
      openRace: (_, id) => opened = id,
    );

    final row = find.byKey(const Key('planDetailLinkedRace'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(
        of: row,
        matching: find.text('Built for Richmond Marathon · Nov 14, 2026'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pump();
    expect(opened, _listingId);
  });

  testWidgets('a plan with no race link shows no race row and reads nothing',
      (tester) async {
    final races = _FakeRaces();
    await _pump(tester, training: _FakeTraining(), races: races);

    expect(find.byKey(const Key('planDetailLinkedRace')), findsNothing);
    expect(races.calls, 0);
  });

  testWidgets('a failed race read leaves the plan without its race row',
      (tester) async {
    final races = _FakeRaces(fail: true);
    await _pump(
      tester,
      training: _FakeTraining(raceListingId: _listingId),
      races: races,
    );

    expect(races.calls, 1);
    expect(find.byKey(const Key('planDetailLinkedRace')), findsNothing);
    expect(find.text('Richmond build'), findsWidgets);
  });
}
