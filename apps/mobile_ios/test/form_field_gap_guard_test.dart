// Stacked form fields go in ui_kit's `FieldColumn`, which owns the one gap
// between them (issue #1374). An outlined field's floating label sits on
// its top border, half of it above the field, so fields that touched drew
// each label over the field above ("Half-width, m" on the bearing's border
// on the line calibration screen), and forms spaced their fields by hand
// with 0, 8, 12, 16 or 20.
//
// The scan reads every `children:` list in `lib/` outside a `Row`, `Wrap`
// or `FieldColumn` and counts two fields that follow each other with
// nothing between them but a `SizedBox(height: …)`. A field is a
// `TextField`, `TextFormField`, `DropdownButtonFormField`, `InputDecorator`
// or `DropdownMenu`, the same wrapped in `Padding` / `InkWell` /
// `Semantics` / `Expanded` and the like, a helper (a `_field(...)` method,
// a widget class) whose body is one, or a `Row` holding one; a `for` that
// repeats a field counts once. The map below may only shrink: a new pair
// fails, and so does an entry whose count has fallen without the map being
// lowered.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Touching fields not yet in a FieldColumn, with the reason each is left.
const _unmigrated = <String, (int, String)>{
  'lib/screens/settings_body_metrics_screen.dart': (
    1,
    'the settings pages are being reworked by their own lane of issue '
        '#1374; move the pair onto FieldColumn there',
  ),
  'lib/screens/settings_preferences_screen.dart': (
    1,
    'the settings pages are being reworked by their own lane of issue '
        '#1374; move the pair onto FieldColumn there',
  ),
  'lib/screens/settings_safety_screen.dart': (
    1,
    'the settings pages are being reworked by their own lane of issue '
        '#1374; move the pair onto FieldColumn there',
  ),
};

/// [s] with comments removed and every string literal emptied, keeping the
/// code inside an interpolation, so neither a bracket in a string nor a
/// quote inside `${…}` can end a scan early.
String _codeOnly(String s) {
  final out = StringBuffer();
  // Open string quotes (`r` prefixed when raw) and `}` for an interpolation.
  final stack = <String>[];
  final braces = <int>[];
  var i = 0;
  while (i < s.length) {
    final top = stack.isEmpty ? null : stack.last;
    if (top != null && top != '}') {
      final raw = top.startsWith('r');
      final quote = raw ? top.substring(1) : top;
      if (s.startsWith(quote, i)) {
        stack.removeLast();
        out.write("'");
        i += quote.length;
      } else if (!raw && s[i] == r'\') {
        i += 2;
      } else if (!raw && s.startsWith(r'${', i)) {
        stack.add('}');
        braces.add(0);
        i += 2;
      } else {
        i++;
      }
      continue;
    }
    if (s.startsWith('//', i)) {
      final end = s.indexOf('\n', i);
      i = end < 0 ? s.length : end;
    } else if (s.startsWith('/*', i)) {
      final end = s.indexOf('*/', i + 2);
      i = end < 0 ? s.length : end + 2;
    } else if (s[i] == "'" || s[i] == '"') {
      final quote = s.startsWith(s[i] * 3, i) ? s[i] * 3 : s[i];
      stack.add(i > 0 && s[i - 1] == 'r' ? 'r$quote' : quote);
      out.write("'");
      i += quote.length;
    } else if (top == '}' && s[i] == '}' && braces.last == 0) {
      stack.removeLast();
      braces.removeLast();
      i++;
    } else {
      if (top == '}' && s[i] == '{') braces[braces.length - 1]++;
      if (top == '}' && s[i] == '}') braces[braces.length - 1]--;
      if (top == null) out.write(s[i]);
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

/// [body] split at its top-level commas.
List<String> _split(String body) {
  final out = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ',' && depth == 0) {
      out.add(body.substring(start, i).trim());
      start = i + 1;
    }
  }
  final last = body.substring(start).trim();
  if (last.isNotEmpty) out.add(last);
  return out;
}

final _fieldCtor = RegExp(
    r'^(?:TextField|TextFormField|DropdownButtonFormField|InputDecorator|DropdownMenu)\b');
final _anyField = RegExp(
    r'\b(?:TextField|TextFormField|DropdownButtonFormField|InputDecorator|DropdownMenu)\s*(?:<[^>(]*>)?\(');
final _call = RegExp(r'^(\w+)\s*(?:<[^>(]*>)?\(');

/// [e] without a leading `const`, `if (…)` or `for (…)`.
String _strip(String e) {
  var x = e.trimLeft();
  for (;;) {
    if (x.startsWith('const ')) {
      x = x.substring(6).trimLeft();
    } else if (RegExp(r'^(?:if|for)\s*\(').hasMatch(x)) {
      x = x.substring(_close(x, x.indexOf('(')) + 1).trimLeft();
    } else {
      return x;
    }
  }
}

/// The expression a function or a `build` returns, when it has one return.
String? _returned(String afterParams) {
  final rest = afterParams.trimLeft();
  if (rest.startsWith('=>')) return rest.substring(2);
  if (!rest.startsWith('{')) return null;
  final body = rest.substring(0, _close(rest, 0) + 1);
  final r = RegExp(r'\breturn\s+').allMatches(body).toList();
  return r.length == 1 ? body.substring(r.first.end) : null;
}

/// Names of the helpers in [code] that build one field: a method returning a
/// Widget, or a StatelessWidget whose build does.
Set<String> _helpers(String code) {
  final out = <String>{};
  for (final m
      in RegExp(r'Widget\s+(_?\w+)\s*(?:<[^>(]*>)?\(').allMatches(code)) {
    final open = code.indexOf('(', m.start);
    final e = _returned(code.substring(_close(code, open) + 1));
    if (e != null && _fieldCtor.hasMatch(_strip(e))) out.add(m.group(1)!);
  }
  for (final m in RegExp(r'class\s+(\w+)\s+extends\s+StatelessWidget')
      .allMatches(code)) {
    final open = code.indexOf('{', m.end);
    final body = code.substring(open, _close(code, open) + 1);
    final b = RegExp(r'Widget\s+build\s*\(').firstMatch(body);
    if (b == null) continue;
    final e = _returned(body.substring(_close(body, b.end - 1) + 1));
    if (e != null && _fieldCtor.hasMatch(_strip(e))) out.add(m.group(1)!);
  }
  return out;
}

const _wrappers = {
  'Padding', 'Semantics', 'InkWell', 'GestureDetector', 'Expanded', //
  'Flexible', 'Tooltip', 'KeyedSubtree', 'Focus', 'MergeSemantics',
  'ExcludeSemantics', 'Opacity', 'IgnorePointer', 'AbsorbPointer',
};

bool _isField(String element, Set<String> helpers) {
  final x = _strip(element);
  if (_fieldCtor.hasMatch(x)) return true;
  final head = _call.firstMatch(x)?.group(1);
  if (head == null) return false;
  if (helpers.contains(head)) return true;
  final args = x.substring(x.indexOf('('));
  if (_wrappers.contains(head)) {
    for (final a in _split(args.substring(1, _close(args, 0)))) {
      if (a.startsWith('child:') &&
          _isField(a.substring('child:'.length), helpers)) {
        return true;
      }
    }
  }
  // A row of fields stands where a field would.
  if (head == 'Row') {
    if (_anyField.hasMatch(args)) return true;
    for (final h in helpers) {
      if (RegExp('\\b$h\\s*(?:<[^>(]*>)?\\(').hasMatch(args)) return true;
    }
  }
  return false;
}

/// [elements] with each `...[ ]` spread laid out in place.
List<String> _flat(List<String> elements) => [
      for (final e in elements)
        if (_strip(e).startsWith('...['))
          ..._flat(_split(_strip(e).substring(4, _close(_strip(e), 3))))
        else
          e,
    ];

final _gap = RegExp(r'^SizedBox\s*\(\s*height:');

/// Touching field pairs in [source]; [shared] adds helper widgets declared
/// in other files.
int countTouching(String source, {Set<String> shared = const {}}) {
  final code = _codeOnly(source);
  final helpers = {..._helpers(code), ...shared};
  var n = 0;
  for (final m in RegExp(r'children:\s*(?:<\w+>)?\[').allMatches(code)) {
    var depth = 0;
    var j = m.start - 1;
    for (; j >= 0; j--) {
      final c = code[j];
      if (c == ')' || c == ']' || c == '}') depth++;
      if (c == '(' || c == '[' || c == '{') {
        if (depth == 0) break;
        depth--;
      }
    }
    final owner = RegExp(r'(\w+)\s*(?:<[^>(]*>)?\s*$')
        .firstMatch(code.substring(0, j < 0 ? 0 : j))
        ?.group(1);
    if (owner == 'Row' || owner == 'Wrap' || owner == 'FieldColumn') continue;
    final open = m.end - 1;
    var fieldAbove = false;
    for (final e in _flat(_split(code.substring(open + 1, _close(code, open))))) {
      final field = _isField(e, helpers);
      if (field && RegExp(r'^for\s*\(').hasMatch(e)) n++;
      if (field && fieldAbove) n++;
      // A hand gap between two fields leaves them touching for this rule.
      if (!_gap.hasMatch(_strip(e))) fieldAbove = field;
    }
  }
  return n;
}

void main() {
  test('stacked form fields are spaced by FieldColumn', () {
    final files = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.contains('/l10n/'))
          f,
    ];
    final shared = <String>{
      for (final f in files)
        ..._helpers(_codeOnly(f.readAsStringSync()))
            .where((n) => !n.startsWith('_') && n != 'build'),
    };
    final found = <String, int>{};
    for (final f in files) {
      final n = countTouching(f.readAsStringSync(), shared: shared);
      if (n > 0) found[f.path.replaceAll(r'\', '/')] = n;
    }
    final drift = {
      for (final path in {...found.keys, ..._unmigrated.keys})
        if ((found[path] ?? 0) != (_unmigrated[path]?.$1 ?? 0))
          path: found[path] ?? 0,
    };
    expect(
      drift,
      isEmpty,
      reason: 'Put stacked fields in ui_kit\'s FieldColumn (no SizedBox '
          'between them): it places the one field gap, so no floating label '
          'sits on the field above. A count that fell: lower _unmigrated to '
          'match. Map of path -> count found:',
    );
  });

  group('the scan', () {
    test('counts fields with no gap or a hand gap between them', () {
      expect(countTouching('Column(children: [TextField(), TextField()])'), 1);
      expect(
          countTouching('Column(children: [TextField(), '
              'const SizedBox(height: 8), DropdownButtonFormField<int>()])'),
          1);
      expect(
          countTouching('ListView(children: [InkWell(child: InputDecorator()), '
              'Row(children: [Expanded(child: TextField())])])'),
          1);
      expect(countTouching('Column(children: [for (final c in cs) TextField()])'),
          1);
    });

    test('sees through a spread, an if and a helper', () {
      expect(
          countTouching('Column(children: [TextField(), '
              "if (x) ...[const SizedBox(height: 8), Text('\${a ? 'b' : 'c'}'), "
              'TextField(), _f(c)]]) '
              'Widget _f(TextEditingController c) => TextField(controller: c);'),
          1);
    });

    test('leaves a FieldColumn, a Row and fields apart alone', () {
      expect(countTouching('FieldColumn(children: [TextField(), TextField()])'),
          0);
      expect(
          countTouching('Row(children: [Expanded(child: TextField()), '
              'Expanded(child: TextField())])'),
          0);
      expect(
          countTouching('Column(children: [TextField(), Text(hint), '
              'TextField()])'),
          0);
    });
  });
}
