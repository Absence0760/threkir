// Every modal bottom sheet lays its content out through ui_kit's
// `SheetScaffold`, which adds the keyboard or system nav-bar inset to the
// sheet's bottom. `showModalBottomSheet(useSafeArea: true)` deliberately
// leaves the bottom bar to the content, and sheets that padded for
// `viewInsets` alone drew their Save row under a 3-button nav bar, where a
// tap landed on Back or Home (issue #1374 IK-1, decisions § 2485).
//
// A call counts as migrated when its builder builds a `SheetScaffold`
// directly, or builds a widget whose class (or its `State`) does. The sheets
// not yet migrated are counted per file in `_unmigrated`, which may only
// shrink: a new unmigrated sheet fails, and so does an entry that has gone
// stale because a sheet was migrated or removed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _unmigrated = <String, int>{
  'lib/screens/add_run_screen.dart': 1,
  'lib/screens/club_detail_screen.dart': 1,
  'lib/screens/event_detail_screen.dart': 3,
  'lib/screens/group_thread_screen.dart': 1,
  'lib/screens/message_thread_screen.dart': 1,
  'lib/screens/period_summary_screen.dart': 1,
  'lib/screens/plan_detail_screen.dart': 1,
  'lib/screens/plan_new_screen.dart': 1,
  'lib/screens/route_builder_screen.dart': 1,
  'lib/screens/route_detail_screen.dart': 1,
  'lib/screens/run_screen.dart': 2,
  'lib/screens/runs_screen.dart': 1,
  'lib/screens/settings_integrations_screen.dart': 2,
  'lib/widgets/audience_sheet.dart': 1,
  'lib/widgets/badge_share_sheet.dart': 1,
  'lib/widgets/club_invite_card.dart': 1,
  'lib/widgets/disclosure_section.dart': 1,
  'lib/widgets/dm_reaction_chips.dart': 1,
  'lib/widgets/event_photos.dart': 1,
  'lib/widgets/finisher_certificate_card.dart': 1,
  'lib/widgets/group_members_sheet.dart': 1,
  'lib/widgets/head_to_head_card.dart': 1,
  'lib/widgets/live_share_indicator.dart': 1,
  'lib/widgets/log_sheet.dart': 1,
  'lib/widgets/race_stop_sheet.dart': 1,
  'lib/widgets/recap_share_card.dart': 1,
  'lib/widgets/route_share_card.dart': 1,
  'lib/widgets/run_share_card.dart': 1,
  'lib/widgets/runner_menu.dart': 1,
  'lib/widgets/send_route_sheet.dart': 1,
  'lib/widgets/streamer_overlay_sheet.dart': 1,
  'lib/widgets/workout_move_sheet.dart': 1,
};

int _close(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s.startsWith('//', i)) {
      final nl = s.indexOf('\n', i);
      if (nl < 0) return s.length - 1;
      i = nl;
      continue;
    }
    final c = s[i];
    if (c == '(' || c == '{') depth++;
    if (c == ')' || c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return s.length - 1;
}

/// Class name -> its source, across lib/.
Map<String, String> _classes(List<File> files) {
  final out = <String, String>{};
  final decl = RegExp(r'^(?:abstract\s+)?class\s+(\w+)[^{]*\{', multiLine: true);
  for (final f in files) {
    final s = f.readAsStringSync();
    for (final m in decl.allMatches(s)) {
      final end = _close(s, m.end - 1);
      out[m.group(1)!] = s.substring(m.start, end + 1);
    }
  }
  return out;
}

bool _builds(String code, Map<String, String> classes, Set<String> seen) {
  if (code.contains('SheetScaffold(')) return true;
  for (final m in RegExp(r'\b([A-Z_]\w*)\(').allMatches(code)) {
    final name = m.group(1)!;
    for (final candidate in [name, '_${name}State', '${name}State']) {
      if (!seen.add(candidate)) continue;
      final body = classes[candidate];
      if (body != null && body.contains('SheetScaffold(')) return true;
    }
  }
  return false;
}

Map<String, int> _unmigratedNow() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.contains('/l10n/gen/'))
      .toList();
  final classes = _classes(files);
  final counts = <String, int>{};
  for (final f in files) {
    final s = f.readAsStringSync();
    final path = f.path.replaceAll(r'\', '/');
    var from = 0;
    while (true) {
      final at = s.indexOf('showModalBottomSheet', from);
      if (at < 0) break;
      from = at + 1;
      final lineStart = s.lastIndexOf('\n', at) + 1;
      if (s.substring(lineStart, at).trimLeft().startsWith('//')) continue;
      var open = at + 'showModalBottomSheet'.length;
      if (s[open] == '<') {
        // Step over the type argument, which can hold a record's own parens.
        var depth = 0;
        for (; open < s.length; open++) {
          if (s[open] == '<') depth++;
          if (s[open] == '>' && --depth == 0) break;
        }
        open++;
      }
      if (open >= s.length || s[open] != '(') continue;
      final args = s.substring(open, _close(s, open) + 1);
      final b = args.indexOf('builder:');
      if (b < 0 || !_builds(args.substring(b), classes, <String>{})) {
        counts[path] = (counts[path] ?? 0) + 1;
      }
    }
  }
  return counts;
}

void main() {
  test('every modal bottom sheet is a SheetScaffold, or counted below', () {
    final now = _unmigratedNow();
    final grew = <String>[];
    final stale = <String>[];
    for (final e in now.entries) {
      final allowed = _unmigrated[e.key] ?? 0;
      if (e.value > allowed) grew.add('${e.key}: ${e.value} (allowed $allowed)');
    }
    for (final e in _unmigrated.entries) {
      final actual = now[e.key] ?? 0;
      if (actual < e.value) stale.add('${e.key}: ${e.value} -> $actual');
    }
    expect(grew, isEmpty,
        reason: 'a new sheet must lay out through SheetScaffold, so its '
            'actions clear the keyboard and the nav bar');
    expect(stale, isEmpty,
        reason: 'a sheet was migrated or removed; lower its count in '
            '_unmigrated (drop the entry at zero)');
  });

  test('the scan recognises a migrated sheet and an unmigrated one', () {
    final classes = {
      '_GoodSheetState': 'class _GoodSheetState { build() => SheetScaffold(body: x); }',
      '_BadSheetState': 'class _BadSheetState { build() => Padding(child: x); }',
    };
    expect(_builds('builder: (_) => const _GoodSheet()', classes, {}), isTrue);
    expect(_builds('builder: (_) => const _BadSheet()', classes, {}), isFalse);
    expect(_builds('builder: (c) => SheetScaffold(body: Text(a))', classes, {}),
        isTrue);
  });
}
