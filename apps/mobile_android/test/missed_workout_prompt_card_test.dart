import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_missed_prompt.dart';
import '../lib/training_service.dart';
import '../lib/widgets/missed_workout_prompt_card.dart';

/// The Today card's "ask once" about a missed workout (decisions § 2122): what
/// it asks, which answer it recommends, and that "Let it go" records the
/// answer or says it could not.
class _Training extends TrainingService {
  _Training({this.fail = false});
  final bool fail;
  final answered = <List<String>>[];
  @override
  Future<void> answerMissedWorkouts({
    required String planId,
    required List<String> workoutIds,
    Map<String, double> distances = const {},
  }) async {
    if (fail) throw Exception('offline');
    answered.add(workoutIds);
  }
}

final DateTime _now = DateTime(2026, 3, 11, 9);

PlanWeekRow _week(String id, int idx, String phase) => PlanWeekRow(
    id: id, planId: 'p1', weekIndex: idx, phase: phase, targetVolumeM: 30000);

PlanWorkoutRow _wo(String id, String weekId, DateTime date, String kind,
        double dist,
        {bool done = false, DateTime? ack}) =>
    PlanWorkoutRow(
      id: id,
      weekId: weekId,
      scheduledDate: date,
      kind: kind,
      targetDistanceM: dist,
      manuallyCompleted: done,
      missedAckAt: ack,
    );

MissedPrompt _prompt(List<PlanWorkoutRow> workouts,
        {String phase = 'build'}) =>
    MissedWorkoutPromptCard.promptFor(
      weeks: [_week('w0', 0, phase), _week('w1', 1, phase)],
      workouts: workouts,
      now: _now,
    )!;

final _longMiss = [
  _wo('missed', 'w0', DateTime(2026, 3, 8), 'long', 16000),
  _wo('next', 'w1', DateTime(2026, 3, 15), 'long', 14000),
];

Future<AppLocalizations> _pump(
  WidgetTester tester, {
  required _Training training,
  required MissedPrompt prompt,
  VoidCallback? onMakeUp,
  Future<void> Function()? onAnswered,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: MissedWorkoutPromptCard(
        training: training,
        planId: 'p1',
        prompt: prompt,
        onMakeUp: onMakeUp,
        onAnswered: onAnswered,
      ),
    ),
  ));
  return AppLocalizations.delegate.load(const Locale('en'));
}

void main() {
  setUpAll(() => initializeDateFormatting());

  test('promptFor reads the answer off the row and asks nothing once answered',
      () {
    expect(_prompt(_longMiss).workoutId, 'missed');
    expect(
      MissedWorkoutPromptCard.promptFor(
        weeks: [_week('w0', 0, 'build'), _week('w1', 1, 'build')],
        workouts: [
          _wo('missed', 'w0', DateTime(2026, 3, 8), 'long', 16000,
              ack: DateTime(2026, 3, 9)),
          _longMiss[1],
        ],
        now: _now,
      ),
      isNull,
    );
  });

  testWidgets('a missed long run recommends making it up and hands it to the '
      'host', (tester) async {
    final training = _Training();
    var madeUp = 0;
    final l10n = await _pump(tester,
        training: training, prompt: _prompt(_longMiss), onMakeUp: () => madeUp++);

    expect(find.textContaining('Missed: Long run on'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('missedPromptBody'))).data,
      l10n.missedPromptMakeUpBody('14.0 km', '16.0 km'),
    );
    final makeUp = find.byKey(const Key('missedPromptMakeUp'));
    expect(tester.widget(makeUp), isA<FilledButton>());
    expect(
        find.descendant(
            of: makeUp, matching: find.textContaining(l10n.missedPromptRecommended)),
        findsOneWidget);
    final letGo = find.byKey(const Key('missedPromptLetGo'));
    expect(tester.widget(letGo), isA<OutlinedButton>());
    expect(
        find.descendant(
            of: letGo, matching: find.textContaining(l10n.missedPromptRecommended)),
        findsNothing);

    await tester.tap(makeUp);
    await tester.pump();
    expect(madeUp, 1);
    expect(training.answered, isEmpty,
        reason: 'the host previews the make-up and records it on apply');
  });

  testWidgets('without a host preview there is no make-up to offer',
      (tester) async {
    await _pump(tester, training: _Training(), prompt: _prompt(_longMiss));
    expect(find.byKey(const Key('missedPromptMakeUp')), findsNothing);
    expect(tester.widget(find.byKey(const Key('missedPromptLetGo'))),
        isA<FilledButton>());
  });

  testWidgets('a missed tempo is let go, recommended, and never offered as a '
      'make-up', (tester) async {
    final l10n = await _pump(tester,
        training: _Training(),
        prompt: _prompt([
          _wo('tempo', 'w1', DateTime(2026, 3, 10), 'tempo', 8000),
          _longMiss[1],
        ]),
        onMakeUp: () {});
    expect(find.byKey(const Key('missedPromptMakeUp')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('missedPromptBody'))).data,
        l10n.missedPromptLetGoBody);
    final letGo = find.byKey(const Key('missedPromptLetGo'));
    expect(tester.widget(letGo), isA<FilledButton>());
    expect(
        find.descendant(
            of: letGo, matching: find.textContaining(l10n.missedPromptRecommended)),
        findsOneWidget);
  });

  testWidgets('a missed long run in the taper says so and is let go',
      (tester) async {
    final l10n = await _pump(tester,
        training: _Training(),
        prompt: _prompt(_longMiss, phase: 'taper'),
        onMakeUp: () {});
    expect(find.byKey(const Key('missedPromptMakeUp')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('missedPromptBody'))).data,
        l10n.missedPromptTaperBody);
  });

  testWidgets('Let it go records the answer, hides the card and tells the host',
      (tester) async {
    final training = _Training();
    var told = 0;
    final l10n = await _pump(tester,
        training: training,
        prompt: _prompt([
          _wo('easy', 'w1', DateTime(2026, 3, 10), 'easy', 6000),
        ]),
        onAnswered: () async => told++);

    await tester.tap(find.byKey(const Key('missedPromptLetGo')));
    await tester.pump();
    expect(training.answered, [
      ['easy'],
    ]);
    expect(told, 1);
    expect(find.byKey(const Key('missedPrompt')), findsNothing);
    expect(find.text(l10n.missedPromptLetGoDone), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a failed answer says so and keeps the question', (tester) async {
    final training = _Training(fail: true);
    var told = 0;
    final l10n = await _pump(tester,
        training: training,
        prompt: _prompt([
          _wo('easy', 'w1', DateTime(2026, 3, 10), 'easy', 6000),
        ]),
        onAnswered: () async => told++);

    await tester.tap(find.byKey(const Key('missedPromptLetGo')));
    await tester.pump();
    expect(told, 0);
    expect(find.byKey(const Key('missedPrompt')), findsOneWidget);
    expect(find.textContaining(l10n.missedPromptSaveFailed('').trim()),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('missedPromptLetGo')))
            .onPressed,
        isNotNull,
        reason: 'the runner can try again');
    await tester.pump(const Duration(seconds: 6));
  });
}
