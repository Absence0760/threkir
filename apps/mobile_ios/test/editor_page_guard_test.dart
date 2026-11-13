// A full-page form lays out through ui_kit's `EditorPage` (directly, or as a
// `showFullScreenForm` sheet's `FullScreenFormBody`), which pins the form's
// one primary action above the keyboard and the nav bar, keeps the fields
// scrolling, and wraps the action row at large text (issue #1374 NS-6, NS-7,
// TO-7, IK-11; conventions § Editors).
//
// Two shapes fail:
//  1. A button placed by hand whose handler is a save (`_save…`, `_submit…`,
//     `_create…`, `_redeem…`) anywhere in a `Scaffold`'s arguments, or in the
//     private widget builders they call. Inside an `EditorPage` or a
//     `FullScreenFormBody` the same button is a second Save beside the pinned
//     one, so it counts there too.
//  2. A `showFullScreenForm` whose builder never reaches a
//     `FullScreenFormBody`, so the sheet would have no page at all.
//
// `_exempt` counts the hand-placed buttons that remain, per file, each with
// why. It may only shrink: a new one fails, and so does an entry gone stale.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _exempt = <String, ({int count, String why})>{
  'lib/screens/club_detail_screen.dart': (
    count: 2,
    why: 'Post (the update composer) and Create event are inline actions on '
        'a detail page, not an editor',
  ),
  'lib/widgets/exercise_catalogue_picker.dart': (
    count: 1,
    why: "the picker's Create custom exercise row is a list action",
  ),
  'lib/screens/route_detail_screen.dart': (
    count: 1,
    why: 'Rate opens the review dialog from a detail page',
  ),
  'lib/screens/settings_body_metrics_screen.dart': (
    count: 1,
    why: 'Save covers one section of a page whose other rows save on pick; '
        'pinned at the foot it would read as saving those rows too',
  ),
};

final _host = RegExp(r'\b(Scaffold|EditorPage|FullScreenFormBody)\(');
final _button = RegExp(
    r'\b(?:FilledButton|TextButton|ElevatedButton|OutlinedButton)(?:\.\w+)?\(');
final _saveHandler = RegExp(r'\b_(?:save|submit|create|redeem)(?:[A-Z]\w*)?\b');

/// The index of the bracket closing the one at [open], skipping comments and
/// string literals.
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
    if (c == "'" || c == '"') {
      // Step over the literal, honouring escapes; an interpolation's own
      // quotes pair up as literals of their own, so its brackets balance.
      var j = i + 1;
      while (j < s.length && s[j] != c) {
        if (s[j] == r'\') j++;
        j++;
      }
      i = j;
      continue;
    }
    if (c == '(' || c == '{' || c == '[') depth++;
    if (c == ')' || c == '}' || c == ']') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return s.length - 1;
}

/// Private widget builders in [s]: name -> source span of the body.
Map<String, (int, int)> _builders(String s) {
  final out = <String, (int, int)>{};
  for (final m in RegExp(r'\bWidget\??\s+(_\w+)\s*\(').allMatches(s)) {
    final params = _close(s, m.end - 1);
    var i = params + 1;
    while (i < s.length && s[i].trim().isEmpty) {
      i++;
    }
    if (s.startsWith('{', i)) {
      out[m.group(1)!] = (i, _close(s, i));
    } else if (s.startsWith('=>', i)) {
      out[m.group(1)!] = (i, s.indexOf(';', i));
    }
  }
  return out;
}

/// Offsets of hand-placed save buttons in [s] (each counted once).
Set<int> _handPlacedSaves(String s) {
  final builders = _builders(s);
  final spans = <(int, int)>[];
  final seen = <String>{};
  void addSpan((int, int) span) {
    spans.add(span);
    final text = s.substring(span.$1, span.$2);
    for (final c in RegExp(r'\b(_\w+)\(').allMatches(text)) {
      final name = c.group(1)!;
      final body = builders[name];
      if (body != null && seen.add(name)) addSpan(body);
    }
  }

  for (final m in _host.allMatches(s)) {
    addSpan((m.end - 1, _close(s, m.end - 1)));
  }
  final hits = <int>{};
  for (final (from, to) in spans) {
    for (final b in _button.allMatches(s.substring(from, to))) {
      final at = from + b.start;
      final args = s.substring(at + b.end - b.start - 1,
          _close(s, at + b.end - b.start - 1) + 1);
      final on = RegExp(r'\bonPressed:').firstMatch(args);
      if (on == null) continue;
      // The handler is what follows onPressed up to the next named argument.
      final rest = args.substring(on.end);
      final next = RegExp(r',\s*\w+:').firstMatch(rest);
      final handler = next == null ? rest : rest.substring(0, next.start);
      if (_saveHandler.hasMatch(handler)) hits.add(at);
    }
  }
  return hits;
}

/// Class name -> source, across lib/.
Map<String, String> _classes(List<File> files) {
  final out = <String, String>{};
  final decl =
      RegExp(r'^(?:abstract\s+)?class\s+(\w+)[^{]*\{', multiLine: true);
  for (final f in files) {
    final s = f.readAsStringSync();
    for (final m in decl.allMatches(s)) {
      out[m.group(1)!] = s.substring(m.start, _close(s, m.end - 1) + 1);
    }
  }
  return out;
}

bool _buildsFormBody(String code, Map<String, String> classes) {
  if (code.contains('FullScreenFormBody(')) return true;
  for (final m in RegExp(r'\b([A-Z_]\w*)\(').allMatches(code)) {
    final name = m.group(1)!;
    for (final c in [name, '_${name}State', '${name}State']) {
      if (classes[c]?.contains('FullScreenFormBody(') ?? false) return true;
    }
  }
  return false;
}

List<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.contains('/l10n/gen/'))
    .toList();

void main() {
  test('no full-page form places its Save by hand, beyond the exemptions', () {
    final grew = <String>[];
    final stale = <String>[];
    final now = <String, int>{};
    for (final f in _libFiles()) {
      final n = _handPlacedSaves(f.readAsStringSync()).length;
      if (n > 0) now[f.path.replaceAll(r'\', '/')] = n;
    }
    for (final e in now.entries) {
      final allowed = _exempt[e.key]?.count ?? 0;
      if (e.value > allowed) grew.add('${e.key}: ${e.value} (allowed $allowed)');
    }
    for (final e in _exempt.entries) {
      if ((now[e.key] ?? 0) < e.value.count) {
        stale.add('${e.key}: ${e.value.count} -> ${now[e.key] ?? 0}');
      }
    }
    expect(grew, isEmpty,
        reason: 'lay the form out with EditorPage (or FullScreenFormBody) '
            'and pass its one primary action as `save:`');
    expect(stale, isEmpty,
        reason: 'a hand-placed Save went away; lower its count in _exempt '
            '(drop the entry at zero)');
  });

  test('every showFullScreenForm builder lays out a FullScreenFormBody', () {
    final files = _libFiles();
    final classes = _classes(files);
    final bare = <String>[];
    for (final f in files) {
      final s = f.readAsStringSync();
      if (f.path.endsWith('widgets/full_screen_form.dart')) continue;
      for (final m in RegExp(r'\bshowFullScreenForm(?:<[^(]*>)?\(').allMatches(s)) {
        final args = s.substring(m.end - 1, _close(s, m.end - 1) + 1);
        final b = args.indexOf('builder:');
        if (b < 0 || !_buildsFormBody(args.substring(b), classes)) {
          bare.add('${f.path}:${s.substring(0, m.start).split('\n').length}');
        }
      }
    }
    expect(bare, isEmpty);
  });

  test('the scan sees a hand-placed Save and ignores a pinned one', () {
    expect(
        _handPlacedSaves('''
          Widget build(BuildContext c) => Scaffold(
            appBar: AppBar(actions: [TextButton(onPressed: _save, child: x)]),
            body: _footer(),
          );
          Widget _footer() => FilledButton(onPressed: _busy ? null : _submit, child: y);
        ''').length,
        2);
    expect(
        _handPlacedSaves('''
          Widget build(BuildContext c) => EditorPage(
            title: t,
            save: EditorSave(label: l, onPressed: _save),
            fields: [TextButton(onPressed: _addRow, child: z)],
          );
        ''').length,
        0);
    expect(
        _handPlacedSaves('''
          Widget build(BuildContext c) => EditorPage(
            title: t,
            save: EditorSave(label: l, onPressed: _save),
            fields: [FilledButton(onPressed: _saveDraft, child: z)],
          );
        ''').length,
        1,
        reason: 'a second Save inside the page counts');
    expect(
        _handPlacedSaves('''
          Widget build(BuildContext c) => Scaffold(
            body: FilledButton(onPressed: _saving ? null : _open, child: z),
          );
        ''').length,
        0,
        reason: '_saving is a flag, not a save handler');
  });
}
