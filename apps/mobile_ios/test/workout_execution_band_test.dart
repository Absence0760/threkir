import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/widgets/workout_execution_band.dart';
import 'package:run_recorder/run_recorder.dart';

WorkoutStep _step({
  WorkoutStepKind kind = WorkoutStepKind.rep,
  String label = 'Rep 3/6',
  double distance = 400,
  int pace = 240,
  int? repIndex = 3,
  int? repTotal = 6,
}) =>
    WorkoutStep(
      kind: kind,
      targetDistanceMetres: distance,
      targetPaceSecPerKm: pace,
      label: label,
      repIndex: repIndex,
      repTotal: repTotal,
    );

WorkoutStep _durStep({
  String label = 'Stride',
  int durationSec = 30,
  int pace = 240,
}) =>
    WorkoutStep(
      kind: WorkoutStepKind.rep,
      targetDistanceMetres: 0,
      targetDurationSec: durationSec,
      targetPaceSecPerKm: pace,
      label: label,
    );

Future<void> _pumpBand(
  WidgetTester tester, {
  required WorkoutBandState state,
  VoidCallback? onSkip,
  VoidCallback? onRewind,
  VoidCallback? onAbandon,
  String? effortTarget,
}) {
  final notifier = ValueNotifier<WorkoutBandState>(state);
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: WorkoutExecutionBand(
          state: notifier,
          onSkip: onSkip ?? () {},
          onRewind: onRewind ?? () {},
          onAbandon: onAbandon ?? () {},
          effortTarget: effortTarget,
        ),
      ),
    ),
  );
}

void main() {
  group('WorkoutExecutionBand', () {
    testWidgets('renders nothing when state is empty (no step + not complete)',
        (tester) async {
      await _pumpBand(tester, state: WorkoutBandState.empty);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Rewind'), findsNothing);
    });

    testWidgets('renders step label, target distance, target pace, and m-to-go',
        (tester) async {
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 14,
          currentIndex: 4,
          progress: 0.25,
          remainingMetres: 300,
          actualPaceSecPerKm: 235,
          adherence: PaceAdherence.ahead,
          complete: false,
          abandoned: false,
        ),
      );
      // Header line: "Rep 3 of 6 · 400 m @ 4:00/km", the step named in the
      // runner's language rather than the expander's English label.
      expect(find.textContaining('Rep 3 of 6'), findsOneWidget);
      expect(find.textContaining('400 m'), findsOneWidget);
      expect(find.textContaining('4:00/km'), findsOneWidget);
      // Step counter and remaining-distance footer.
      expect(find.text('5/14'), findsOneWidget);
      expect(find.text('300 m to go'), findsOneWidget);
      // Pace pip shows signed delta.
      expect(find.text('−5s'), findsOneWidget);
    });

    testWidgets('carries the workout\'s effort target line (decisions § 2092)',
        (tester) async {
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 14,
          currentIndex: 4,
          progress: 0.25,
          remainingMetres: 300,
          actualPaceSecPerKm: 235,
          adherence: PaceAdherence.ahead,
          complete: false,
          abandoned: false,
        ),
        effortTarget: 'Effort 3–4/10 · Cap 125 bpm',
      );
      expect(find.byKey(const Key('workoutBandEffortTarget')), findsOneWidget);
      expect(find.text('Effort 3–4/10 · Cap 125 bpm'), findsOneWidget);
    });

    testWidgets('Skip and Abandon trigger callbacks', (tester) async {
      var skips = 0;
      var abandons = 0;
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 3,
          currentIndex: 0,
          progress: 0.5,
          remainingMetres: 200,
          actualPaceSecPerKm: 240,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
        onSkip: () => skips++,
        onAbandon: () => abandons++,
      );

      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(skips, 1);

      // Abandon lives in the overflow menu, not on the card.
      expect(find.text('Abandon'), findsNothing);
      await tester.tap(find.byTooltip('More workout actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abandon'));
      await tester.pumpAndSettle();
      expect(abandons, 1);
    });

    testWidgets('Rewind is disabled on the first step', (tester) async {
      var rewinds = 0;
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 3,
          currentIndex: 0,
          progress: 0.5,
          remainingMetres: 200,
          actualPaceSecPerKm: 240,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
        onRewind: () => rewinds++,
      );
      final rewindBtn = find.byKey(const Key('workoutBandRewind'));
      expect(rewindBtn, findsOneWidget);
      // onPressed is null on the first step → button is disabled, taps no-op.
      await tester.tap(rewindBtn, warnIfMissed: false);
      await tester.pump();
      expect(rewinds, 0,
          reason: 'Rewind button must be disabled when currentIndex == 0');
    });

    testWidgets('Rewind triggers callback once advanced past first step',
        (tester) async {
      var rewinds = 0;
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 3,
          currentIndex: 1,
          progress: 0.1,
          remainingMetres: 360,
          actualPaceSecPerKm: 240,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
        onRewind: () => rewinds++,
      );
      await tester.tap(find.byTooltip('Rewind'));
      await tester.pump();
      expect(rewinds, 1);
    });

    testWidgets('renders the workout-complete shell when step is null + complete',
        (tester) async {
      await _pumpBand(
        tester,
        state: const WorkoutBandState(
          step: null,
          totalSteps: 6,
          currentIndex: 6,
          progress: 1,
          remainingMetres: 0,
          actualPaceSecPerKm: null,
          adherence: PaceAdherence.onPace,
          complete: true,
          abandoned: false,
        ),
      );
      expect(find.textContaining('Workout complete'), findsOneWidget);
      // Controls hidden in complete state.
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Rewind'), findsNothing);
      expect(find.text('Abandon'), findsNothing);
    });

    testWidgets('renders the abandoned shell', (tester) async {
      await _pumpBand(
        tester,
        state: const WorkoutBandState(
          step: null,
          totalSteps: 6,
          currentIndex: 2,
          progress: 0,
          remainingMetres: 0,
          actualPaceSecPerKm: null,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: true,
        ),
      );
      expect(find.textContaining('abandoned'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Rewind'), findsNothing);
    });

    testWidgets('renders duration-based target ("30s") and seconds-to-go',
        (tester) async {
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _durStep(durationSec: 30, pace: 240),
          totalSteps: 4,
          currentIndex: 1,
          progress: 0.6,
          remainingMetres: 0,
          remainingDuration: const Duration(seconds: 12),
          actualPaceSecPerKm: 245,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      // Header shows time target, not metres.
      expect(find.textContaining('Run · 30s'), findsOneWidget);
      // Distance footer is replaced by a time remainder.
      expect(find.text('12s to go'), findsOneWidget);
      expect(find.text('0 m to go'), findsNothing,
          reason: 'must not fall back to distance footer for duration steps');
    });

    testWidgets('formats longer duration remainders as "Nm Ns"',
        (tester) async {
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _durStep(durationSec: 240, pace: 240),
          totalSteps: 1,
          currentIndex: 0,
          progress: 0.1,
          remainingMetres: 0,
          remainingDuration: const Duration(seconds: 215),
          actualPaceSecPerKm: 240,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      // 4-minute step, 215 s remaining → "3m 35s to go".
      expect(find.text('3m 35s to go'), findsOneWidget);
      // Header shows the rounded target as "4m".
      expect(find.textContaining('4m'), findsOneWidget);
    });

    testWidgets('pace pip uses an em-dash when actual pace is null',
        (tester) async {
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 3,
          currentIndex: 0,
          progress: 0,
          remainingMetres: 400,
          actualPaceSecPerKm: null,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('an unpaced walk-run step shows no pace pip', (tester) async {
      await _pumpBand(
        tester,
        state: const WorkoutBandState(
          step: WorkoutStep(
            kind: WorkoutStepKind.walk,
            targetDistanceMetres: 0,
            targetDurationSec: 90,
            targetPaceSecPerKm: 300,
            label: 'Walk 1/7',
            repIndex: 1,
            repTotal: 7,
            paced: false,
          ),
          totalSteps: 17,
          currentIndex: 2,
          progress: 0.5,
          remainingMetres: 0,
          remainingDuration: Duration(seconds: 45),
          actualPaceSecPerKm: 720,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      expect(find.text('+420s'), findsNothing);
      // A walk has no pace target: the header states the walk and its length,
      // never the plan's easy pace.
      expect(find.text('Walk 1 of 7 · 1m 30s'), findsOneWidget);
      expect(find.textContaining('@'), findsNothing);
      expect(find.textContaining('5:00'), findsNothing);
      expect(find.text('45s to go'), findsOneWidget);
    });

    testWidgets('a walk-run run interval and its walking warm-up show no pace',
        (tester) async {
      for (final (step, header) in const [
        (
          WorkoutStep(
            kind: WorkoutStepKind.rep,
            targetDistanceMetres: 0,
            targetDurationSec: 60,
            targetPaceSecPerKm: 732,
            label: 'Run 2/8',
            repIndex: 2,
            repTotal: 8,
            paced: false,
          ),
          'Run 2 of 8 · 1m',
        ),
        (
          WorkoutStep(
            kind: WorkoutStepKind.warmup,
            targetDistanceMetres: 0,
            targetDurationSec: 300,
            targetPaceSecPerKm: 732,
            label: 'Warmup',
            paced: false,
          ),
          'Warm-up walk · 5m',
        ),
      ]) {
        await _pumpBand(
          tester,
          state: WorkoutBandState(
            step: step,
            totalSteps: 17,
            currentIndex: 1,
            progress: 0.2,
            remainingMetres: 0,
            remainingDuration: const Duration(seconds: 40),
            actualPaceSecPerKm: 690,
            adherence: PaceAdherence.onPace,
            complete: false,
            abandoned: false,
          ),
        );
        expect(find.text(header), findsOneWidget);
        expect(find.textContaining('12:12'), findsNothing);
      }
    });

    testWidgets('an unpaced distance step (the graduation 5K) shows no pace',
        (tester) async {
      await _pumpBand(
        tester,
        state: const WorkoutBandState(
          step: WorkoutStep(
            kind: WorkoutStepKind.rep,
            targetDistanceMetres: 5000,
            targetPaceSecPerKm: 732,
            label: 'Run 1/1',
            repIndex: 1,
            repTotal: 1,
            paced: false,
          ),
          totalSteps: 3,
          currentIndex: 1,
          progress: 0.1,
          remainingMetres: 4500,
          actualPaceSecPerKm: 700,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      expect(find.text('Run · 5.0 km'), findsOneWidget);
      expect(find.textContaining('12:12'), findsNothing);
    });
  });

  group('WorkoutExecutionBand — distance pref propagation', () {
    // The band's `_fmtDistance` was hardcoded km. Mi-mode users now
    // see miles / yards. Each test plants a Preferences in the
    // desired mode then asserts the rendered text reflects it.
    tearDown(resetActivePreferencesForTest);

    Future<void> setUnit(bool useMiles) async {
      SharedPreferences.setMockInitialValues({'use_miles': useMiles});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
    }

    testWidgets('mi mode: 400 m target renders in yards + /mi pace',
        (tester) async {
      // 400 × 1.09361 ≈ 437 yards (sub-1 mile → yards branch).
      // Both the header's distance pill AND the "to go" footer
      // render in yards; pace flips to /mi.
      await setUnit(true);
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 6,
          currentIndex: 0,
          progress: 0,
          remainingMetres: 400,
          actualPaceSecPerKm: null,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      expect(find.textContaining('437 yd'), findsAtLeastNWidgets(1));
      // Header pace also flips to /mi (was "4:00/km").
      expect(find.textContaining('/mi'), findsOneWidget);
      // Negative shape — the original "400 m" / "/km" must NOT
      // leak through.
      expect(find.textContaining('400 m'), findsNothing);
      expect(find.textContaining('/km'), findsNothing);
    });

    testWidgets('mi mode: 2000 m target renders as "1.2 mi"',
        (tester) async {
      // 2000 / 1609.344 = 1.243 → "1.2 mi" at 1 decimal.
      await setUnit(true);
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(distance: 2000),
          totalSteps: 6,
          currentIndex: 0,
          progress: 0,
          remainingMetres: 2000,
          actualPaceSecPerKm: null,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      expect(find.textContaining('1.2 mi'), findsOneWidget);
    });

    testWidgets('km mode (default): 400 m renders in metres + /km pace',
        (tester) async {
      // Negative-shape pin so a regression that inverted the branch
      // would fail loud. 400 m appears in both the header pill and
      // the "to go" footer → findsAtLeastNWidgets(2).
      await setUnit(false);
      await _pumpBand(
        tester,
        state: WorkoutBandState(
          step: _step(),
          totalSteps: 6,
          currentIndex: 0,
          progress: 0,
          remainingMetres: 400,
          actualPaceSecPerKm: null,
          adherence: PaceAdherence.onPace,
          complete: false,
          abandoned: false,
        ),
      );
      expect(find.textContaining('400 m'), findsAtLeastNWidgets(1));
      expect(find.textContaining('/km'), findsOneWidget);
      expect(find.textContaining('yd'), findsNothing);
      expect(find.textContaining('/mi'), findsNothing);
    });
  });
  group('WorkoutExecutionBand — controls fit a phone (issue #1300)', () {
    const state = WorkoutBandState(
      step: WorkoutStep(
        kind: WorkoutStepKind.steady,
        targetDistanceMetres: 8046.72,
        targetPaceSecPerKm: 348,
        label: 'Steady',
      ),
      totalSteps: 3,
      currentIndex: 1,
      progress: 0.01,
      remainingMetres: 8000,
      actualPaceSecPerKm: 360,
      adherence: PaceAdherence.behind,
      complete: false,
      abandoned: false,
    );

    Future<void> pumpAt(WidgetTester tester, double scale,
        {Locale locale = const Locale('en')}) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: WorkoutExecutionBand(
              state: ValueNotifier<WorkoutBandState>(state),
              onSkip: () {},
              onRewind: () {},
              onAbandon: () {},
            ),
          ),
        ),
      );
    }

    int lineCount(WidgetTester tester, Finder text) {
      final rp = tester.renderObject<RenderParagraph>(text);
      final plain = rp.text.toPlainText();
      final boxes = rp.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: plain.length));
      return boxes.map((b) => b.top.round()).toSet().length;
    }

    // German is pinned at 1.0 only: the test font draws every glyph a full
    // em wide, so "Überspringen" at 2x is about twice as wide as on a device.
    for (final (scale, locale) in const [
      (1.0, Locale('en')),
      (2.0, Locale('en')),
      (1.0, Locale('de')),
    ]) {
      testWidgets(
          'at 360dp, ${locale.languageCode}, text scale $scale: Skip is one '
          'unbroken line and nothing overflows', (tester) async {
        await pumpAt(tester, scale, locale: locale);
        expect(tester.takeException(), isNull);
        final l10n = lookupAppLocalizations(locale);
        final skip = find.descendant(
          of: find.byKey(const Key('workoutBandSkip')),
          matching: find.text(l10n.runWorkoutSkip),
        );
        expect(skip, findsOneWidget);
        expect(lineCount(tester, skip), 1);
        expect(tester.renderObject<RenderParagraph>(skip).didExceedMaxLines,
            isFalse,
            reason: 'the Skip label must fit, not ellipsize');
        // Rewind and Abandon carry no label on the card at all.
        expect(find.text(l10n.runWorkoutRewind), findsNothing);
        expect(find.text(l10n.runWorkoutAbandon), findsNothing);
        expect(find.byTooltip(l10n.runWorkoutRewind), findsOneWidget);
      });
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'at 360dp, text scale $scale: Abandon is reachable from the menu',
          (tester) async {
        await pumpAt(tester, scale);
        await tester.tap(find.byKey(const Key('workoutBandMore')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Abandon'), findsOneWidget);
      });
    }

    testWidgets('Rewind is announced by its label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAt(tester, 1.0);
      expect(find.bySemanticsLabel('Rewind'), findsOneWidget);
      expect(find.byTooltip('More workout actions'), findsOneWidget);
      handle.dispose();
    });
  });
}
