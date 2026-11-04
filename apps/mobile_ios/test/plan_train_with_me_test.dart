import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/race_service.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/screens/plan_library_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/error_state.dart';
import '../lib/widgets/loading_skeletons.dart';
import 'pump_until.dart';

// "Train with me" (decisions § 2262): a creator's /share/plan/<id> link opens
// the library preview by id, and the copy a follower starts names whose plan
// it came from.

const _owner = 'owner-uuid';
const _creator = 'creator-uuid';
const _templateId = '0b6f2f4e-8c1d-4a7e-9f3b-2d5c6a7b8c9d';

final DateTime _today = DateTime(2026, 3, 11);

DateTime get _monday =>
    _today.subtract(Duration(days: _today.weekday - DateTime.monday));

TrainingPlanRow _template() => TrainingPlanRow(
      id: _templateId,
      userId: _creator,
      name: 'Spring marathon block',
      goalEvent: 'distance_full',
      goalDistanceM: 42195,
      startDate: DateTime(2026, 3, 2),
      endDate: DateTime(2026, 5, 24),
      daysPerWeek: 5,
      status: 'completed',
      source: 'manual',
      isTemplate: true,
      isPublicTemplate: true,
    );

class _FakeTraining extends TrainingService {
  _FakeTraining({
    this.entry,
    this.failEntry = false,
    this.sourceAuthorId,
    this.startedFrom,
  });

  final PublicPlanLibraryEntry? entry;
  final bool failEntry;
  final String? sourceAuthorId;
  final PlanStartedFrom? startedFrom;
  int entryCalls = 0;
  int startedFromCalls = 0;

  @override
  String? get currentUserId => _owner;

  @override
  Future<PublicPlanLibraryEntry?> fetchPublicPlanLibraryEntry(String id) async {
    entryCalls++;
    if (failEntry) throw Exception('network down');
    return entry;
  }

  @override
  Future<PlanStartedFrom?> fetchPlanStartedFrom(String planId) async {
    startedFromCalls++;
    return startedFrom;
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
    plan: TrainingPlanRow(
      id: 'plan-1',
      userId: _owner,
      name: 'Spring marathon block',
      goalEvent: 'distance_full',
      goalDistanceM: 42195,
      startDate: _monday,
      endDate: _monday.add(const Duration(days: 13)),
      daysPerWeek: 4,
      status: 'active',
      source: 'manual',
      rules: const [],
      isTemplate: false,
      isPublicTemplate: false,
      parentTemplateId: _templateId,
      sourceAuthorId: sourceAuthorId,
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
    workouts: const <PlanWorkoutRow>[],
  );

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
  @override
  Future<RaceListingView?> fetchRaceListing(String id) async => null;
}

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

Future<void> _pumpDetail(WidgetTester tester, _FakeTraining training) async {
  tester.view.physicalSize = const Size(420, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(PlanDetailScreen(
    training: training,
    planId: 'plan-1',
    social: _FakeSocial(),
    viewerIdOverride: _owner,
    now: () => _today,
    raceService: _FakeRaces(),
  )));
  await pumpUntil(
    tester,
    () => !tester.any(find.byType(SectionedDetailSkeleton)),
    describe: 'the plan fetch to replace the full-body loader',
  );
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PlanStartedFrom', () {
    test('reads the RPC document and credits the handle first', () {
      final from = PlanStartedFrom.fromJson({
        'author': {'name': 'Creator Cat', 'handle': 'creatorcat'},
        'template_id': _templateId,
      })!;
      expect(from.credit, '@creatorcat');
      expect(from.templateId, _templateId);
      expect(
        const PlanStartedFrom(authorName: 'Creator Cat').credit,
        'Creator Cat',
      );
      expect(const PlanStartedFrom(authorName: '  ').credit, isNull);
      expect(PlanStartedFrom.fromJson({'author': null})!.credit, isNull);
      expect(PlanStartedFrom.fromJson(null), isNull);
      expect(PlanStartedFrom.fromJson('x'), isNull);
    });
  });

  group('PlanLibraryLinkScreen', () {
    testWidgets('a Train with me link opens the library preview by id',
        (tester) async {
      final training = _FakeTraining(
        entry: PublicPlanLibraryEntry(
          plan: _template(),
          authorHandle: 'Creator Cat',
        ),
      );
      await tester.pumpWidget(_app(
          PlanLibraryLinkScreen(training: training, planId: _templateId)));
      await tester.pump();
      await tester.pump();

      expect(training.entryCalls, 1);
      expect(find.byType(PlanLibraryPreviewScreen), findsOneWidget);
      expect(find.text('Spring marathon block'), findsWidgets);
      expect(find.text('by Creator Cat'), findsOneWidget);
    });

    testWidgets('a plan no longer in the library says so', (tester) async {
      await tester.pumpWidget(_app(PlanLibraryLinkScreen(
          training: _FakeTraining(), planId: _templateId)));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('planLibraryLinkNotFound')), findsOneWidget);
      expect(find.text('This plan is no longer in the public library.'),
          findsOneWidget);
      expect(find.byType(PlanLibraryPreviewScreen), findsNothing);
    });

    testWidgets('a failed read offers a retry rather than a not-found',
        (tester) async {
      final training = _FakeTraining(failEntry: true);
      await tester.pumpWidget(_app(
          PlanLibraryLinkScreen(training: training, planId: _templateId)));
      await tester.pump();
      await tester.pump();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.byKey(const Key('planLibraryLinkNotFound')), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(training.entryCalls, 2);
    });
  });

  group('PlanDetailScreen attribution', () {
    testWidgets('a copy of a public plan names the creator it started from',
        (tester) async {
      final training = _FakeTraining(
        sourceAuthorId: _creator,
        startedFrom: const PlanStartedFrom(
          authorName: 'Creator Cat',
          authorHandle: 'creatorcat',
          templateId: _templateId,
        ),
      );
      await _pumpDetail(tester, training);

      final row = find.byKey(const Key('planDetailStartedFrom'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(
            of: row, matching: find.text("Started from @creatorcat's plan")),
        findsOneWidget,
      );
    });

    testWidgets('a hidden creator is not named, and the line still shows',
        (tester) async {
      await _pumpDetail(
        tester,
        _FakeTraining(
          sourceAuthorId: _creator,
          startedFrom: const PlanStartedFrom(),
        ),
      );
      expect(find.text("Started from another runner's plan"), findsOneWidget);
    });

    testWidgets('a plan nobody else wrote shows no line and reads nothing',
        (tester) async {
      final training = _FakeTraining();
      await _pumpDetail(tester, training);
      expect(find.byKey(const Key('planDetailStartedFrom')), findsNothing);
      expect(training.startedFromCalls, 0);
    });
  });
}
