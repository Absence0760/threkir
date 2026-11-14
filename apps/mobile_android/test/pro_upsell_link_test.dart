import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/settings_destination.dart';
import '../lib/widgets/pro_upsell_link.dart';

Future<AppLocalizations> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(360, 640),
  double textScale = 1.0,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: c!,
    ),
    home: Scaffold(body: child),
  ));
  await tester.pumpAndSettle();
  return AppLocalizations.delegate.load(locale);
}

void main() {
  tearDown(() => pendingSettingsDestination.value = null);

  testWidgets('the link asks the shell for the Pro screen', (tester) async {
    final l10n = await _pump(
      tester,
      const ProUpsellLink(message: 'Logging from a photo is a Pro feature.'),
    );
    expect(find.text('Logging from a photo is a Pro feature.'), findsOneWidget);
    expect(pendingSettingsDestination.value, isNull);
    await tester.tap(find.text(l10n.proUpsellAction));
    expect(pendingSettingsDestination.value, SettingsDestination.pro);
  });

  testWidgets('the link is a 48 dp target', (tester) async {
    await _pump(tester, const ProUpsellLink(message: 'Pro gets more.'));
    final size = tester.getSize(find.byKey(const ValueKey('pro-upsell-link')));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  });

  testWidgets('the colour reaches both the message and the link',
      (tester) async {
    const ink = Color(0xFF123456);
    final l10n = await _pump(
      tester,
      const ProUpsellLink(message: 'Daily limit reached.', color: ink),
    );
    expect(tester.widget<Text>(find.text('Daily limit reached.')).style?.color,
        ink);
    final link = tester.widget<TextButton>(find.byType(TextButton));
    expect(link.style?.foregroundColor?.resolve({}), ink);
    expect(find.text(l10n.proUpsellAction), findsOneWidget);
  });

  testWidgets('wraps under the message at 320 dp and 2x text, in German',
      (tester) async {
    final l10n = await _pump(
      tester,
      const ProUpsellLink(
        message: 'Tageslimit erreicht. Pro hat ein höheres Limit.',
      ),
      size: const Size(320, 640),
      textScale: 2.0,
      locale: const Locale('de'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(l10n.proUpsellAction), findsOneWidget);
    expect(tester.getRect(find.byType(ProUpsellLink)).right,
        lessThanOrEqualTo(320));
  });
}
