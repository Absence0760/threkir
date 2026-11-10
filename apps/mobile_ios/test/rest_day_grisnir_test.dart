// Grisnir's rest-day card on Home (#1360): his resting art, hidden from
// assistive tech, beside his one line, which wraps rather than overflowing
// at the OS's largest text. Web twin: `RestDayGrisnir.svelte`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/mascot.dart';
import '../lib/widgets/rest_day_grisnir.dart';

Future<void> _pump(WidgetTester tester, {double scale = 1, Locale? locale}) =>
    tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const Scaffold(
        body: SizedBox(width: 320, child: RestDayGrisnir()),
      ),
    ));

void main() {
  testWidgets('draws the resting render beside the one line', (tester) async {
    await _pump(tester);
    final art = tester.widget<Image>(find.byType(Image));
    expect((art.image as AssetImage).assetName, kGrisnirRestAsset);
    expect(art.excludeFromSemantics, isTrue);
    expect(art.width, RestDayGrisnir.artWidth);
    expect(find.text("Back by morning, like Thor's goats."), findsOneWidget);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('fits a 320 px card at 2x text in $locale', (tester) async {
      await _pump(tester, scale: 2, locale: locale);
      expect(tester.takeException(), isNull);
    });
  }
}
