import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/hold_to_stop_hint.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/run_screen.dart';
import 'pump_until.dart';

Future<void> _pumpButton(
  WidgetTester tester, {
  required VoidCallback onHoldComplete,
  bool showHint = true,
  bool reduceMotion = false,
  Key? key,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Center(
              child: HoldToStopButton(
                key: key,
                onHoldComplete: onHoldComplete,
                showHint: showHint,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final _hintRing = find.byKey(HoldToStopButton.hintRingKey);
final _hintBubble = find.byKey(HoldToStopButton.hintBubbleKey);

/// The learned flag as the mounted button read it on mount; null until that
/// SharedPreferences read lands.
bool? _buttonLearned(WidgetTester tester) {
  final state = tester.state(find.byType(HoldToStopButton));
  // ignore: avoid_dynamic_calls
  return (state as dynamic).learned as bool?;
}

/// Waits for the button's learned-flag read to land, which is what starts the
/// demonstration, then advances the fake clock into it: the first frame starts
/// the demonstration's clock, the second moves it.
Future<void> _pumpUntilHintShows(WidgetTester tester) async {
  await pumpUntil(tester, () => _buttonLearned(tester) == false,
      describe: "the Stop button's learned-flag read to report unlearned");
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(_hintRing, findsOneWidget,
      reason: 'the hold-to-stop demonstration should play by itself');
}

/// Lets the demonstration run to its end so the test leaves no ticker live.
Future<void> _finishHint(WidgetTester tester) async {
  await tester.pump(HoldToStopButton.hintDuration);
  await tester.pump();
}

Future<bool?> _storedLearned(WidgetTester tester) async {
  bool? learned;
  await tester.runAsync(() async {
    final prefs = await SharedPreferences.getInstance();
    learned = prefs.getBool(kHoldToStopLearnedKey);
  });
  return learned;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({kHoldToStopLearnedKey: true});
  });

  testWidgets('renders the "hold to stop" hint and no ring at rest',
      (tester) async {
    await _pumpButton(tester, onHoldComplete: () {});

    expect(find.text('Hold to stop'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('hides the hint when showHint is false', (tester) async {
    await _pumpButton(tester, onHoldComplete: () {}, showHint: false);

    expect(find.text('Hold to stop'), findsNothing);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
  });

  testWidgets('a short tap does not stop the run', (tester) async {
    var stopped = false;
    await _pumpButton(tester, onHoldComplete: () => stopped = true);

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump(const Duration(milliseconds: 50));

    expect(stopped, isFalse);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('holding advances the progress ring, then stops the run',
      (tester) async {
    var stopped = false;
    await _pumpButton(tester, onHoldComplete: () => stopped = true);

    final gesture = await tester
        .startGesture(tester.getCenter(find.byIcon(Icons.stop_rounded)));
    // Advance partway through the hold window in small steps: the ring should
    // become visible and partly filled, but the run not yet stopped. The first
    // frames establish the ticker baseline before progress starts advancing.
    final ringFinder = find.byType(CircularProgressIndicator);
    for (var i = 0; i < 4 && ringFinder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(ringFinder, findsOneWidget);
    final ring = tester.widget<CircularProgressIndicator>(ringFinder);
    expect(ring.value, isNotNull);
    expect(ring.value!, greaterThan(0.0));
    expect(ring.value!, lessThan(1.0));
    expect(stopped, isFalse);

    // Cross the full hold threshold.
    await tester.pump(const Duration(milliseconds: 900));
    expect(stopped, isTrue);

    await gesture.up();
    await tester.pump();
  });

  group('first-run hint (issue #1253)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('plays untouched on a device that has never held to stop',
        (tester) async {
      await _pumpButton(tester, onHoldComplete: () {}, showHint: false);
      await _pumpUntilHintShows(tester);

      expect(_hintBubble, findsOneWidget,
          reason: 'the docked Stop has no caption, so the hint brings one');
      expect(find.text('Hold to stop'), findsOneWidget);

      await _finishHint(tester);
      expect(_hintRing, findsNothing);
      expect(_hintBubble, findsNothing);
    });

    testWidgets('the in-panel Stop plays the ring beside its own caption',
        (tester) async {
      await _pumpButton(tester, onHoldComplete: () {});
      await _pumpUntilHintShows(tester);

      expect(_hintBubble, findsNothing);
      expect(find.text('Hold to stop'), findsOneWidget,
          reason: 'the standing caption is not doubled by a bubble');

      await _finishHint(tester);
    });

    testWidgets('a tap without a hold replays it', (tester) async {
      var stopped = false;
      await _pumpButton(tester,
          onHoldComplete: () => stopped = true, showHint: false);
      await _pumpUntilHintShows(tester);
      await _finishHint(tester);
      expect(_hintRing, findsNothing);

      await tester.tap(find.byIcon(Icons.stop_rounded));
      // The first frame starts the replay's clock; the second advances it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(stopped, isFalse);
      expect(_hintRing, findsOneWidget);
      expect(_hintBubble, findsOneWidget);
      expect(await _storedLearned(tester), isNull,
          reason: 'a tap is not a learned hold');

      await _finishHint(tester);
    });

    testWidgets('a completed hold retires it for good', (tester) async {
      var stopped = false;
      await _pumpButton(tester,
          onHoldComplete: () => stopped = true, showHint: false);
      await _pumpUntilHintShows(tester);

      final gesture = await tester
          .startGesture(tester.getCenter(find.byIcon(Icons.stop_rounded)));
      await tester.pump();
      expect(_hintRing, findsNothing,
          reason: 'pressing hands the ring to the real hold');
      for (var i = 0; i < 12 && !stopped; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(stopped, isTrue);
      await gesture.up();
      await tester.pump();

      for (var i = 0; i < 20 && await _storedLearned(tester) != true; i++) {
        await tester.pump();
      }
      expect(await _storedLearned(tester), isTrue);

      // Short taps no longer replay it.
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(_hintRing, findsNothing);

      // A later run's Stop (a fresh button) stays quiet.
      await _pumpButton(tester,
          onHoldComplete: () {}, showHint: false, key: UniqueKey());
      await pumpUntil(tester, () => _buttonLearned(tester) != null,
          describe: "the fresh Stop button's learned-flag read to land");
      expect(_buttonLearned(tester), isTrue);
      await tester.pump(const Duration(milliseconds: 600));
      expect(_hintRing, findsNothing);
      expect(_hintBubble, findsNothing);
    });

    testWidgets('reduce motion shows a still caption and no moving ring',
        (tester) async {
      await _pumpButton(tester,
          onHoldComplete: () {}, showHint: false, reduceMotion: true);
      await pumpUntil(tester, () => _hintBubble.evaluate().isNotEmpty,
          describe: 'the static hold-to-stop caption');

      expect(find.text('Hold to stop'), findsOneWidget);
      expect(_hintRing, findsNothing);
      await tester.pump(HoldToStopButton.hintDuration * 2);
      expect(_hintBubble, findsOneWidget,
          reason: 'a still caption does not time out like the animation');
      expect(_hintRing, findsNothing);
    });
  });
}
