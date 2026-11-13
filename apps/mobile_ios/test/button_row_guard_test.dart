import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Button-row guard (#1374 TO-7).
///
/// A `Row` holding two or more Material buttons with no flex child cannot
/// wrap: a button never wraps its own label, so at a large text size or in a
/// long locale the row is start-packed and the last button, usually Save, is
/// clipped off the right edge. Such a row is an `OverflowBar` (it lays the
/// buttons out in a line while they fit and stacks them when they do not, as
/// `AlertDialog` does), or gives its buttons an `Expanded` / `Flexible`.
/// `Spacer` does not count: it shrinks to nothing and the buttons still
/// overflow.
void main() {
  test('no Row holds two buttons that cannot wrap', () {
    final offenders = <String>[];
    for (final root in ['lib', '../../packages/ui_kit/lib']) {
      for (final f
          in Directory(root).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.contains('/gen/')) continue;
        final src = f.readAsStringSync();
        for (final m in RegExp(r'(?<![\w.])Row\(').allMatches(src)) {
          final children = _topLevelChildren(_span(src, m.end - 1, '(', ')'));
          if (children == null) continue;
          final buttons = children.where(_button.hasMatch).length;
          final flex = children.any(_flex.hasMatch);
          if (buttons >= 2 && !flex) {
            final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
            offenders.add('${f.path}:$line');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'make these OverflowBar(alignment: end, overflowAlignment: '
            'end, spacing: 8), or give the buttons a flex parent:\n'
            '${offenders.join('\n')}');
  });

  test('the scanner sees a two-button row and passes an OverflowBar', () {
    const bad = '''
Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    TextButton(onPressed: null, child: Text('Cancel')),
    const SizedBox(width: 8),
    FilledButton.icon(onPressed: null, icon: x, label: Text('Save')),
  ],
)''';
    const flexed = '''
Row(children: [
  Expanded(child: OutlinedButton(onPressed: null, child: Text('A'))),
  Expanded(child: FilledButton(onPressed: null, child: Text('B'))),
])''';
    const spaced = '''
Row(children: [
  TextButton(onPressed: null, child: Text('A')),
  const Spacer(),
  FilledButton(onPressed: null, child: Text('B')),
])''';
    int count(String s) {
      final children = _topLevelChildren(_span(s, s.indexOf('('), '(', ')'))!;
      return children.where(_button.hasMatch).length;
    }

    expect(count(bad), 2);
    expect(_topLevelChildren(_span(flexed, 3, '(', ')'))!.any(_flex.hasMatch),
        isTrue);
    expect(_topLevelChildren(_span(spaced, 3, '(', ')'))!.any(_flex.hasMatch),
        isFalse,
        reason: 'a Spacer shrinks to nothing; it is not a flex child');
  });
}

final _button = RegExp(
    r'^(?:const\s+)?(?:TextButton|FilledButton|OutlinedButton|ElevatedButton)'
    r'(?:\.\w+)?\(');
final _flex = RegExp(r'^(?:const\s+)?(?:Expanded|Flexible)\b');

/// The top-level elements of the `children:` list in a `Row(...)` argument
/// span, or null when the row's children are not a list literal.
List<String>? _topLevelChildren(String args) {
  final m = RegExp(r'children:\s*(?:const\s*)?(?:<Widget>)?\[').firstMatch(args);
  if (m == null) return null;
  var depth = 0;
  for (final c in args.substring(0, m.start).split('')) {
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) depth--;
  }
  // The match belongs to a nested widget, not to this row.
  if (depth != 1) return null;
  final list = _span(args, m.end - 1, '[', ']');
  final body = list.substring(1, list.length - 1);
  final out = <String>[];
  final cur = StringBuffer();
  depth = 0;
  for (final c in body.split('')) {
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) depth--;
    if (c == ',' && depth == 0) {
      out.add(cur.toString().trim());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  if (cur.toString().trim().isNotEmpty) out.add(cur.toString().trim());
  return out;
}

String _span(String source, int open, String o, String c) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final ch = source[i];
    if (ch == o) depth++;
    if (ch == c) {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  return source.substring(open);
}
