import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  test('the scale is ascending and holds every rung once', () {
    final sorted = [...AppSpace.scale]..sort();
    expect(AppSpace.scale, sorted);
    expect(AppSpace.scale.toSet().length, AppSpace.scale.length);
  });

  test('every rung web has matches web\'s value', () {
    // Web declares the rungs in rem on a 16 px root.
    final css = File('../../apps/web/src/app.css').readAsStringSync();
    double web(String name) {
      final m = RegExp('--space-$name:\\s*([0-9.]+)rem;').firstMatch(css);
      expect(m, isNotNull, reason: '--space-$name is missing from app.css');
      return double.parse(m!.group(1)!) * 16;
    }

    expect(AppSpace.xxs, web('2xs'));
    expect(AppSpace.xs, web('xs'));
    expect(AppSpace.sm, web('sm'));
    expect(AppSpace.md, web('md'));
    expect(AppSpace.lg, web('lg'));
    expect(AppSpace.xl, web('xl'));
    expect(AppSpace.xxl, web('2xl'));
  });

  test('the named insets sit on the scale', () {
    for (final v in [
      AppInsets.gutter,
      AppInsets.pageTop,
      AppInsets.sectionGap,
      AppInsets.itemGap,
      ...[AppInsets.card, AppInsets.cardDense, AppInsets.sheet, AppInsets.page]
          .expand((e) => [e.left, e.top, e.right, e.bottom])
          .where((v) => v != 0),
    ]) {
      expect(AppSpace.scale, contains(v));
    }
  });
}
