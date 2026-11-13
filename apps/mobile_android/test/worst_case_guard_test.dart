import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Worst-case guard (issue #1374 TO-6).
///
/// A raised text scale on a surface wider than 400 dp cannot show a
/// horizontal overflow, so a 2x test there passes the screens that break on
/// a phone; 17 such tests were found. A test file that raises the text
/// scale to 1.3x or more either goes through `worst_case_layout.dart` (a
/// 320 dp phone, the nav bar, every locale) or sizes its own surface 400 dp
/// wide or narrower. The files below predate the rule; the list may only
/// shrink, and a file that is fixed must leave it.
const _wideAtLargeText = <String>{
  'coach_screen_strip_test.dart',
  'feed_screen_test.dart',
  'finished_summary_test.dart',
  'grisnir_milestone_test.dart',
  'nutrition_meal_detail_screen_test.dart',
  'nutrition_rings_card_test.dart',
  'plan_detail_adherence_test.dart',
  'readiness_card_test.dart',
  'run_screen_test.dart',
  'runner_menu_test.dart',
  'this_week_strip_test.dart',
};

bool _raisesTextScale(String src) => [
      ...RegExp(r'TextScaler\.linear\(\s*([0-9.]+)').allMatches(src),
      ...RegExp(r'textScale(?:Factor)?:\s*([0-9.]+)').allMatches(src),
    ].any((m) => (double.tryParse(m.group(1)!) ?? 0) >= 1.3);

bool _narrow(String src) =>
    RegExp(r'worstCaseTestWidgets|useWorstCasePhone|kWorstCasePhone').hasMatch(src) ||
    RegExp(r'Size\(\s*([0-9.]+)\s*,')
        .allMatches(src)
        .any((m) => (double.tryParse(m.group(1)!) ?? 1e9) <= 400);

void main() {
  test('a raised text scale is tested on a phone-width surface', () {
    final offenders = <String>[];
    final fixed = <String>[];
    for (final f in Directory('test').listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('_test.dart') || name == 'worst_case_guard_test.dart') {
        continue;
      }
      final src = f.readAsStringSync();
      final wide = _raisesTextScale(src) && !_narrow(src);
      if (wide && !_wideAtLargeText.contains(name)) offenders.add(name);
      if (!wide && _wideAtLargeText.contains(name)) fixed.add(name);
    }
    expect(offenders, isEmpty,
        reason: 'test the large text scale with worstCaseTestWidgets '
            '(test/worst_case_layout.dart) or on a <= 400 dp surface: $offenders');
    expect(fixed, isEmpty,
        reason: 'these now test on a phone; remove them from the list: $fixed');
  });
}
