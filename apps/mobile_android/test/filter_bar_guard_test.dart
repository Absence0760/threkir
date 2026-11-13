// Every list's search and quick filters go through ui_kit's `FilterBar`
// (issue #1374): one `AppSearchField`, which always has a clear button, and
// one line of chips that scrolls sideways rather than wrapping, with the rest
// behind a Filters sheet. Before it there were 20 hand-built search fields in
// about six styles, 11 with no clear button, and six filter idioms across the
// Fitness tabs.
//
// Two scans, each with a per-file count of the copies not yet migrated. The
// maps may only shrink: a new copy fails, and so does an entry whose count
// has fallen without the map being lowered.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Hand-built search fields (`prefixIcon: Icon(Icons.search)`) still to move
/// onto `AppSearchField`.
const _unmigratedSearch = <String, int>{
  'lib/screens/help_screen.dart': 1,
  'lib/screens/messages_screen.dart': 1,
  'lib/screens/nearby_area_screen.dart': 1,
  'lib/screens/plan_library_screen.dart': 1,
  'lib/screens/privacy_zones_screen.dart': 1,
  'lib/screens/route_builder_screen.dart': 1,
  'lib/screens/route_picker_screen.dart': 1,
  'lib/screens/routes_heatmap_screen.dart': 1,
  'lib/screens/routine_public_library_screen.dart': 1,
  'lib/widgets/exercise_catalogue_picker.dart': 1,
  'lib/widgets/nutrition_log_sheet.dart': 1,
};

/// The hub tab bodies whose toolbar is a list's control row. Chips in a card
/// (a race's tags) and chips inside a sheet are not a toolbar and are not
/// counted; a `Wrap` of filter chips or a `ChoiceChipRow` anywhere else in
/// these files is.
const _listTabs = [
  'lib/screens/runs_screen.dart',
  'lib/screens/plans_screen.dart',
  'lib/screens/races_screen.dart',
  'lib/screens/routes_screen.dart',
  'lib/screens/explore_routes_screen.dart',
  'lib/screens/global_segments_screen.dart',
  'lib/screens/gym_screen.dart',
  'lib/screens/nutrition_screen.dart',
  'lib/screens/feed_screen.dart',
  'lib/screens/people_screen.dart',
  'lib/screens/clubs_screen.dart',
  'lib/screens/discover_screen.dart',
  'lib/screens/challenges_screen.dart',
];

/// Wrapping chip rows still in a list tab's toolbar. Empty since the Social
/// tabs moved onto FilterBar; it stays so a new one fails by name.
const _unmigratedChipWraps = <String, int>{};

/// [source] with comments removed and every string literal emptied, so a
/// bracket inside either can't end a scan early. Newlines are kept.
String _codeOnly(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end;
    } else if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
    } else if (source[i] == "'" || source[i] == '"') {
      final triple = source.startsWith(source[i] * 3, i);
      final quote = triple ? source[i] * 3 : source[i];
      final raw = i > 0 && source[i - 1] == 'r';
      var j = i + quote.length;
      while (j < source.length && !source.startsWith(quote, j)) {
        if (!raw && source[j] == r'\') j++;
        j++;
      }
      out.write("''");
      i = j + quote.length;
    } else {
      out.write(source[i]);
      i++;
    }
  }
  return out.toString();
}

/// Index of the bracket that closes the one at [open].
int _close(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    final c = s[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return s.length - 1;
}

final _search = RegExp(r'prefixIcon:\s*(?:const\s+)?Icon\(\s*Icons\.search\b');
final _chip = RegExp(r'\b(?:FilterChip|ChoiceChip|InputChip)\(|\bbuildChoiceChip\b');
final _sheet = RegExp(r'\b(?:showFilterSheet|SheetScaffold|showModalBottomSheet)\s*(?:<[^(]*>)?\(');

int _countChipWraps(String code) {
  final sheets = [
    for (final m in _sheet.allMatches(code)) (m.start, _close(code, m.end - 1)),
  ];
  bool inSheet(int at) => sheets.any((r) => at > r.$1 && at < r.$2);
  var n = 0;
  for (final m in RegExp(r'\bWrap\(').allMatches(code)) {
    if (inSheet(m.start)) continue;
    final args = code.substring(m.end - 1, _close(code, m.end - 1));
    if (_chip.hasMatch(args)) n++;
  }
  for (final m in RegExp(r'\bChoiceChipRow\s*(?:<[^(]*>)?\(').allMatches(code)) {
    if (!inSheet(m.start)) n++;
  }
  return n;
}

Map<String, int> _drift(Map<String, int> found, Map<String, int> pinned) => {
      for (final path in {...found.keys, ...pinned.keys})
        if ((found[path] ?? 0) != (pinned[path] ?? 0))
          path: found[path] ?? 0,
    };

void main() {
  test('every search field is AppSearchField', () {
    final found = <String, int>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      final n = _search.allMatches(_codeOnly(f.readAsStringSync())).length;
      if (n > 0) found[path] = n;
    }
    expect(
      _drift(found, _unmigratedSearch),
      isEmpty,
      reason: 'A new search field: build it as ui_kit\'s AppSearchField '
          '(inside a FilterBar on a list), which always has a clear button. '
          'A count that fell: lower _unmigratedSearch to match. Map of '
          'path -> count found:',
    );
  });

  test('a list tab\'s chips sit on one FilterBar line, never in a Wrap', () {
    final found = <String, int>{};
    for (final path in _listTabs) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is gone; update _listTabs');
      final n = _countChipWraps(_codeOnly(file.readAsStringSync()));
      if (n > 0) found[path] = n;
    }
    expect(
      _drift(found, _unmigratedChipWraps),
      isEmpty,
      reason: 'Put a list tab\'s quick chips in FilterBar.chips (one line that '
          'scrolls sideways) and the rest in its Filters sheet, where chips '
          'may wrap. A count that fell: lower _unmigratedChipWraps to match. '
          'Map of path -> count found:',
    );
  });

  test('the scan sees a wrapped chip row and ignores one inside a sheet', () {
    expect(_countChipWraps('Wrap(children: [ChoiceChip(label: x)])'), 1);
    expect(_countChipWraps('ChoiceChipRow<int>(options: o)'), 1);
    expect(
      _countChipWraps(
          'showFilterSheet(builder: (c, s) => Wrap(children: [FilterChip()]))'),
      0,
    );
    expect(_countChipWraps('Wrap(children: [Chip(label: x)])'), 0);
  });
}
