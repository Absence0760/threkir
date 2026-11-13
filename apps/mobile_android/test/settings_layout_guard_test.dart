// The settings pages are built from ui_kit's `SettingsList`, `ListRow` and
// `SectionHeader`, so the group heading and the row anatomy are the
// components' and not each page's (issue #1374). Before, one area separated
// groups four ways — a `SectionHeader`, a hand-built uppercase eyebrow, a
// `titleMedium` title and a bare `Divider` — and wrote its nav, switch and
// value rows out by hand about a hundred times.
//
// In You and every settings page this fails on:
//   1. an eyebrow built by hand: `.toUpperCase()` on a `labelSmall` label;
//   2. a section title built by hand: a `titleMedium` / `titleSmall` text
//      style (`SectionHeader.title` is the heading form);
//   3. a settings row built by hand: a `ListTile(` or `SwitchListTile(`
//      (`ListRow.nav` / `.value` / `.toggle`).
// The counts below are what is left to migrate. They may only shrink: a
// file over its count fails, and so does a file under it, until the entry
// is lowered or removed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Hand-built rows still on the pages not yet moved to `SettingsList`.
const _rowsLeft = <String, int>{
  'lib/screens/settings_about_screen.dart': 8,
  'lib/screens/settings_account_screen.dart': 15,
  'lib/screens/settings_body_metrics_screen.dart': 3,
  'lib/screens/settings_integrations_screen.dart': 11,
  'lib/screens/settings_pro_screen.dart': 7,
  'lib/screens/settings_safety_screen.dart': 7,
};

/// Title styles that are not section headings.
const _titlesLeft = <String, (int, String)>{
  'lib/screens/settings_integrations_screen.dart': (
    2,
    'the HR strap and treadmill scan sheets title themselves; they move to '
        'SheetScaffold, which owns a sheet title',
  ),
  'lib/screens/settings_pro_screen.dart': (
    1,
    'the active-plan row emphasises its own title; it is a row, not a heading',
  ),
};

final _row = RegExp(r'(?<![A-Za-z_])(ListTile|SwitchListTile)\(');
final _title = RegExp(r'textTheme\s*\.\s*(titleMedium|titleSmall)');

List<File> _scope() => [
      File('lib/screens/you_screen.dart'),
      ...Directory('lib/screens')
          .listSync()
          .whereType<File>()
          .where((f) {
            final name = f.uri.pathSegments.last;
            return name.startsWith('settings_') && name.endsWith('.dart');
          }),
    ]..sort((a, b) => a.path.compareTo(b.path));

String _path(File f) => f.path.replaceAll(r'\', '/');

/// The source with line comments removed, so a comment naming a widget is
/// not counted as one.
String _code(File f) => f
    .readAsLinesSync()
    .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
    .join('\n');

void main() {
  final files = _scope();

  test('the scope is the You tab and the settings pages', () {
    final names = files.map(_path).toSet();
    expect(names, contains('lib/screens/you_screen.dart'));
    expect(names, contains('lib/screens/settings_screen.dart'));
    expect(names, contains('lib/screens/settings_preferences_screen.dart'));
  });

  test('no hand-built eyebrow: an uppercased labelSmall label', () {
    final offenders = <String>[];
    for (final f in files) {
      final src = _code(f);
      for (final m in RegExp(r'\.toUpperCase\(\)').allMatches(src)) {
        final after = src.substring(
            m.end, (m.end + 300).clamp(0, src.length));
        if (after.contains('labelSmall')) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${_path(f)}:$line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'A group label is SectionHeader (or a SettingsSection label).');
  });

  test('no hand-built section title past the counts left', () {
    final problems = <String>[];
    for (final f in files) {
      final n = _title.allMatches(_code(f)).length;
      final allowed = _titlesLeft[_path(f)]?.$1 ?? 0;
      if (n > allowed) {
        problems.add('${_path(f)}: $n title styles, $allowed allowed — use '
            'SectionHeader.title for a section heading');
      } else if (n < allowed) {
        problems.add('${_path(f)}: $n title styles, $allowed listed — lower '
            'the count in _titlesLeft');
      }
    }
    expect(problems, isEmpty);
  });

  test('no hand-built settings row past the counts left', () {
    final problems = <String>[];
    for (final f in files) {
      final n = _row.allMatches(_code(f)).length;
      final allowed = _rowsLeft[_path(f)] ?? 0;
      if (n > allowed) {
        problems.add('${_path(f)}: $n hand-built rows, $allowed allowed — use '
            'ListRow.nav / .value / .toggle');
      } else if (n < allowed) {
        problems.add('${_path(f)}: $n hand-built rows, $allowed listed — '
            'lower the count in _rowsLeft');
      }
    }
    expect(problems, isEmpty);
  });

  test('every listed file is still in scope', () {
    final names = files.map(_path).toSet();
    expect(
      {..._rowsLeft.keys, ..._titlesLeft.keys}.where((k) => !names.contains(k)),
      isEmpty,
    );
  });

  test('the duplicate eyebrow widget stays gone', () {
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.dart') &&
            !f.path.contains('/l10n/gen/') &&
            _code(f).contains('FormSectionLabel'))
        .map(_path)
        .toList();
    expect(hits, isEmpty,
        reason: 'FormSectionLabel was a second eyebrow; use SectionHeader.');
  });
}
