// A map screen's floating controls and bottom panel go through ui_kit's
// `MapFirstPage`, which owns the system-bar, keyboard and side insets
// (issue #1374, conventions § Mobile map-first pages). Screens that placed
// their own bottom content drew the live spectator's stats under a 3-button
// nav bar (IK-5) and put the privacy-zones Locate button over Clear all
// (IK-3).
//
// Two checks:
//   * A map screen (a `lib/screens` file that builds `FlutterMap(`,
//     `LiveRunMap(` or `MapFirstPage(`) counts its hand-placed bottom
//     controls: a `Positioned(` with a `bottom:`, a Scaffold
//     `floatingActionButton:`, and an `Alignment.bottom…` placement. The
//     counts left are pinned per file in `_handPlaced`, which may only
//     shrink: a rise fails, and so does a fall the map was not lowered for.
//   * A screen in `_migrated` builds `MapFirstPage(` and reads no inset of
//     its own (`SafeArea(`, `MediaQuery.paddingOf` / `viewPaddingOf`, a
//     `.padding.bottom` / `.viewPadding.bottom`), so the template stays the
//     one owner.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _handPlaced = <String, int>{
  'lib/screens/privacy_zones_screen.dart': 1,
  'lib/screens/public_route_screen.dart': 1,
  'lib/screens/route_builder_screen.dart': 1,
  'lib/screens/route_detail_screen.dart': 1,
  'lib/screens/routes_heatmap_screen.dart': 1,
  'lib/screens/run_detail_screen.dart': 1,
  'lib/screens/run_screen.dart': 7,
};

const _migrated = <String>{
  'lib/screens/live_spectator_screen.dart',
};

int _close(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    final c = s[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return s.length - 1;
}

String _stripComments(String s) =>
    s.split('\n').map((l) => l.trimLeft().startsWith('//') ? '' : l).join('\n');

final _mapWidget = RegExp(r'\b(?:FlutterMap|LiveRunMap|MapFirstPage)\(');

int handPlacedIn(String s) {
  var n = 0;
  for (final m in RegExp(r'\bPositioned\(').allMatches(s)) {
    final args = s.substring(m.end, _close(s, m.end - 1));
    if (RegExp(r'\bbottom:').hasMatch(args)) n++;
  }
  n += RegExp(r'\bfloatingActionButton:').allMatches(s).length;
  n += RegExp(r'\bAlignment(?:Directional)?\.bottom').allMatches(s).length;
  return n;
}

final _ownInset = RegExp(
    r'\bSafeArea\(|MediaQuery\.(?:paddingOf|viewPaddingOf)\(|'
    r'\.(?:viewPadding|padding)\.bottom\b');

Map<String, String> _screens() => {
      for (final f in Directory('lib/screens')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        f.path.replaceAll(r'\', '/'): _stripComments(f.readAsStringSync()),
    };

void main() {
  test('hand-placed bottom controls on map screens only go down', () {
    final now = <String, int>{};
    for (final MapEntry(key: path, value: s) in _screens().entries) {
      if (!_mapWidget.hasMatch(s)) continue;
      final n = handPlacedIn(s);
      if (n > 0) now[path] = n;
    }
    final problems = <String>[
      for (final MapEntry(:key, :value) in now.entries)
        if ((_handPlaced[key] ?? 0) < value)
          '$key places $value bottom control(s) by hand (allowed '
              '${_handPlaced[key] ?? 0}): put map controls in MapFirstPage\'s '
              'controls / footer and bottom content in its panel or sheet',
      for (final MapEntry(:key, :value) in _handPlaced.entries)
        if ((now[key] ?? 0) < value)
          '$key is down to ${now[key] ?? 0}: lower _handPlaced to match',
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('a migrated map screen builds MapFirstPage and reads no inset itself',
      () {
    final screens = _screens();
    final problems = <String>[
      for (final path in _migrated)
        if (screens[path] case final s?) ...[
          if (!s.contains('MapFirstPage(')) '$path no longer builds MapFirstPage',
          for (final m in _ownInset.allMatches(s))
            '$path reads an inset itself (${m.group(0)}); MapFirstPage owns it',
        ] else
          '$path is gone: drop it from _migrated',
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('the counter sees each placement it is meant to', () {
    expect(handPlacedIn('Positioned(left: 0, bottom: 0, child: x)'), 1);
    expect(handPlacedIn('Positioned(top: 12, child: f(bottom: 3))'), 1);
    expect(handPlacedIn('Positioned(top: 12, left: 12, child: x)'), 0);
    expect(handPlacedIn('Scaffold(floatingActionButton: fab)'), 1);
    expect(handPlacedIn('Align(alignment: AlignmentDirectional.bottomEnd)'), 1);
  });
}
