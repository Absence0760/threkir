import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/metrics.dart';
import '../lib/widgets/metric_label.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('MetricStat', () {
    testWidgets('names the metric and opens its definition on tap',
        (tester) async {
      await tester.pumpWidget(
          _host(const MetricStat(metric: Metric.vo2max, value: '52.4')));
      await tester.pumpAndSettle();

      expect(find.text('VO₂ max'), findsOneWidget);
      expect(find.text('52.4'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
          find.textContaining('how much oxygen your body can use per minute'),
          findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('MetricInfoButton', () {
    testWidgets('carries a subject-naming accessible label', (tester) async {
      await tester
          .pumpWidget(_host(const MetricInfoButton(metric: Metric.rpe)));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.tooltip, 'About RPE');
    });

    testWidgets('opens the definition of the metric it names', (tester) async {
      await tester
          .pumpWidget(_host(const MetricInfoButton(metric: Metric.e1rm)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('Est. 1RM'), findsOneWidget);
      expect(find.textContaining('the heaviest weight you could lift'),
          findsOneWidget);
    });

    testWidgets('keeps a 48dp tap target under a 18dp glyph', (tester) async {
      await tester
          .pumpWidget(_host(const MetricInfoButton(metric: Metric.vert)));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(IconButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('MetricSentence', () {
    testWidgets('renders the sentence with its disclosure beside it',
        (tester) async {
      await tester.pumpWidget(_host(const MetricSentence(
        metric: Metric.riegel,
        sentence: 'predictor',
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('Riegel equivalence'), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.text('Riegel formula'), findsOneWidget);
      expect(
          find.textContaining('predict your time at one race distance'),
          findsOneWidget);
    });

    testWidgets('interpolates a sentence argument', (tester) async {
      await tester.pumpWidget(_host(const MetricSentence(
        metric: Metric.trimp,
        sentence: 'hr',
        args: {'days': '42'},
      )));
      await tester.pumpAndSettle();

      expect(find.text('Heart-rate TRIMP over the last 42 days.'),
          findsOneWidget);
    });
  });

  group('metricText', () {
    testWidgets('resolves the label, a variant and a sentence', (tester) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(_host(Builder(builder: (context) {
        l10n = AppLocalizations.of(context);
        return const SizedBox.shrink();
      })));

      expect(metricText(l10n, Metric.vert), 'Vert');
      expect(
          metricText(l10n, Metric.vert,
              variant: 'total', args: const {'value': '250 m'}),
          '250 m vert');
      expect(
          metricText(l10n, Metric.vdot,
              variant: 'value', args: const {'value': '49.8'}),
          'VDOT 49.8');
      expect(metricDefinition(l10n, Metric.rpe),
          startsWith('Rate of perceived exertion'));
    });
  });
}
