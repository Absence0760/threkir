// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme;

import '../lib/l10n/gen/app_localizations.dart';
import 'three_button_nav_bar.dart' show kThreeButtonNavBar;

/// The worst case a screen is laid out for (issue #1374 TO-6): the narrowest
/// phone the app supports, the largest OS text size, Android's 3-button
/// navigation bar, and every shipped locale.
///
/// Before this, 52 test files each hand-rolled a raised text scale, and at
/// least 17 of them ran it on a surface 400 dp or wider, where a horizontal
/// overflow cannot happen. A screen's worst-case test goes through here:
///
/// ```dart
/// worstCaseTestWidgets('Today', (tester, locale) async {
///   await tester.pumpWidget(worstCaseApp(locale: locale, home: ...));
///   await tester.pump();
/// });
/// ```
///
/// [worstCaseTestWidgets] registers one test per locale, sizes the view,
/// adds the nav bar, and fails on any exception the pump left (a
/// `RenderFlex` overflow surfaces as one). One locale per run, rather than a
/// synthetic locale holding each string's longest translation: that would
/// be a generated catalogue to keep in step with every ARB change, and a
/// reader only ever has one locale. Each string still meets its longest
/// translation in one of the runs.
const kWorstCasePhone = Size(320, 640);
const double kWorstCaseTextScale = 2.0;

/// Every shipped locale, in [AppLocalizations.supportedLocales] order.
final List<Locale> kWorstCaseLocales = AppLocalizations.supportedLocales;

/// A 320 x 640 dp phone with the 48 dp 3-button navigation bar.
void useWorstCasePhone(WidgetTester tester) {
  tester.view.physicalSize = kWorstCasePhone;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = const FakeViewPadding(bottom: kThreeButtonNavBar);
  tester.view.padding = const FakeViewPadding(bottom: kThreeButtonNavBar);
  addTearDown(tester.view.reset);
}

/// The app shell a worst-case test pumps: the given [locale], the app theme,
/// and the OS text scale at [kWorstCaseTextScale].
Widget worstCaseApp({
  required Locale locale,
  required Widget home,
  ThemeData? theme,
  List<NavigatorObserver> navigatorObservers = const [],
}) =>
    MaterialApp(
      theme: theme ?? AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: navigatorObservers,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(kWorstCaseTextScale)),
        child: child!,
      ),
      home: home,
    );

/// Fails if laying out left an exception behind; a `RenderFlex` overflow is
/// reported as one.
void expectNoOverflow(WidgetTester tester, String where) {
  final e = tester.takeException();
  expect(e, isNull, reason: '$where overflowed or threw: $e');
}

/// One test per shipped locale at the worst case. [body] pumps the screen
/// (through [worstCaseApp]) and may walk it; any overflow left at the end
/// fails the run, and [body] can call [expectNoOverflow] between steps.
void worstCaseTestWidgets(
  String description,
  Future<void> Function(WidgetTester tester, Locale locale) body, {
  List<Locale>? locales,
  bool skip = false,
}) {
  for (final locale in locales ?? kWorstCaseLocales) {
    testWidgets(
      '$description fits 320 dp at 2x with the 3-button bar '
      '[${locale.toLanguageTag()}]',
      (tester) async {
        useWorstCasePhone(tester);
        await body(tester, locale);
        expectNoOverflow(tester, '$description [${locale.toLanguageTag()}]');
      },
      skip: skip,
    );
  }
}

/// The [AppLocalizations] a worst-case run reads, for finding a localized
/// label without spelling it in English.
AppLocalizations l10nFor(Locale locale) => lookupAppLocalizations(locale);
