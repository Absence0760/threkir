import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/route_review_dialog.dart';

void main() {
  // Issue #1374 TO-1: five 48 dp stars need 240 dp and a 320 dp phone's
  // dialog content area is 192 dp, so the fifth star was clipped out of reach.
  for (final size in [const Size(320, 568), const Size(360, 640)]) {
    testWidgets('all five stars fit and five can be given at '
        '${size.width.toInt()} dp, 2.0x', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      RouteReviewDraft? result;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  result = await showRouteReviewDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final l10n =
          AppLocalizations.of(tester.element(find.byType(AlertDialog)));
      final dialog = tester.getRect(find.byType(AlertDialog));
      final stars = find.descendant(
          of: find.byType(StarRatingInput), matching: find.byType(IconButton));
      expect(stars, findsNWidgets(5));
      for (var i = 0; i < 5; i++) {
        final r = tester.getRect(stars.at(i));
        expect(r.left, greaterThanOrEqualTo(dialog.left));
        expect(r.right, lessThanOrEqualTo(dialog.right));
        expect(r.height, greaterThanOrEqualTo(48));
        expect(r.width, greaterThanOrEqualTo(24));
      }

      final fifth = find.byTooltip(l10n.routeDetailRateStars(5));
      await tester.ensureVisible(fifth);
      await tester.pumpAndSettle();
      await tester.tap(fifth);
      await tester.pump();
      await tester.enterText(find.byType(TextField), '  lovely  ');
      await tester.tap(find.text(l10n.routeDetailSubmit));
      await tester.pumpAndSettle();
      expect(result, (rating: 5, comment: 'lovely'));
    });
  }

  testWidgets('Cancel resolves to null and a blank comment to null',
      (tester) async {
    final results = <RouteReviewDraft?>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => results.add(await showRouteReviewDialog(
                context,
                initialRating: 3)),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    final l10n = AppLocalizations.of(tester.element(find.text('open')));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.routeDetailCancel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.routeDetailSubmit));
    await tester.pumpAndSettle();
    expect(results, [null, (rating: 3, comment: null)]);
  });
}
