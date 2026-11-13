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
//
// A sheet that holds typed text is opened with `showFormSheet` and builds a
// `SheetDiscardGuard`, so a swipe down, a barrier tap or Back asks before the
// text is lost (issue #1374 NS-13). A plain `showModalBottomSheet` closes on
// a swipe through `Navigator.pop`, which no `PopScope` can stop.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sheets still laid out by hand, per file. Every one is in a file another
/// lane of issue #1374 round 2 owns, and moves with that lane's rework.
const _unmigrated = <String, int>{
  // The editor lane rebuilds these screens on `EditorPage`.
  'lib/screens/add_run_screen.dart': 1,
  'lib/screens/plan_new_screen.dart': 1,
};

/// `showFormSheet` itself calls `showModalBottomSheet` with the caller's
/// builder, so it is not a sheet of its own.
const _helper = 'lib/widgets/form_sheet.dart';

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

Iterable<String> _candidates(String name) =>
    [name, '_${name}State', '${name}State'];

final _scaffold = RegExp(r'\bSheetScaffold(\.floating)?\(');
final _guard = RegExp(r'\bSheetDiscardGuard\(');

/// Whether [code] builds [token] itself, or builds a widget whose class (or
/// its `State`) does.
bool _builds(String code, Map<String, String> classes, Set<String> seen,
    [Pattern? token]) {
  token ??= _scaffold;
  if (code.contains(token)) return true;
  for (final m in RegExp(r'\b([A-Z_]\w*)\(').allMatches(code)) {
    for (final candidate in _candidates(m.group(1)!)) {
      if (!seen.add(candidate)) continue;
      final body = classes[candidate];
      if (body != null && body.contains(token)) return true;
    }
  }
  return false;
}

final _textField = RegExp(r'\b(TextField|TextFormField)\(');

/// Whether [code], or any widget it builds however deep, builds a text field.
bool _holdsText(String code, Map<String, String> classes, Set<String> seen) {
  if (_textField.hasMatch(code)) return true;
  for (final m in RegExp(r'\b([A-Z_]\w*)\(').allMatches(code)) {
    for (final candidate in _candidates(m.group(1)!)) {
      if (!seen.add(candidate)) continue;
      final body = classes[candidate];
      if (body != null && _holdsText(body, classes, seen)) return true;
    }
  }
  return false;
}

class _Call {
  _Call(this.path, this.line, this.opener, this.builder);
  final String path;
  final int line;
  final String opener;
  final String builder;
  @override
  String toString() => '$path:$line ($opener)';
}

List<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.contains('/l10n/gen/'))
    .toList();

List<_Call> _calls(List<File> files) {
  final out = <_Call>[];
  final opener = RegExp(r'(?<![\w.])(showModalBottomSheet|showFormSheet)\b');
  for (final f in files) {
    final path = f.path.replaceAll(r'\', '/');
    if (path == _helper) continue;
    final s = f.readAsStringSync();
    for (final m in opener.allMatches(s)) {
      final at = m.start;
      final lineStart = s.lastIndexOf('\n', at) + 1;
      if (s.substring(lineStart, at).trimLeft().startsWith('//')) continue;
      var open = m.end;
      if (open < s.length && s[open] == '<') {
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
      out.add(_Call(path, '\n'.allMatches(s.substring(0, at)).length + 1,
          m.group(1)!, b < 0 ? '' : args.substring(b)));
    }
  }
  return out;
}

List<String> _countDrift(Map<String, int> now, Map<String, int> allowed) {
  final out = <String>[];
  for (final e in now.entries) {
    final a = allowed[e.key] ?? 0;
    if (e.value > a) out.add('${e.key}: ${e.value} (allowed $a)');
  }
  for (final e in allowed.entries) {
    final actual = now[e.key] ?? 0;
    if (actual < e.value) out.add('${e.key}: stale, ${e.value} -> $actual');
  }
  return out;
}

void main() {
  final files = _libFiles();
  final classes = _classes(files);
  final calls = _calls(files);

  test('every modal bottom sheet is a SheetScaffold, or counted below', () {
    final now = <String, int>{};
    for (final c in calls) {
      if (!_builds(c.builder, classes, <String>{})) {
        now[c.path] = (now[c.path] ?? 0) + 1;
      }
    }
    expect(_countDrift(now, _unmigrated), isEmpty,
        reason: 'a new sheet must lay out through SheetScaffold, so its '
            'actions clear the keyboard and the nav bar; a migrated one '
            'lowers its count in _unmigrated (drop the entry at zero)');
  });

  test('a sheet holding typed text asks before a swipe, a tap or Back drops it',
      () {
    final unguarded = <String>[];
    for (final c in calls) {
      if (!_holdsText(c.builder, classes, <String>{})) continue;
      final guarded = c.opener == 'showFormSheet' &&
          _builds(c.builder, classes, <String>{}, _guard);
      if (!guarded) unguarded.add('$c');
    }
    expect(unguarded, isEmpty,
        reason: 'open the sheet with showFormSheet and wrap its content in '
            'SheetDiscardGuard with an isDirty that compares the fields to '
            'what they opened with. A search over a list is AppSearchField, '
            'which this does not count: the query is not a draft');
  });

  test('showFormSheet and SheetDiscardGuard always come together', () {
    final bad = <String>[];
    for (final c in calls) {
      final guard =
          _builds(c.builder, classes, <String>{}, _guard);
      final form = c.opener == 'showFormSheet';
      if (guard != form) bad.add('$c guard=$guard');
    }
    expect(bad, isEmpty,
        reason: 'showFormSheet turns off the theme drag handle that '
            'SheetDiscardGuard redraws, and a guard opened any other way is '
            'closed by a swipe without asking');
  });

  test('the scan recognises a migrated sheet and an unmigrated one', () {
    final classes = {
      '_GoodSheetState': 'class _GoodSheetState { build() => SheetScaffold(body: x); }',
      '_BadSheetState': 'class _BadSheetState { build() => Padding(child: x); }',
      '_FieldState': 'class _FieldState { build() => TextField(); }',
      '_FormSheetState':
          'class _FormSheetState { build() => Column(children: [_Field()]); }',
    };
    expect(_builds('builder: (_) => const _GoodSheet()', classes, {}), isTrue);
    expect(_builds('builder: (_) => const _BadSheet()', classes, {}), isFalse);
    expect(_builds('builder: (c) => SheetScaffold(body: Text(a))', classes, {}),
        isTrue);
    expect(
        _builds('builder: (c) => SheetScaffold.floating(body: x)', classes, {}),
        isTrue);
    expect(_holdsText('builder: (_) => _FormSheet()', classes, {}), isTrue);
    expect(_holdsText('builder: (_) => _GoodSheet()', classes, {}), isFalse);
  });
}
