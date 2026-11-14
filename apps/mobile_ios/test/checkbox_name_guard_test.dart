import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Checkbox guard (#1374 A11Y-13).
///
/// A bare `Checkbox` is announced as "checkbox, not checked" with no name;
/// its label beside it is a second stop, often with a second tap action. A
/// checkbox in `lib/` is a `CheckboxListTile` (one node: the title names it
/// and the whole row toggles), or carries its own `semanticLabel`.
void main() {
  test('every bare Checkbox carries a semanticLabel', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(r'(?<![\w.])Checkbox(?:\.adaptive)?\(').allMatches(src)) {
        var depth = 0;
        var end = m.end - 1;
        for (; end < src.length; end++) {
          if (src[end] == '(') depth++;
          if (src[end] == ')' && --depth == 0) break;
        }
        if (!src.substring(m.start, end).contains('semanticLabel')) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${f.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'use CheckboxListTile, or give the Checkbox a semanticLabel:\n'
            '${offenders.join('\n')}');
  });
}
