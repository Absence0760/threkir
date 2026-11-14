import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Live-region guard (#1374 A11Y-2).
///
/// A `Semantics(liveRegion: true)` asks TalkBack / VoiceOver to read the
/// node again every time its label changes. Around text that changes on a
/// timer that is a screen reader talking without pause: the race countdown
/// read "Starts in 4:59 … 4:58 … 4:57" over the whole recorder. A clock
/// announces at coarse marks through `announceForAccessibility`
/// (`lib/a11y_announce.dart`) instead.
///
/// Every live region in `lib/` and `packages/ui_kit/lib` is registered here
/// with what changes it: an event (a save, an error, a selection), never a
/// clock. A new one fails until it is registered with its reason, and one
/// that goes away fails until its entry is removed.
const _registered = <String, (int, String)>{
  'lib/screens/global_segments_screen.dart': (1, 'the result count after a search or filter change'),
  'lib/screens/park_courses_screen.dart': (1, 'the board month after a previous / next month tap'),
  'lib/screens/plan_new_screen.dart': (6, 'validation errors and the computed preview after an input change'),
  'lib/screens/run_screen.dart': (1, 'the stopped chip, set once when recording stops'),
  'lib/screens/season_plan_screen.dart': (4, 'the preview and its refusal after an input change'),
  'lib/screens/settings_body_metrics_screen.dart': (2, 'the unsaved / saved line after an edit or a save'),
  'lib/widgets/audience_sheet.dart': (1, 'the audience summary after a selection'),
  'lib/widgets/coach_assist_consent_switch.dart': (1, 'the save error after a toggle'),
  'lib/widgets/coach_share_sheet.dart': (1, 'the share error after a send'),
  'lib/widgets/group_people_picker.dart': (1, 'the selected count after a pick'),
  'lib/widgets/import_failure_report.dart': (1, 'the failure summary when an import ends'),
  'lib/widgets/send_route_sheet.dart': (2, 'the send result and its error'),
  'lib/widgets/streamer_overlay_sheet.dart': (1, 'the copy result after a tap'),
  'lib/widgets/top_banner.dart': (1, 'the banner message, once per banner'),
  'lib/widgets/undo_bar.dart': (1, 'the undo message, once per pending action; its countdown is excluded'),
  'lib/widgets/workout_move_sheet.dart': (1, 'the move error after a confirm'),
  '../../packages/ui_kit/lib/src/widgets/list_skeleton.dart': (2, 'the loading label, once while loading'),
};

Map<String, int> _scan(String root) {
  final found = <String, int>{};
  for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final src = f.readAsStringSync();
    final n = RegExp(r'^(?!\s*//).*\bliveRegion\s*:', multiLine: true).allMatches(src).length;
    if (n > 0) found[f.path] = n;
  }
  return found;
}

void main() {
  test('every live region is registered with the event that changes it', () {
    final found = {..._scan('lib'), ..._scan('../../packages/ui_kit/lib')};
    final problems = <String>[];
    for (final e in found.entries) {
      final reg = _registered[e.key];
      if (reg == null) {
        problems.add('${e.key}: ${e.value} live region(s) not registered. If its text '
            'changes on a timer, announce at marks with announceForAccessibility instead.');
      } else if (reg.$1 != e.value) {
        problems.add('${e.key}: registered ${reg.$1}, found ${e.value}');
      }
    }
    for (final k in _registered.keys) {
      if (!found.containsKey(k)) problems.add('$k: registered but has no live region; remove the entry');
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('no live region sits beside a sub-second timer in the same file', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (!RegExp(r'\bliveRegion\s*:').hasMatch(src)) continue;
      final fast = RegExp(r'Timer\.periodic\(\s*const\s+Duration\(\s*milliseconds:\s*(\d+)')
          .allMatches(src)
          .any((m) => int.parse(m.group(1)!) < 1000);
      if (fast) offenders.add(f.path);
    }
    expect(offenders, isEmpty,
        reason: 'a file that ticks faster than once a second must not hold a live region:\n'
            '${offenders.join('\n')}');
  });
}
