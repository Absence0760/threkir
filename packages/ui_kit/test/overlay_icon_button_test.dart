import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Issue #1374 A11Y-6: the photo tiles' overlay buttons were 30 dp discs
/// 4 dp apart. The shared button keeps a 48 dp target and a scrim the glyph
/// is legible on over any photo.
double _luminance(Color c) {
  double chan(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Future<void> _pump(WidgetTester tester, ThemeData theme, List<Widget> buttons) =>
    tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(child: Row(mainAxisSize: MainAxisSize.min, children: buttons)),
      ),
    ));

void main() {
  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
    testWidgets('$name: each button is a 48 dp target and neighbours do not overlap',
        (tester) async {
      var taps = <String>[];
      await _pump(tester, theme, [
        OverlayIconButton(icon: Icons.edit, tooltip: 'Edit', onPressed: () => taps.add('edit')),
        OverlayIconButton(icon: Icons.delete, tooltip: 'Delete', onPressed: () => taps.add('delete')),
      ]);
      final edit = tester.getRect(find.byType(OverlayIconButton).first);
      final delete = tester.getRect(find.byType(OverlayIconButton).last);
      expect(edit.size, const Size(48, 48));
      expect(delete.size, const Size(48, 48));
      expect(edit.overlaps(delete.deflate(0.01)), isFalse);
      // A tap 20 dp right of the edit disc's centre is still edit's.
      await tester.tapAt(edit.center + const Offset(20, 0));
      await tester.tapAt(delete.center - const Offset(20, 0));
      expect(taps, ['edit', 'delete']);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  }

  test('the glyph clears AA on the scrim over the lightest and darkest photo', () {
    for (final photo in [Colors.white, Colors.black]) {
      final disc = Color.alphaBlend(OverlayIconButton.scrim, photo);
      final on = Color.alphaBlend(OverlayIconButton.glyph, disc);
      final off = Color.alphaBlend(OverlayIconButton.disabledGlyph, disc);
      expect(_contrast(on, disc), greaterThanOrEqualTo(4.5), reason: 'over $photo');
      expect(_contrast(off, disc), greaterThanOrEqualTo(3.0),
          reason: 'disabled glyph over $photo (1.4.11)');
    }
    // The disc itself stands off a white photo (1.4.11).
    expect(_contrast(Color.alphaBlend(OverlayIconButton.scrim, Colors.white), Colors.white),
        greaterThanOrEqualTo(3.0));
  });

  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
    test('$name: a selected toggle reads onPrimary on primary', () {
      expect(_contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary),
          greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('a disabled button stays a 48 dp target with its name', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, AppTheme.light, [
      const OverlayIconButton(icon: Icons.emoji_events, tooltip: 'Race gallery', onPressed: null),
    ]);
    expect(tester.getSize(find.byType(OverlayIconButton)), const Size(48, 48));
    expect(find.byTooltip('Race gallery'), findsOneWidget);
    handle.dispose();
  });
}
