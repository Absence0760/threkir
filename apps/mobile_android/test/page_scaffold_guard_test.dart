// Every page is laid out by a ui_kit page template (`PushedPage`,
// `DetailPage`, `EditorPage`, `MapFirstPage`, `HubTabBody`, `RootPage`,
// `ConversationPage`), which owns the app bar, the primary action and the
// system-bar and keyboard insets (issue #1374). A raw `Scaffold` puts all of
// that back in the screen's hands.
//
// The pages still built on a raw `Scaffold` are counted per file in
// `_rawScaffolds`, each with why. The map may only shrink: a new raw
// `Scaffold` fails, and so does an entry that has gone stale because its page
// moved to a template or was removed. `detail_page_guard_test.dart` counts
// hand-built app bars; this one also catches a page with no bar at all.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _rawScaffolds = <String, ({int count, String why})>{
  'lib/screens/home_screen.dart': (
    count: 1,
    why: 'the app shell: rail or bottom bar, docked FAB and the root pages; '
        'one tree for both layouts keeps a run alive across rotation',
  ),
  'lib/screens/run_screen.dart': (
    count: 1,
    why: 'the full-screen recorder',
  ),
  'lib/screens/onboarding_screen.dart': (
    count: 1,
    why: 'the signed-out full-bleed intro carousel',
  ),
  'lib/widgets/nutrition_log_sheet.dart': (
    count: 1,
    why: 'the barcode camera, a full-bleed camera surface',
  ),
  'lib/screens/avatar_crop_screen.dart': (
    count: 1,
    why: 'not migrated yet: needs a non-scrolling EditorPage',
  ),
  'lib/screens/coach_screen.dart': (
    count: 1,
    why: 'not migrated yet: a conversation (ConversationPage)',
  ),
  'lib/screens/confirm_age_screen.dart': (
    count: 1,
    why: 'not migrated yet: a gate that cannot be dismissed (EditorPage)',
  ),
  'lib/screens/group_thread_screen.dart': (
    count: 1,
    why: 'not migrated yet: a conversation (ConversationPage)',
  ),
  'lib/screens/gym_session_screen.dart': (
    count: 1,
    why: 'not migrated yet: EditorPage with the execution band as its bar',
  ),
  'lib/screens/live_spectator_screen.dart': (
    count: 1,
    why: 'not migrated yet: the error branch only (MapFirstPage)',
  ),
};

final _raw = RegExp(r'(?<![\w.])Scaffold\(');

String _code(String source) => source
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

int _count(String source) => _raw.allMatches(_code(source)).length;

void main() {
  test('the pattern matches a raw Scaffold and nothing that merely contains '
      'the name', () {
    expect(_count('return Scaffold(body: x);'), 1);
    expect(_count('child: Scaffold('), 1);
    for (final lookAlike in [
      'Scaffold.of(context)',
      'ScaffoldMessenger.of(context)',
      'SheetScaffold(child: x)',
      '_buildScaffold(context)',
      '// Scaffold( in a comment',
    ]) {
      expect(_count(lookAlike), 0, reason: lookAlike);
    }
  });

  test('pages build a ui_kit template, not a raw Scaffold', () {
    final found = <String, int>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('/l10n/gen/')) continue;
      final n = _count(f.readAsStringSync());
      if (n > 0) found[f.path] = n;
    }

    final problems = <String>[];
    found.forEach((path, n) {
      final allowed = _rawScaffolds[path]?.count ?? 0;
      if (n > allowed) {
        problems.add('$path builds $n raw Scaffold(s), $allowed allowed: lay '
            'the page out with PushedPage, DetailPage, EditorPage, '
            'MapFirstPage, HubTabBody, RootPage or ConversationPage');
      }
    });
    _rawScaffolds.forEach((path, entry) {
      final n = found[path] ?? 0;
      if (n < entry.count) {
        problems.add('$path now builds $n raw Scaffold(s) but is allowed '
            '${entry.count}: lower or drop its _rawScaffolds entry');
      }
    });
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
