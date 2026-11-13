import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('shows the message and the caller\'s retry label, and retries',
      (tester) async {
    var retried = 0;
    await _pump(
      tester,
      ErrorState(
          message: 'Could not load', retryLabel: 'Again', onRetry: () => retried++),
    );
    expect(find.text('Could not load'), findsOneWidget);
    await tester.tap(find.text('Again'));
    expect(retried, 1);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('the inline form is one row that fits a section', (tester) async {
    await _pump(
      tester,
      ListView(children: [
        ErrorState.inline(
            message: 'Section failed', retryLabel: 'Again', onRetry: () {}),
      ]),
    );
    expect(find.text('Section failed'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Again'), findsOneWidget);
  });

  testWidgets('the full form scrolls instead of overflowing a short viewport',
      (tester) async {
    await _pump(
      tester,
      SizedBox(
        height: 80,
        child: ErrorState(message: 'm', retryLabel: 'r', onRetry: () {}),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the inline form puts Retry under a message that fills the row',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: ListView(children: [
            ErrorState.inline(
              message: 'Impossible de charger les signalements',
              retryLabel: 'Réessayer',
              onRetry: () {},
            ),
          ]),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('Réessayer')).dy,
      greaterThan(tester.getTopLeft(find.text(
              'Impossible de charger les signalements'))
          .dy),
    );
  });
}
