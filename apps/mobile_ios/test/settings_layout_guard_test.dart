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
// Outside them, an uppercased `labelSmall` label is counted per file against
// `_eyebrowsLeft`, each with the reason it is not a group heading.
// The counts below are what is left to migrate. They may only shrink: a
// file over its count fails, and so does a file under it, until the entry
// is lowered or removed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Hand-built rows still on the pages not yet moved to `SettingsList`.
const _rowsLeft = <String, int>{
  'lib/screens/settings_about_screen.dart': 8,
  'lib/screens/settings_account_screen.dart': 13,
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

/// Uppercased `labelSmall` labels left outside the settings pages, and why
/// each is not a group heading. A heading that names a group of rows or a
/// section is `SectionHeader`; these are a figure's own label, a table's
/// column head, a calendar cell, a status word. The counts may only shrink.
const _eyebrowsLeft = <String, (int, String)>{
  'lib/screens/feed_screen.dart': (1, "a stat's label under its value"),
  'lib/screens/gym_exercise_screen.dart': (
    1,
    "the best e1RM figure's label under its value",
  ),
  'lib/screens/gym_records_screen.dart': (
    1,
    "a record's label in a TermValueRow",
  ),
  'lib/screens/live_spectator_screen.dart': (
    1,
    "a live stat's label, scaled down rather than cut",
  ),
  'lib/screens/event_detail_screen.dart': (1, "a figure's label above it"),
  'lib/screens/plan_detail_screen.dart': (
    2,
    "the phase strip's steps and a week's phase beside its heading",
  ),
  'lib/screens/progress_screen.dart': (1, "a period total's label"),
  'lib/screens/runs_screen.dart': (1, "a summary figure's label"),
  'lib/screens/workout_detail_screen.dart': (
    1,
    "a target figure's label in the hero, spoken as written",
  ),
  'lib/widgets/badge_grid.dart': (1, "a badge's tier, in the tier colour"),
  'lib/widgets/dm_route_attachment.dart': (
    1,
    'the kind line of a route shared in a message bubble',
  ),
  'lib/widgets/pacing_strategy_section.dart': (1, "the table's column heads"),
  'lib/widgets/plan_day_cell.dart': (1, "a calendar cell's workout kind"),
  'lib/widgets/race_predictor_card.dart': (1, "the table's column heads"),
  'lib/widgets/route_conditions.dart': (
    1,
    "a report's severity word beside its condition pill, in its colour",
  ),
  'lib/widgets/workout_review_section.dart': (1, "the table's column heads"),
};

/// Uppercased `labelSmall` labels in [src]: `.toUpperCase()` with a
/// `labelSmall` style within the next 300 characters.
int eyebrowsIn(String src) => RegExp(r'\.toUpperCase\(\)')
    .allMatches(src)
    .where((m) => src
        .substring(m.end, (m.end + 300).clamp(0, src.length))
        .contains('labelSmall'))
    .length;

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

  test('outside settings, the hand-built eyebrows left only shrink', () {
    final scoped = files.map(_path).toSet();
    final problems = <String>[];
    final found = <String, int>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = _path(f);
      if (!path.endsWith('.dart') ||
          path.contains('/l10n/gen/') ||
          scoped.contains(path)) {
        continue;
      }
      final n = eyebrowsIn(_code(f));
      if (n > 0) found[path] = n;
    }
    for (final e in found.entries) {
      final allowed = _eyebrowsLeft[e.key]?.$1 ?? 0;
      if (e.value > allowed) {
        problems.add('${e.key}: ${e.value} uppercased labelSmall labels, '
            '$allowed allowed — a group heading is SectionHeader');
      }
    }
    for (final e in _eyebrowsLeft.entries) {
      final n = found[e.key] ?? 0;
      if (n < e.value.$1) {
        problems.add('${e.key}: $n left, ${e.value.$1} listed — lower the '
            'count or remove the entry');
      }
      if (e.value.$2.trim().isEmpty) problems.add('${e.key}: needs a reason');
    }
    expect(problems, isEmpty);
  });

  test('the eyebrow scan counts an uppercased labelSmall and nothing else', () {
    expect(
        eyebrowsIn("Text(l.x.toUpperCase(), style: t.textTheme.labelSmall)"),
        1);
    expect(eyebrowsIn("Text(l.x.toUpperCase(), style: t.textTheme.titleSmall)"),
        0);
    expect(eyebrowsIn("Text(l.x, style: t.textTheme.labelSmall)"), 0);
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
