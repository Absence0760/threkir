import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Slider guard (#1374 A11Y-4).
///
/// Material's `Slider` reads its value to TalkBack as a percentage of its
/// range unless it is given a `semanticFormatterCallback`, and `label:` only
/// feeds the visual value bubble. The privacy-zone radius read "33%, slider"
/// at 200 m. Every `Slider(` in `lib/` and `packages/ui_kit/lib` passes a
/// formatter that reads the value in the unit the screen shows.
void main() {
  test('every Slider reads its value through semanticFormatterCallback', () {
    final offenders = <String>[];
    for (final root in ['lib', '../../packages/ui_kit/lib']) {
      for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        for (final m in RegExp(r'(?<![\w.])(?:Slider|RangeSlider)(?:\.adaptive)?\(').allMatches(src)) {
          final span = _argSpan(src, m.end - 1);
          if (!span.contains('semanticFormatterCallback')) {
            final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
            offenders.add('${f.path}:$line');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'a Slider without semanticFormatterCallback is read as a bare percentage:\n'
            '${offenders.join('\n')}');
  });
}

String _argSpan(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  return source.substring(open);
}
