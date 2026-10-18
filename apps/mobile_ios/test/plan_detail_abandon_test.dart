// Plan detail's app-bar menu: Abandon for an active or paused plan, and the
// coach's profile on a coach-assigned one.

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

class _FakeTraining extends TrainingService {
  String status;
  final String? coachId;
  final Object? updateError;
  final statusCalls = <(String, String)>[];
  int fetchCalls = 0;

  _FakeTraining({this.status = 'active', this.coachId, this.updateError});

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
      plan: TrainingPlanRow(
        id: 'plan-1',
        userId: _owner,
        name: 'Spring Half',
        goalEvent: 'distance_half',
        goalDistanceM: 21097.5,
        startDate: DateTime(2026, 3, 9),
        endDate: DateTime(2026, 3, 22),
        daysPerWeek: 4,
        status: status,
        source: 'generated',
        isTemplate: false,
        isPublicTemplate: false,
        assignedByCoachId: coachId,
      ),
      weeks: const [
        PlanWeekRow(id: 'w1', planId: 'plan-1', weekIndex: 0, phase: 'base'),
      ],
      workouts: [
        PlanWorkoutRow(
          id: 'wo-1',
          weekId: 'w1',
          scheduledDate: DateTime(2026, 3, 12),
          kind: 'easy',
          targetDistanceM: 6000,
          manuallyCompleted: false,
        ),
      ],
    );
  }

  @override
  Future<void> updateStatus(String id, String status) async {
    statusCalls.add((id, status));
    if (updateError != null) throw updateError!;
    this.status = status;
  }

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

Future<void> _pump(WidgetTester tester, _FakeTraining training,
    {String viewerId = _owner, List<String>? opened}) async {
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
        viewerIdOverride: viewerId,
        now: () => _today,
        cyclePlanConfig: () => null,
        openProfileOverride: (_, id) => opened?.add(id),
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

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('planDetailMenu')));
  await tester.pumpAndSettle();
}

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('abandon', () {
    for (final status in ['active', 'paused']) {
      testWidgets('is offered on an $status plan', (tester) async {
        await _pump(tester, _FakeTraining(status: status));
        await _openMenu(tester);
        expect(find.byKey(const Key('planDetailMenuAbandon')), findsOneWidget);
      });
    }

    for (final status in ['completed', 'abandoned']) {
      testWidgets('is not offered on a $status plan', (tester) async {
        await _pump(tester, _FakeTraining(status: status));
        await _openMenu(tester);
        expect(find.byKey(const Key('planDetailMenuAbandon')), findsNothing);
        expect(find.text('Delete plan'), findsOneWidget);
      });
    }

    testWidgets('a viewer who does not own the plan gets no menu at all',
        (tester) async {
      await _pump(tester, _FakeTraining(), viewerId: 'someone-else');
      expect(find.byKey(const Key('planDetailMenu')), findsNothing);
      expect(find.text('Abandon plan'), findsNothing);
    });

    testWidgets('confirms with what is kept; cancel changes nothing',
        (tester) async {
      final training = _FakeTraining(status: 'paused');
      await _pump(tester, training);
      await _openMenu(tester);
      await tester.tap(find.text('Abandon plan'));
      await tester.pumpAndSettle();

      expect(_inDialog('Abandon "Spring Half"?'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching:
                  find.textContaining('weeks, workouts and linked runs are kept')),
          findsOneWidget);

      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();
      expect(training.statusCalls, isEmpty);
      expect(find.byKey(const Key('planDetailPaused')), findsOneWidget);
    });

    testWidgets('confirming abandons the plan and the screen follows',
        (tester) async {
      final training = _FakeTraining(status: 'paused');
      await _pump(tester, training);
      expect(find.byKey(const Key('planDetailPaused')), findsOneWidget);
      final loads = training.fetchCalls;

      await _openMenu(tester);
      await tester.tap(find.text('Abandon plan'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Abandon'));
      await tester.runAsync(() => pumpUntil(
            tester,
            () => training.fetchCalls > loads,
            describe: 'the reload after abandoning',
          ));
      await tester.pumpAndSettle();

      expect(training.statusCalls, [('plan-1', 'abandoned')]);
      expect(find.byKey(const Key('planDetailPaused')), findsNothing);
      await _openMenu(tester);
      expect(find.byKey(const Key('planDetailMenuAbandon')), findsNothing);
    });

    testWidgets('a failed abandon says so and leaves the plan as it was',
        (tester) async {
      final training =
          _FakeTraining(status: 'active', updateError: Exception('offline'));
      await _pump(tester, training);
      await _openMenu(tester);
      await tester.tap(find.text('Abandon plan'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Abandon'));
      await tester.pumpAndSettle();

      expect(training.statusCalls, [('plan-1', 'abandoned')]);
      expect(training.status, 'active');
      expect(find.textContaining("Couldn't update the plan"), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await _openMenu(tester);
      expect(find.byKey(const Key('planDetailMenuAbandon')), findsOneWidget);
    });
    testWidgets('a failed abandon of a paused plan leaves it paused',
        (tester) async {
      final training =
          _FakeTraining(status: 'paused', updateError: Exception('offline'));
      await _pump(tester, training);
      expect(find.byKey(const Key('planDetailPaused')), findsOneWidget);
      await _openMenu(tester);
      await tester.tap(find.text('Abandon plan'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Abandon'));
      await tester.pumpAndSettle();

      expect(training.statusCalls, [('plan-1', 'abandoned')]);
      expect(training.status, 'paused');
      expect(find.textContaining("Couldn't update the plan"), findsOneWidget);
      expect(find.byKey(const Key('planDetailPaused')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await _openMenu(tester);
      expect(find.byKey(const Key('planDetailMenuAbandon')), findsOneWidget);
    });
  });

  group('coach', () {
    testWidgets("a coach-assigned plan's menu opens the coach's profile",
        (tester) async {
      final opened = <String>[];
      await _pump(tester, _FakeTraining(coachId: 'coach-1'), opened: opened);
      await _openMenu(tester);
      final entry = find.byKey(const Key('planDetailMenuCoach'));
      expect(entry, findsOneWidget);
      expect(
          find.descendant(of: entry, matching: find.text('Assigned by Carla')),
          findsOneWidget);

      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(opened, ['coach-1']);
    });

    testWidgets('no coach entry when the plan has no coach', (tester) async {
      await _pump(tester, _FakeTraining());
      await _openMenu(tester);
      expect(find.byKey(const Key('planDetailMenuCoach')), findsNothing);
    });

    testWidgets("no coach entry when the coach's profile cannot be resolved",
        (tester) async {
      await _pump(tester, _FakeTraining(coachId: 'coach-gone'));
      await _openMenu(tester);
      expect(find.byKey(const Key('planDetailMenuCoach')), findsNothing);
    });

    testWidgets('no coach entry when the viewer assigned the plan themselves',
        (tester) async {
      await _pump(tester, _FakeTraining(coachId: _owner));
      await _openMenu(tester);
      expect(find.byKey(const Key('planDetailMenuCoach')), findsNothing);
    });
  });
}
