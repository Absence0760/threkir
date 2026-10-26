import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/run_screen.dart';

Widget _host({
  required double paneHeight,
  required double textScale,
  double width = 360,
  String timeValue = '28:41',
  String movingValue = '27:12',
  bool synced = true,
  String? syncError,
  VoidCallback? onDone,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: paneHeight,
          child: FinishedSummary(
            distanceValue: '5.03',
            distanceUnit: 'km',
            timeValue: timeValue,
            movingValue: movingValue,
            primaryLabel: 'Avg pace',
            primaryValue: '5:42',
            primaryUnit: '/km',
            synced: synced,
            syncError: syncError,
            onDone: onDone ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('FinishedSummary — text-scaling scroll fallback', () {
    // The issue geometry: on a ~640dp compact phone the stats pane's
    // flex-4 budget is ~324dp; at 2x OS text scale the content computes
    // to ~395dp. The pane must scroll, not paint an overflow stripe or
    // clip the Done button.
    testWidgets('does not overflow at 2x text scale on a compact pane', (
      tester,
    ) async {
      await tester.pumpWidget(_host(paneHeight: 324, textScale: 2.0));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('Done stays reachable and tappable at 2x text scale', (
      tester,
    ) async {
      var done = 0;
      await tester.pumpWidget(
        _host(paneHeight: 324, textScale: 2.0, onDone: () => done++),
      );
      await tester.pump();

      final doneButton = find.widgetWithText(FilledButton, 'Done');
      expect(doneButton, findsOneWidget);
      await tester.ensureVisible(doneButton);
      await tester.pump();
      await tester.tap(doneButton);
      expect(done, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sync-error variant does not overflow at 2x text scale', (
      tester,
    ) async {
      // The error string is longer than the synced label and renders at
      // a fixed 13px base — the worst-case content height.
      await tester.pumpWidget(
        _host(
          paneHeight: 324,
          textScale: 2.0,
          synced: false,
          syncError: 'Sync failed — saved on this device, will retry',
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Sync failed — saved on this device, will retry'),
        findsOneWidget,
      );
    });

    testWidgets('normal scale keeps the content centered without scrolling', (
      tester,
    ) async {
      var done = 0;
      await tester.pumpWidget(
        _host(paneHeight: 324, textScale: 1.0, onDone: () => done++),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);

      // Content fits: no scroll offset needed, Done tappable in place.
      final scrollable = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollable.controller?.offset ?? 0, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      expect(done, 1);

      // Centering preserved: the heading sits below the 24px padding edge
      // (the ConstrainedBox minHeight keeps MainAxisAlignment.center
      // meaningful when the content is shorter than the pane).
      final headingTop = tester.getTopLeft(find.text('Run Complete')).dy;
      expect(headingTop, greaterThan(24));
    });
  });

  group('FinishedSummary — the numbers stay legible', () {
    // A 13 mile run on a ~355dp phone: four values in one row each shrank to
    // fill a 76dp column and ran together ("13.30 mi3:00:583:00:5513:36").
    Future<void> pumpLongRun(WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          paneHeight: 420,
          textScale: 1.0,
          width: 355,
          timeValue: '3:00:58',
          movingValue: '3:00:55',
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('a three-hour run keeps a gap between neighbouring values', (
      tester,
    ) async {
      await pumpLongRun(tester);
      for (final (a, b) in [('5.03', '5:42'), ('3:00:58', '3:00:55')]) {
        final gap =
            tester.getRect(find.text(b)).left -
            tester.getRect(find.text(a)).right;
        expect(
          gap,
          greaterThanOrEqualTo(8),
          reason: '$a and $b must not touch',
        );
      }
    });

    testWidgets('a three-hour run keeps every value near full size', (
      tester,
    ) async {
      await pumpLongRun(tester);
      for (final v in ['5.03', '5:42', '3:00:58', '3:00:55']) {
        // The test font draws every glyph a full em wide, far wider than
        // the app's, so a real font fits unscaled where this one shrinks a
        // little. The old row drew these at under half size.
        final scale =
            tester.getRect(find.text(v)).width /
            tester.getSize(find.text(v)).width;
        expect(scale, greaterThan(0.9), reason: '$v is drawn near full size');
      }
    });
  });
}
