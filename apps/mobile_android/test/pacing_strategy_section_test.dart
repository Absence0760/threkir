import 'package:core_models/core_models.dart' show DistanceUnit, Waypoint;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/pacing_strategy_section.dart';

const double _mPerDegLat = 111320;
const double _tenMileFraction = 16093.44 / 42195;

/// A meridian-aligned track of `(metres, pace s/km)` legs in 50 m steps.
List<Waypoint> _track(List<(double, double)> legs) {
  var cumM = 0.0;
  var tMs = DateTime.utc(2026, 4, 12, 7).millisecondsSinceEpoch;
  Waypoint at() => Waypoint(
      lat: 40 + cumM / _mPerDegLat,
      lng: -105,
      timestamp: DateTime.fromMillisecondsSinceEpoch(tMs, isUtc: true));
  final out = <Waypoint>[at()];
  for (final (m, pace) in legs) {
    final n = (m / 50).round() < 1 ? 1 : (m / 50).round();
    for (var i = 0; i < n; i++) {
      cumM += m / n;
      tMs += (m / n * pace).round();
      out.add(at());
    }
  }
  return out;
}

/// A 5K under 10-10-10 with a 25:00 goal (targets 5:06 / 5:00 / 4:50 per km),
/// run at 4:50, 5:00 and 5:15 — the went-out-too-fast shape. The same run the
/// web Playwright spec seeds.
final _tooFastFiveK = _track([
  (5000 * _tenMileFraction, 290),
  (5000 * _tenMileFraction, 300),
  (5000 - 2 * 5000 * _tenMileFraction, 315),
]);

const _strategy = {
  'pacing_strategy': {
    'preset': 'ten_ten_ten',
    'distance_m': 5000,
    'goal_time_s': 1500,
  },
};

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, dynamic>? metadata,
  List<Waypoint> track = const [],
  DistanceUnit unit = DistanceUnit.km,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PacingStrategySection(
              metadata: metadata, track: track, unit: unit),
        ),
      ),
    ),
  );
}

Finder _inPhase(String intent, String text) => find.descendant(
    of: find.byKey(Key('pacing-strategy-phase-$intent')),
    matching: find.text(text));

void main() {
  group('PacingStrategySection', () {
    testWidgets('renders nothing without a pacing strategy', (tester) async {
      await _pump(tester,
          metadata: const {'activity_type': 'run'}, track: _tooFastFiveK);
      expect(find.byKey(const Key('pacing-strategy-section')), findsNothing);
      expect(find.text('Pacing strategy'), findsNothing);
    });

    testWidgets('renders nothing for a preset this build does not know',
        (tester) async {
      await _pump(tester,
          metadata: const {
            'pacing_strategy': {'preset': 'pyramid', 'distance_m': 5000},
          },
          track: _tooFastFiveK);
      expect(find.byKey(const Key('pacing-strategy-section')), findsNothing);
    });

    testWidgets('grades a 10-10-10 run that went out too fast, phase by phase',
        (tester) async {
      await _pump(tester, metadata: _strategy, track: _tooFastFiveK);
      expect(find.text('Pacing strategy'), findsOneWidget);
      expect(find.text('Went out too fast'), findsOneWidget);
      expect(find.textContaining('10-10-10'), findsOneWidget);
      expect(find.textContaining('Goal 25:00'), findsOneWidget);
      expect(_inPhase('hold_back', 'Hold back'), findsOneWidget);
      expect(_inPhase('settle', 'Settle'), findsOneWidget);
      expect(_inPhase('race', 'Race'), findsOneWidget);
      expect(_inPhase('hold_back', '5:06 /km'), findsOneWidget);
      expect(_inPhase('hold_back', '−16s'), findsOneWidget);
      expect(_inPhase('race', '4:50 /km'), findsOneWidget);
      expect(find.textContaining('1.5%'), findsOneWidget);
    });

    testWidgets('pace cells and the gap follow the miles preference',
        (tester) async {
      await _pump(tester,
          metadata: _strategy, track: _tooFastFiveK, unit: DistanceUnit.mi);
      // 306 s/km is 8:12 per mile; the 16 s/km gap is 26 s per mile.
      expect(_inPhase('hold_back', '8:12 /mi'), findsOneWidget);
      expect(_inPhase('hold_back', '−26s'), findsOneWidget);
    });

    testWidgets('a run with no track keeps the targets and says why it is ungraded',
        (tester) async {
      await _pump(tester, metadata: _strategy);
      expect(find.text('Pacing strategy'), findsOneWidget);
      expect(find.text('Went out too fast'), findsNothing);
      expect(_inPhase('hold_back', '5:06 /km'), findsOneWidget);
      expect(
          find.text(
              "This run has no timed GPS track, so its phases can't be graded."),
          findsOneWidget);
    });
  });
}
