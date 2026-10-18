// Plan detail's failure paths and the library publish toggle (#1186
// Robustness: "error and timeout states", "publish / unpublish UI on plan
// detail"). The layout suite only proves the toggle renders; these drive it.

import 'dart:async';
import 'dart:io';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

const _owner = 'owner-uuid';
final DateTime _today = DateTime(2026, 3, 11);

final _plan = TrainingPlanRow(
  id: 'plan-1',
  userId: _owner,
  name: 'Spring Half',
  goalEvent: 'distance_half',
  goalDistanceM: 21097.5,
  startDate: _today,
  endDate: _today.add(const Duration(days: 6)),
  daysPerWeek: 4,
  status: 'active',
  source: 'generated',
  rules: const [],
  isTemplate: false,
  isPublicTemplate: false,
);

class _FakeTraining extends TrainingService {
  /// What each `fetchPlan` call does, in order; the last one repeats.
  final List<Object?> loads;
  List<TrainingPlanRow> published;
  Object? publishError;
  Object? unpublishError;
  int fetchCalls = 0;
  final publishCalls = <String>[];
  final unpublishCalls = <String>[];

  _FakeTraining({
    this.loads = const [null],
    this.published = const [],
  });

  @override
  Future<
    ({
      TrainingPlanRow? plan,
      List<PlanWeekRow> weeks,
      List<PlanWorkoutRow> workouts,
    })
  >
  fetchPlan(String id) async {
    final outcome = loads[fetchCalls.clamp(0, loads.length - 1)];
    fetchCalls++;
    if (outcome != null) throw outcome;
    return (
      plan: _plan,
      weeks: const [
        PlanWeekRow(id: 'w1', planId: 'plan-1', weekIndex: 0, phase: 'base'),
      ],
      workouts: <PlanWorkoutRow>[],
    );
  }

  @override
  Future<List<TrainingPlanRow>> fetchMyPublishedPlans() async => published;

  @override
  Future<String> publishPlanToLibrary({required String planId}) async {
    publishCalls.add(planId);
    if (publishError != null) throw publishError!;
    return 'template-1';
  }

  @override
  Future<void> unpublishFromLibrary(String templateId) async {
    unpublishCalls.add(templateId);
    if (unpublishError != null) throw unpublishError!;
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
      home: PlanDetailScreen(
        training: training,
        planId: 'plan-1',
        social: _FakeSocial(),
        viewerIdOverride: _owner,
        now: () => _today,
      ),
    ),
  );
  await pumpUntil(
    tester,
    () => !tester.any(find.byType(FullBodyLoader)),
    describe: 'the plan fetch to settle',
  );
  await tester.pump();
}

/// Lets a top banner's dismiss timer run out so the test ends with none
/// pending.
Future<void> _drainBanner(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 4));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final en = lookupAppLocalizations(const Locale('en'));

  group('load failures', () {
    testWidgets('a failed load says so, not "not found", and retry recovers',
        (tester) async {
      final training = _FakeTraining(loads: [Exception('boom'), null]);
      await _pump(tester, training);

      expect(find.text(en.planDetailLoadError), findsOneWidget);
      expect(find.text(en.planDetailNotFound), findsNothing);

      await tester.tap(find.text(en.errorStateRetry));
      await pumpUntil(
        tester,
        () => tester.any(find.text('Spring Half')),
        describe: 'the retried load to render the plan',
      );
      expect(training.fetchCalls, 2);
      expect(find.text(en.planDetailLoadError), findsNothing);
    });

    testWidgets('a timed-out load names the connection, not a generic failure',
        (tester) async {
      await _pump(
          tester, _FakeTraining(loads: [TimeoutException('slow link')]));

      expect(find.text(en.planDetailTimeoutError), findsOneWidget);
      expect(find.text(en.planDetailLoadError), findsNothing);
      expect(find.text(en.errorStateRetry), findsOneWidget);
    });
  });

  group('a refresh over a plan already on screen', () {
    Future<void> pullToRefresh(WidgetTester tester) async {
      // The test surface is tall enough that the list cannot be dragged, so
      // the indicator is fired the way a pull would fire it.
      unawaited(tester
          .state<RefreshIndicatorState>(find.byType(RefreshIndicator).first)
          .show());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }

    testWidgets('a failed refresh keeps the plan and says it is stale',
        (tester) async {
      final training = _FakeTraining(loads: [null, Exception('boom')]);
      await _pump(tester, training);
      await pullToRefresh(tester);

      expect(training.fetchCalls, 2);
      expect(find.text('Spring Half'), findsWidgets);
      expect(find.text(en.commonStaleRefreshFailed), findsOneWidget);
      expect(find.text(en.planDetailLoadError), findsNothing);
      expect(find.byType(FullBodyLoader), findsNothing);
      await _drainBanner(tester);
    });

    testWidgets('offline, the banner says so', (tester) async {
      final training =
          _FakeTraining(loads: [null, const SocketException('no route')]);
      await _pump(tester, training);
      await pullToRefresh(tester);

      expect(find.text('Spring Half'), findsWidgets);
      expect(find.text(en.commonStaleOffline), findsOneWidget);
      await _drainBanner(tester);
    });
  });

  testWidgets('a first load offline says offline, not a generic failure',
      (tester) async {
    await _pump(tester,
        _FakeTraining(loads: [const SocketException('no route')]));
    expect(find.text(en.authErrorOffline), findsOneWidget);
    expect(find.text(en.planDetailLoadError), findsNothing);
  });

  group('library publish toggle', () {
    testWidgets('publishing calls the service and flips to Unpublish',
        (tester) async {
      final training = _FakeTraining();
      await _pump(tester, training);

      await tester.tap(find.text(en.planDetailPublishLibrary));
      await tester.pump();
      await tester.pump();

      expect(training.publishCalls, ['plan-1']);
      expect(find.text(en.planDetailUnpublishLibrary), findsOneWidget);
      expect(find.text(en.planDetailAlreadyPublished), findsOneWidget);
      expect(find.text(en.planDetailPublishLibrarySuccess), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('an already-published plan opens on Unpublish, and it unpublishes',
        (tester) async {
      final training = _FakeTraining(published: [
        _plan.copyWith(id: 'template-9', isPublicTemplate: true),
      ]);
      await _pump(tester, training);
      expect(find.text(en.planDetailUnpublishLibrary), findsOneWidget);

      await tester.tap(find.text(en.planDetailUnpublishLibrary));
      await tester.pump();
      await tester.pump();

      expect(training.unpublishCalls, ['template-9']);
      expect(find.text(en.planDetailPublishLibrary), findsOneWidget);
      expect(find.text(en.planDetailUnpublishSuccess), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('a failed publish says so and leaves the toggle where it was',
        (tester) async {
      final training = _FakeTraining()..publishError = Exception('refused');
      await _pump(tester, training);

      await tester.tap(find.text(en.planDetailPublishLibrary));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Failed to publish'), findsOneWidget);
      expect(find.text(en.planDetailPublishLibrary), findsOneWidget);
      expect(find.text(en.planDetailUnpublishLibrary), findsNothing);
      await _drainBanner(tester);
    });

    testWidgets('a failed unpublish says so and keeps the plan published',
        (tester) async {
      final training = _FakeTraining(published: [
        _plan.copyWith(id: 'template-9', isPublicTemplate: true),
      ])
        ..unpublishError = Exception('refused');
      await _pump(tester, training);

      await tester.tap(find.text(en.planDetailUnpublishLibrary));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Failed to unpublish'), findsOneWidget);
      expect(find.text(en.planDetailUnpublishLibrary), findsOneWidget);
      await _drainBanner(tester);
    });
  });
}
