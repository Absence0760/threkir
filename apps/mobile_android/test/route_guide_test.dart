import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/route_guide.dart';

/// The Dart reader of `fixtures/route_guide_cases.json`, the case table the
/// web twin (apps/web/src/lib/parks/route_guide.test.ts) reads too.
final List<Map<String, dynamic>> _cases = ((jsonDecode(
            File('../../fixtures/route_guide_cases.json').readAsStringSync())
        as Map<String, dynamic>)['cases'] as List)
    .cast<Map<String, dynamic>>();

final Map<String, dynamic> _arb =
    jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;

String _arbKey(String key) =>
    'parkGuide${key[0].toUpperCase()}${key.substring(1)}';

final GuideFormat _english = GuideFormat(
  message: (key, params) => (_arb[_arbKey(key)] as String).replaceAllMapped(
      RegExp(r'\{(\w+)\}'), (m) => '${params[m.group(1)]}'),
  distance: (m) => '${(m / 1000).toStringAsFixed(1)} km',
  short: (m) => '${m.round()} m',
);

void main() {
  for (final c in _cases) {
    test('route guide case: ${c['name']}', () {
      final guide = parseRouteGuide(c['guide']);
      final parsed = c['parsed'] as Map<String, dynamic>?;
      if (parsed == null) {
        expect(guide, isNull);
        return;
      }
      expect(guide, isNotNull);
      expect(guide!.lang, parsed['lang']);
      expect(guide.gettingThere, parsed['getting_there']);
      expect(
        [for (final l in routeGuideLines(guide)) l.toJson()],
        c['lines'],
      );
    });
  }

  test('every line key has an English template whose placeholders it fills', () {
    for (final key in kGuideLineKeys) {
      expect(_arb[_arbKey(key)], isA<String>(), reason: key);
      final line = formatGuideLine(
        GuideLine(key,
            at: 1000,
            name: 'N',
            landmark: 'L',
            gain: 5,
            length: 50,
            n: 2,
            total: 3),
        _english,
      );
      expect(line, isNot(matches(RegExp(r'\{\w+\}'))), reason: key);
    }
  });

  test('routeGuideText renders a guide as English lines', () {
    final guide = parseRouteGuide(_cases[0]['guide'])!;
    final text = routeGuideText(guide, _english);
    expect(text[0], 'Start on Lake Trail.');
    expect(text[1], 'Run the loop clockwise.');
    expect(text[2], 'Pass every checkpoint in order, or the run is not timed.');
    expect(text[3], '0.4 km: turn left onto Ridge Trail.');
    expect(text[6], '0.8 km: a climb of 14 m over 300 m.');
    expect(text.last, '2.0 km: finish.');
  });

  test('guideEn is the English catalogue, entry for entry', () {
    for (final e in guideEn.entries) {
      expect(e.value, _arb[_arbKey(e.key)], reason: e.key);
    }
    expect(
      guideEn.keys.toList()..sort(),
      [...kGuideLineKeys, 'pending', 'checked']..sort(),
    );
  });

  test('routeGuideEnglish leads with the ground-check status and the getting-there note', () {
    final guide = parseRouteGuide(_cases[0]['guide'])!;
    final pending = routeGuideEnglish(guide, null);
    expect(pending[0], 'Drafted from map data, not yet checked on the ground.');
    expect(pending[1], 'Park by the boathouse.');
    expect(pending[2], 'Start on Lake Trail.');
    expect(routeGuideEnglish(guide, '2026-12-01')[0],
        'Checked on the ground on 2026-12-01.');
  });
}
