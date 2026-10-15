import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppTabBar, AppTheme;

/// Issue #666 I14 asked whether the Social hub's fifth sub-tab (Challenges)
/// starts off-screen. Rather than assert it, measure it: `AppTabBar` derives
/// `isScrollable` from whether the labels fit the width it is handed
/// (decisions § 533), so the answer is a function of the phone and the OS
/// text scale, not of the author's guess.
///
/// A filled strip gives every tab an EQUAL share of the width, so whether it
/// fits is the widest label times the tab count — not the sum of the labels.
/// The sum rule called five labels a fit at 840 dp while each tab's 168 dp
/// share was narrower than "Challenges", which then clipped. On a 360 dp
/// phone the finding is true, and it was already true of the FOURTH tab
/// before Challenges existed: this is the derivation behaving, not a
/// regression the fifth tab introduced.
void main() {
  Future<({bool scrollable, double lastTabRight, double width})> measure(
    WidgetTester tester, {
    required double width,
    required List<String> labels,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late TabController controller;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: DefaultTabController(
        length: labels.length,
        child: Builder(builder: (ctx) {
          controller = DefaultTabController.of(ctx);
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 0,
              bottom: AppTabBar(controller: controller, labels: labels),
            ),
            body: const SizedBox.shrink(),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();

    final bar = tester.widget<TabBar>(find.byType(TabBar));
    final last = tester.getRect(find.text(labels.last));
    return (
      scrollable: bar.isScrollable,
      lastTabRight: last.right,
      width: width
    );
  }

  const five = ['Feed', 'People', 'Clubs', 'Discover', 'Challenges'];
  const four = ['Feed', 'People', 'Clubs', 'Discover'];

  testWidgets('the five Social labels do not fit a 360 dp phone',
      (tester) async {
    final m = await measure(tester, width: 360, labels: five);
    expect(m.scrollable, isTrue,
        reason: 'five labels overflow 360 dp, so AppTabBar derives a '
            'scrolling strip');
    expect(m.lastTabRight, greaterThan(m.width),
        reason: 'Challenges therefore begins past the right edge on load — '
            'measured, not assumed');
  });

  testWidgets('the four that preceded Challenges did not fit either',
      (tester) async {
    // The correction: the fifth tab did not create this. Measured at the same
    // width, the fourth tab already sat past the edge.
    final m = await measure(tester, width: 360, labels: four);
    expect(m.scrollable, isTrue);
    expect(m.lastTabRight, greaterThan(m.width));
  });

  /// The width a filled strip of [labels] needs: the widest label plus
  /// Material's per-tab padding, once per tab. Measured with the tab style the
  /// mounted strip resolves, so the number holds under any test font.
  double fillWidth(WidgetTester tester, List<String> labels) {
    final ctx = tester.element(find.byType(TabBar));
    final theme = Theme.of(ctx);
    final style = theme.tabBarTheme.labelStyle ?? theme.textTheme.titleSmall;
    var widest = 0.0;
    for (final l in labels) {
      final p = TextPainter(
        text: TextSpan(text: l, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(ctx),
      )..layout();
      widest = widest > p.width ? widest : p.width;
      p.dispose();
    }
    return (widest + kTabLabelPadding.horizontal) * labels.length;
  }

  testWidgets('both strips fill once every tab holds its widest label',
      (tester) async {
    // Assert the population, not only the property: the strip is not
    // scrollable for everything, so the two results above are about these
    // labels at that width and not about AppTabBar always scrolling.
    for (final labels in [five, four]) {
      await measure(tester, width: 360, labels: labels);
      final fits = fillWidth(tester, labels).ceilToDouble() + 1;
      final m = await measure(tester, width: fits, labels: labels);
      expect(m.scrollable, isFalse, reason: '${labels.length} labels at $fits');
      expect(m.lastTabRight, lessThanOrEqualTo(m.width));

      final short = await measure(tester, width: fits - 2, labels: labels);
      expect(short.scrollable, isTrue,
          reason: 'one dp short of an equal share for the widest label');
    }
  });
}
