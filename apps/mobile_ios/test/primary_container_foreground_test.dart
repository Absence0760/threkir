// Source pins for what may be drawn ON `primaryContainer` (issue #1300).
//
// The container is the coral tint now, and `packages/ui_kit/test/
// app_theme_nav_fab_contrast_test.dart` computes every pairing below from the
// real tokens: `onPrimaryContainer` clears AA on it in both themes, `primary`
// clears only the 3:1 mark floor (3.689 light / 3.784 dark), `outline` misses
// even that in dark (2.960), and `hintColor` — a 60% white, not a measured
// token — reads 4.484 in dark. So each site here either draws a glyph in
// `primary` or type in `onPrimaryContainer` / `onSurfaceVariant`, and this
// fails if one drifts back.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _window(String path, String anchor, int length) {
  final src = File(path).readAsStringSync();
  final at = src.indexOf(anchor);
  expect(at, isNonNegative, reason: '$path no longer contains "$anchor"');
  final end = (at + length).clamp(0, src.length);
  return src.substring(at, end);
}

void main() {
  test('the lap flag is drawn in onPrimaryContainer, not primary', () {
    final w = _window('lib/screens/run_screen.dart', 'runMarkLapA11yHint', 900);
    final flag = w.indexOf('Icons.flag_outlined');
    expect(flag, isNonNegative);
    final icon = w.substring(flag, flag + 160);
    expect(icon, contains('colorScheme.onPrimaryContainer'));
    expect(icon, isNot(contains('colorScheme.primary,')));
  });

  test('the superset chip label is onPrimaryContainer type', () {
    final w = _window('lib/screens/routine_detail_screen.dart',
        'gymRoutineSupersetBadge', 200);
    expect(w, contains('colorScheme.onPrimaryContainer'));
    expect(w, isNot(contains('colorScheme.primary,')));
  });

  test('the challenge standing card uses measured type tokens', () {
    final w = _window('lib/screens/challenge_detail_screen.dart',
        'Widget _standing(', 2400);
    final body = w.substring(0, w.indexOf("Key('challenge-standing')"));
    expect(body, isNot(contains('hintColor')));
    expect(body, isNot(contains('color: scheme.primary)')));
  });

  for (final (path, anchor) in [
    ('lib/screens/club_detail_screen.dart', 'clubDetailNextEvent'),
    ('lib/widgets/upcoming_event_card.dart', 'upcomingEventBadge'),
  ]) {
    test('$path: the next-event eyebrow and glyphs clear the container', () {
      final w = _window(path, anchor, 1800);
      expect(w.substring(0, 200), contains('colorScheme.onPrimaryContainer'));
      expect(w, isNot(contains('colorScheme.outline')));
    });
  }
}
