// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme, PageTitleScope;

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
  // Keep the framework's report of the last error, which names the widget
  // that overflowed; `takeException` alone returns only the message.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    _reports.add(details.toString());
    previous?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = previous;
    _reports.clear();
  });
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
  final reports = List.of(_reports);
  _reports.clear();
  expect(e, isNull,
      reason: '$where overflowed or threw: '
          '${reports.isEmpty ? e : reports.join('\n')}');
}

/// As [expectNoOverflow], but for a surface whose test environment raises
/// errors that are not layout (a map's tile fetches, which have no network
/// here): those are drained, and only a layout overflow fails.
void expectNoLayoutOverflow(WidgetTester tester, String where) {
  tester.takeException();
  final overflows = _reports.where((r) => r.contains('overflowed')).toList();
  _reports.clear();
  expect(overflows, isEmpty,
      reason: '$where overflowed: ${overflows.join('\n')}');
}

final List<String> _reports = [];

/// Fails when an app bar shows a title it has cut short (TO-12): a pushed
/// page says its name in its body (`PageHeader`, `DetailHero`) and the bar
/// repeats it only once that heading has scrolled away, so a cut bar title
/// is only acceptable on a page whose body says the name in full. A title
/// the bar is hiding (opacity 0) is not shown, so not cut. A conversation's
/// name (`ThreadTitle`) cannot move into a body of messages; it passes when a
/// `Tooltip` around it carries the whole name.
///
/// [worstCaseTestWidgets] runs it on every surface it lays out.
void expectTitlesNotCut(WidgetTester tester, String where) {
  final cut = <String>[];
  for (final barElement in find.byType(AppBar).evaluate()) {
    final title = (barElement.widget as AppBar).title;
    if (title == null) continue;
    Element? titleElement;
    void seek(Element e) {
      if (titleElement != null) return;
      if (identical(e.widget, title)) {
        titleElement = e;
        return;
      }
      e.visitChildren(seek);
    }

    barElement.visitChildren(seek);
    final found = titleElement;
    if (found == null || PageTitleScope.hasInBodyTitle(found)) continue;
    final barRender = barElement.renderObject;
    void check(Element e) {
      final render = e.renderObject;
      if (e is RenderObjectElement &&
          render is RenderParagraph &&
          render.hasSize &&
          render.didExceedMaxLines &&
          _shown(render, barRender) &&
          !_wholeInTooltip(e, render.text.toPlainText())) {
        cut.add(render.text.toPlainText());
      }
      e.visitChildren(check);
    }

    check(found);
  }
  expect(cut, isEmpty,
      reason: '$where cuts its app-bar title short: $cut. Say the title in '
          'the body (PushedPage / DetailPage with a PageHeader or '
          'DetailHero), where it wraps.');
}

bool _wholeInTooltip(Element e, String text) {
  var whole = false;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Tooltip && w.message == text) whole = true;
    return !whole && w is! AppBar;
  });
  return whole;
}

bool _shown(RenderObject render, RenderObject? stop) {
  for (RenderObject? r = render; r != null && r != stop; r = r.parent) {
    if (r is RenderOpacity && r.opacity == 0) return false;
    if (r is RenderAnimatedOpacity && r.opacity.value == 0) return false;
  }
  return true;
}

/// One test per shipped locale at the worst case. [body] pumps the screen
/// (through [worstCaseApp]) and may walk it; any overflow left at the end
/// fails the run, and [body] can call [expectNoOverflow] between steps.
void worstCaseTestWidgets(
  String description,
  Future<void> Function(WidgetTester tester, Locale locale) body, {
  List<Locale>? locales,
  bool skip = false,
  bool layoutOnly = false,
}) {
  for (final locale in locales ?? kWorstCaseLocales) {
    testWidgets(
      '$description fits 320 dp at 2x with the 3-button bar '
      '[${locale.toLanguageTag()}]',
      (tester) async {
        useWorstCasePhone(tester);
        await body(tester, locale);
        final where = '$description [${locale.toLanguageTag()}]';
        layoutOnly
            ? expectNoLayoutOverflow(tester, where)
            : expectNoOverflow(tester, where);
        expectTitlesNotCut(tester, where);
      },
      skip: skip,
    );
  }
}

/// The [AppLocalizations] a worst-case run reads, for finding a localized
/// label without spelling it in English.
AppLocalizations l10nFor(Locale locale) => lookupAppLocalizations(locale);

/// Scrolls [scrollable] from top to bottom a viewport at a time, failing on
/// the first step that overflows, so a lazy list's off-screen items are laid
/// out at the worst case too.
Future<void> walkScrollable(
  WidgetTester tester,
  Finder scrollable,
  String where,
) async {
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(position.minScrollExtent);
  await tester.pump();
  expectNoOverflow(tester, '$where at the top');
  for (var step = 1; step <= 60; step++) {
    if (position.pixels >= position.maxScrollExtent) return;
    position.jumpTo((position.pixels + position.viewportDimension * 0.8)
        .clamp(position.minScrollExtent, position.maxScrollExtent));
    await tester.pump();
    expectNoOverflow(tester, '$where, scroll step $step');
  }
}

/// The screen's main vertical scroll view: the first downward [Scrollable]
/// in the tree, so a horizontal strip or a text field's own scrollable
/// above it is never picked.
Finder primaryScrollable() => find
    .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
    .first;
