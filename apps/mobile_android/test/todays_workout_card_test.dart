import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/todays_workout_card.dart';

PlanWorkoutRow _workout({
  String kind = 'tempo',
  double? targetDistanceM = 8000,
  int? targetPaceSecPerKm = 330,
  String? completedRunId,
  DateTime? skippedAt,
}) =>
    PlanWorkoutRow(
      id: 'wo1',
      weekId: 'wk1',
      scheduledDate: DateTime(2026, 4, 25),
      kind: kind,
      targetDistanceM: targetDistanceM,
      targetPaceSecPerKm: targetPaceSecPerKm,
      completedRunId: completedRunId,
      skippedAt: skippedAt,
      manuallyCompleted: false,
    );

Future<void> _pump(
  WidgetTester tester,
  PlanWorkoutRow workout, {
  VoidCallback? onTap,
  VoidCallback? onStart,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TodaysWorkoutCard(
          workout: workout,
          onTap: onTap,
          onStart: onStart,
        ),
      ),
    ),
  );
}

void main() {
  group('TodaysWorkoutCard', () {
    testWidgets('renders "TODAY\'S WORKOUT" label for an incomplete workout',
        (tester) async {
      await _pump(tester, _workout());
      expect(find.text("TODAY'S WORKOUT"), findsOneWidget);
    });

    testWidgets('renders "DONE TODAY" label for a completed workout',
        (tester) async {
      await _pump(tester, _workout(completedRunId: 'run-1'));
      expect(find.text('DONE TODAY'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('renders the workout kind label', (tester) async {
      await _pump(tester, _workout(kind: 'tempo'));
      expect(find.text('Tempo'), findsOneWidget);
    });

    testWidgets('renders target distance when provided', (tester) async {
      await _pump(tester, _workout(targetDistanceM: 8000));
      expect(find.textContaining('8'), findsAtLeastNWidgets(1));
    });

    testWidgets('calls onTap when the card is tapped', (tester) async {
      var taps = 0;
      await _pump(tester, _workout(), onTap: () => taps++);
      await tester.tap(find.byType(TodaysWorkoutCard));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('distance + pace targets survive a narrow width without '
        'overflowing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: TodaysWorkoutCard(workout: _workout()),
              ),
            ),
          ),
        ),
      );
      // Both targets render in a Wrap; at 200 the pace chip flows to a
      // second line (ellipsizing if still too wide) instead of throwing a
      // RenderFlex overflow (the harness fails the test on one).
      expect(find.byIcon(Icons.straighten), findsOneWidget);
      expect(find.textContaining('@'), findsOneWidget);
    });

    testWidgets('a 2.0x text scale on a 320 dp phone reflows instead of '
        'overflowing', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TodaysWorkoutCard(
                    workout: _workout(completedRunId: 'run-1')),
              ],
            ),
          ),
        ),
      );
      // Plan detail's own card put distance, pace and "Completed" in a Row
      // with two inflexible texts, which overflowed here; the shared card
      // keeps the targets in a Wrap. The harness fails on a RenderFlex
      // overflow, so reaching these lines is the assertion.
      expect(find.byIcon(Icons.straighten), findsOneWidget);
      expect(find.byIcon(Icons.speed), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    group('Start button', () {
      final start = find.byKey(const Key('todaysWorkoutStart'));

      testWidgets('shows for an open workout and starts it, not the tap',
          (tester) async {
        var starts = 0;
        var taps = 0;
        await _pump(tester, _workout(),
            onTap: () => taps++, onStart: () => starts++);
        expect(start, findsOneWidget);
        expect(find.text('Start workout'), findsOneWidget);
        await tester.tap(start);
        await tester.pump();
        expect(starts, 1);
        expect(taps, 0);
      });

      testWidgets('is hidden once the workout is done', (tester) async {
        await _pump(tester, _workout(completedRunId: 'run-1'),
            onStart: () {});
        expect(start, findsNothing);
      });

      testWidgets('is hidden for a skipped workout', (tester) async {
        await _pump(tester, _workout(skippedAt: DateTime(2026, 4, 25)),
            onStart: () {});
        expect(start, findsNothing);
      });

      testWidgets('is absent when the surface passes no onStart (Home)',
          (tester) async {
        await _pump(tester, _workout());
        expect(start, findsNothing);
      });
    });

    testWidgets('reads as one button whose label carries the whole card',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _workout(), onTap: () {});
      final node = tester.getSemantics(find.bySemanticsLabel(
          RegExp(r"^TODAY'S WORKOUT, Tempo, 8.*, @ 5:30")));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });
  });
}
