import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

/// Plan detail hosts the missed-workout prompt in its Today slot (decisions
/// § 2122): only for the owner of an active plan, "Make it up" previews the
/// stretched long run like a re-plan, and applying it writes the stretch and
/// the answer through `answer_missed_workouts`, not the plain re-plan path.

const _uid = 'owner-uuid';

/// A Wednesday. The plan started two Mondays before the previous one, so the
/// missed long run (last Sunday) sits in a finished week and the next long
/// run (this Sunday) is still to come.
final DateTime _today = DateTime(2026, 3, 11);
final DateTime _start = DateTime(2026, 2, 23);

class _Training extends TrainingService {
  _Training(this.plan, {this.fail = false, this.missedM = 16000});
  final TrainingPlanRow plan;
  final bool fail;
  final double missedM;
  final answers = <({List<String> ids, Map<String, double> distances})>[];
  final replans = <Map<String, double>>[];

  @override
  Future<
      ({
        TrainingPlanRow? plan,
        List<PlanWeekRow> weeks,
        List<PlanWorkoutRow> workouts
      })> fetchPlan(String id) async {
    PlanWeekRow week(int i) => PlanWeekRow(
        id: 'w$i',
        planId: plan.id,
        weekIndex: i,
        phase: 'build',
        targetVolumeM: 30000);
    final answered = answers.expand((a) => a.ids).toSet();
    final stretched = {for (final a in answers) ...a.distances};
    return (
      plan: plan,
      weeks: [for (var i = 0; i < 4; i++) week(i)],
      workouts: [
        PlanWorkoutRow(
          id: 'missed',
          weekId: 'w1',
          scheduledDate: DateTime(2026, 3, 8),
          kind: 'long',
          targetDistanceM: missedM,
          manuallyCompleted: false,
          missedAckAt: answered.contains('missed') ? _today : null,
        ),
        PlanWorkoutRow(
          id: 'next',
          weekId: 'w2',
          scheduledDate: DateTime(2026, 3, 15),
          kind: 'long',
          targetDistanceM: stretched['next'] ?? 14000,
          manuallyCompleted: false,
        ),
      ],
    );
  }

  @override
  Future<void> answerMissedWorkouts({
    required String planId,
    required List<String> workoutIds,
    Map<String, double> distances = const {},
  }) async {
    if (fail) throw Exception('offline');
    answers.add((ids: workoutIds, distances: distances));
  }

  @override
  Future<void> applyReplan({
    required String planId,
    required Map<String, double> distances,
  }) async {
    replans.add(distances);
  }
}

class _Social extends SocialService {
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async =>
      const [];
}

TrainingPlanRow _plan({String status = 'active'}) => TrainingPlanRow(
      id: 'plan-1',
      userId: _uid,
      name: 'Spring Half',
      goalEvent: 'distance_half',
      goalDistanceM: 21097.5,
      startDate: _start,
      endDate: _start.add(const Duration(days: 55)),
      daysPerWeek: 4,
      status: status,
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
    );

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _Training training, {
  String viewerId = _uid,
  bool openMakeUp = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: PlanDetailScreen(
      training: training,
      planId: 'plan-1',
      social: _Social(),
      viewerIdOverride: viewerId,
      now: () => _today,
      openMakeUp: openMakeUp,
    ),
  ));
  await pumpUntil(tester, () => !tester.any(find.byType(FullBodyLoader)),
      describe: 'the plan fetch to replace the full-body loader');
  await tester.pump();
  return AppLocalizations.delegate.load(const Locale('en'));
}

Finder _preview(AppLocalizations l10n) =>
    find.text(l10n.planDetailReplanMakeUp('14.0 km', '16.0 km'));

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

/// The list builds lazily, so a card scrolled past is gone from the tree.
Future<void> _scrollBackTo(WidgetTester tester, Finder f) =>
    tester.scrollUntilVisible(f, -200,
        scrollable: find.byType(Scrollable).first);

/// Adjust plan, then its Re-plan option. The dialog title and the page's
/// button share a label, so the option is found inside the dialog.
Future<void> _chooseReplan(WidgetTester tester, AppLocalizations l10n) async {
  final adjust = find.text(l10n.planDetailAdjustPlan);
  if (!tester.any(adjust)) await _scrollBackTo(tester, adjust);
  await _tapVisible(tester, adjust.first);
  await tester.pump(const Duration(milliseconds: 400));
  final option = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(l10n.planDetailReplan));
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('Make it up previews the stretch and applies it with the answer',
      (tester) async {
    final training = _Training(_plan());
    final l10n = await _pump(tester, training);

    expect(find.byKey(const ValueKey('planDetailMissedPrompt-missed')),
        findsOneWidget);
    expect(_preview(l10n), findsNothing);

    await _tapVisible(tester, find.byKey(const Key('missedPromptMakeUp')));
    expect(_preview(l10n), findsOneWidget);
    expect(training.answers, isEmpty,
        reason: 'nothing is written until the runner accepts the preview');

    await _tapVisible(tester, find.text(l10n.planDetailReplanApply));
    await pumpUntil(tester, () => training.answers.isNotEmpty,
        describe: 'the make-up to be applied');
    expect(training.answers.single.ids, ['missed']);
    expect(training.answers.single.distances, {'next': 16000.0});
    expect(training.replans, isEmpty,
        reason: 'the make-up goes through answer_missed_workouts');
    await pumpUntil(
        tester,
        () => !tester
            .any(find.byKey(const ValueKey('planDetailMissedPrompt-missed'))),
        describe: 'the answered prompt to go away');
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('cancelling the preview records nothing and keeps the question',
      (tester) async {
    final training = _Training(_plan());
    final l10n = await _pump(tester, training);
    await _tapVisible(tester, find.byKey(const Key('missedPromptMakeUp')));
    await _tapVisible(tester, find.text(l10n.planDetailReplanCancel));
    expect(_preview(l10n), findsNothing);
    expect(training.answers, isEmpty);
    expect(training.replans, isEmpty);
    await _scrollBackTo(
        tester, find.byKey(const ValueKey('planDetailMissedPrompt-missed')));
    expect(find.byKey(const ValueKey('planDetailMissedPrompt-missed')),
        findsOneWidget);
  });

  testWidgets('a failed make-up says so', (tester) async {
    final training = _Training(_plan(), fail: true);
    final l10n = await _pump(tester, training);
    await _tapVisible(tester, find.byKey(const Key('missedPromptMakeUp')));
    await _tapVisible(tester, find.text(l10n.planDetailReplanApply));
    await pumpUntil(
        tester,
        () => tester.any(find.textContaining(
            l10n.missedPromptSaveFailed('').trim())),
        describe: 'the failure banner');
    await _scrollBackTo(
        tester, find.byKey(const ValueKey('planDetailMissedPrompt-missed')));
    expect(find.byKey(const ValueKey('planDetailMissedPrompt-missed')),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets("Home's Make it up opens the preview on arrival", (tester) async {
    final training = _Training(_plan());
    final l10n = await _pump(tester, training, openMakeUp: true);
    await tester.pump();
    expect(_preview(l10n), findsOneWidget);
    expect(training.answers, isEmpty);
  });

  // A make-up the runner already accepted is answered (`missed_ack_at`), so
  // no re-plan may stretch the same long run for it again (decisions § 2125).
  testWidgets('after Make it up is applied, Re-plan proposes no second stretch',
      (tester) async {
    final training = _Training(_plan(), missedM: 20000);
    final l10n = await _pump(tester, training);
    await _tapVisible(tester, find.byKey(const Key('missedPromptMakeUp')));
    await _tapVisible(tester, find.text(l10n.planDetailReplanApply));
    await pumpUntil(tester, () => training.answers.isNotEmpty,
        describe: 'the make-up to be applied');
    expect(training.answers.single.distances, {'next': 16100.0});
    await pumpUntil(
        tester,
        () => !tester
            .any(find.byKey(const ValueKey('planDetailMissedPrompt-missed'))),
        describe: 'the reload after the make-up');
    await tester.pump(const Duration(seconds: 6));

    await _chooseReplan(tester, l10n);
    expect(find.text(l10n.planDetailReplanOnTrack), findsOneWidget);
    expect(find.text(l10n.planDetailReplanPreviewTitle), findsNothing);
    expect(training.replans, isEmpty);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets(
      'a Re-plan opened over an unapplied make-up applies as a re-plan, '
      'not as an answer', (tester) async {
    final training = _Training(_plan());
    final l10n = await _pump(tester, training);
    await _tapVisible(tester, find.byKey(const Key('missedPromptMakeUp')));
    expect(_preview(l10n), findsOneWidget);

    await _chooseReplan(tester, l10n);
    expect(_preview(l10n), findsOneWidget);
    await _tapVisible(tester, find.text(l10n.planDetailReplanApply));
    await pumpUntil(tester, () => training.replans.isNotEmpty,
        describe: 'the re-plan to be applied');
    expect(training.replans.single, {'next': 16000.0});
    expect(training.answers, isEmpty,
        reason: 'only the make-up preview answers the missed workout');
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a paused plan asks nothing', (tester) async {
    await _pump(tester, _Training(_plan(status: 'paused')));
    expect(find.byKey(const Key('missedPrompt')), findsNothing);
  });

  testWidgets('a coach reading an athlete plan is never asked', (tester) async {
    await _pump(tester, _Training(_plan()), viewerId: 'coach-uuid');
    expect(find.byKey(const Key('missedPrompt')), findsNothing);
  });
}
