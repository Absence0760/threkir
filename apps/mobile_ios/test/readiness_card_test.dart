import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training_load.dart';
import '../lib/widgets/readiness_card.dart';

Future<void> _pump(WidgetTester tester, {double? width, double textScale = 1}) {
  final card = ReadinessCard(
    runs: const [],
    now: DateTime(2026, 6, 10, 12),
    loadSeries: [
      TrainingLoadPoint(
        date: DateTime(2026, 6, 10),
        stress: 50,
        atl: 30,
        ctl: 50,
        tsb: 20,
      ),
    ],
  );
  return tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: width == null
              ? SingleChildScrollView(child: card)
              : SizedBox(width: width, child: SingleChildScrollView(child: card)),
        ),
      ),
    ),
  );
}

void main() {
  group('ReadinessCard', () {
    testWidgets('renders the header and a band badge', (tester) async {
      await _pump(tester);
      expect(find.text('Readiness'), findsOneWidget);
    });

    testWidgets(
        'the form contribution is named apart from the TSB stat it comes from',
        (tester) async {
      await _pump(tester);
      expect(find.text('Training balance'), findsOneWidget);
      expect(find.textContaining('TSB'), findsNothing);
    });

    testWidgets('says in words that it is scored from training load only',
        (tester) async {
      // Nothing reads sleep or resting HR yet, so training balance is the
      // only contributor; the single chip used to be the only hint of that.
      await _pump(tester);
      expect(
        find.text('Scored from your training load only. Sleep and resting '
            'heart rate are not part of it yet.'),
        findsOneWidget,
      );
    });

    testWidgets('the load-only note wraps at 2.0x text on a narrow card',
        (tester) async {
      await _pump(tester, width: 280, textScale: 2.0);
      expect(find.byKey(const Key('readinessLoadOnly')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('header row survives a narrow width without overflowing',
        (tester) async {
      await _pump(tester, width: 200);
      // Header + band badge share one row; at 200 the header must
      // ellipsize instead of throwing a RenderFlex overflow (the harness
      // fails the test on one).
      expect(find.text('Readiness'), findsOneWidget);
    });
  });
}
