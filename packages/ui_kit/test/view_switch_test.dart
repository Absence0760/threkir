import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 360,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Directionality(
      textDirection: direction,
      child: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 700),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [child]),
          ),
        ),
      ),
    ),
  ));
}

ViewSwitch<int> _switch(List<String> labels, int selected,
        ValueChanged<int> onChanged) =>
    ViewSwitch<int>(
      label: 'Show',
      options: [
        for (var i = 0; i < labels.length; i++)
          ChoiceChipOption(value: i, label: labels[i]),
      ],
      selected: selected,
      onChanged: onChanged,
    );

Finder _segment(int i) => find.byKey(ValueKey('view-switch-segment-$i'));

void main() {
  // The test font draws every glyph a full em wide, far wider than Roboto,
  // so these labels are chosen for the layout each test exercises.
  test('layoutFor: equal, else proportional, else scroll', () {
    expect(ViewSwitch.layoutFor([100, 120], 288), ViewSwitchLayout.equal);
    expect(
        ViewSwitch.layoutFor([100, 160], 288), ViewSwitchLayout.proportional);
    expect(ViewSwitch.layoutFor([150, 160], 288), ViewSwitchLayout.scroll);
    expect(ViewSwitch.layoutFor([10, 10], double.infinity),
        ViewSwitchLayout.scroll);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('equal segments with centred labels at 320 dp and ${scale}x',
        (tester) async {
      await _pump(tester, _switch(['Me', 'Us'], 0, (_) {}),
          width: 320, textScale: scale);
      expect(tester.takeException(), isNull);
      final a = tester.getRect(_segment(0));
      final b = tester.getRect(_segment(1));
      expect(a.width, closeTo(b.width, 0.5), reason: 'equal widths');
      expect(a.left, closeTo(16, 0.5));
      expect(b.right, closeTo(320 - 16, 0.5));
      // The unselected label sits at its segment's centre: no slot is held
      // for a check it does not draw.
      expect(tester.getCenter(find.text('Us')).dx, closeTo(b.center.dx, 1));
      expect(a.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(find.byKey(const Key('view-switch-scroll')), findsNothing);
    });
  }

  testWidgets('labels too long for equal shares fill the row in proportion, '
      'each centred and whole', (tester) async {
    await _pump(tester, _switch(['Mine', 'Explore'], 0, (_) {}), width: 320);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('view-switch-scroll')), findsNothing);
    final a = tester.getRect(_segment(0));
    final b = tester.getRect(_segment(1));
    expect(a.left, closeTo(16, 0.5));
    expect(b.right, closeTo(320 - 16, 0.5));
    expect(b.width, greaterThan(a.width));
    expect(tester.getCenter(find.text('Explore')).dx, closeTo(b.center.dx, 1));
  });

  testWidgets('a label too long for an equal share takes its own width and '
      'the track scrolls with a fade, so nothing is cut', (tester) async {
    await _pump(
      tester,
      _switch(['Meine', 'Verpflegungsstationen entdecken'], 0, (_) {}),
      width: 320,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('view-switch-scroll')), findsOneWidget);
    final label = tester.renderObject<RenderParagraph>(
        find.text('Verpflegungsstationen entdecken'));
    expect(label.didExceedMaxLines, isFalse);
    expect(tester.getSize(_segment(1)).width,
        greaterThan(tester.getSize(_segment(0)).width));
  });

  testWidgets('selection is a check and a selected state, and a tap switches',
      (tester) async {
    var picked = 0;
    await _pump(tester, _switch(['Browse', 'My clubs'], 0, (v) => picked = v));
    expect(
        find.descendant(of: _segment(0), matching: find.byIcon(Icons.check)),
        findsOneWidget);
    expect(
        find.descendant(of: _segment(1), matching: find.byIcon(Icons.check)),
        findsNothing);
    final handle = tester.ensureSemantics();
    expect(
        tester.getSemantics(find.text('Browse')),
        containsSemantics(
          label: 'Browse',
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
        ));
    expect(tester.getSemantics(find.text('My clubs')),
        containsSemantics(isSelected: false, hasTapAction: true));
    handle.dispose();
    await tester.tap(find.text('My clubs'));
    expect(picked, 1);
  });

  testWidgets('right to left, the first view is at the right', (tester) async {
    await _pump(tester, _switch(['Mine', 'Explore'], 0, (_) {}),
        direction: TextDirection.rtl);
    expect(tester.getCenter(_segment(0)).dx,
        greaterThan(tester.getCenter(_segment(1)).dx));
  });
}
