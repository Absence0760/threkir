import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screen-reader double-read guard (#1374 round 3).
///
/// A `Semantics(label:)` over a child that has its own text or its own node
/// is read twice: the label, then the child ("Give kudos, button" and then
/// "3, button"; "Log" and then the "Log" title under it; "Search clubs"
/// around a field whose hint already says "Search clubs"). Every labelled
/// `Semantics` in `lib/` and ui_kit therefore either
///
/// - passes `excludeSemantics: true` (with `onTap` when the excluded child
///   held the tap), or has `ExcludeSemantics(` as its child, or
/// - says why its children must still be read, in a
///   `// semantics-children: <reason>` comment on the lines just above it
///   (a group name over its own controls, a map whose credit keeps its node,
///   a field with no visible label of its own).
void main() {
  test('every labelled Semantics excludes its children or says why not', () {
    final offenders = <String>[];
    var seen = 0;
    for (final root in ['lib', '../../packages/ui_kit/lib']) {
      for (final f
          in Directory(root).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.contains('/gen/')) continue;
        final src = f.readAsStringSync();
        // Comments blanked (same length) so a call quoted in prose is not a
        // call; the reason comments are read from [src] itself.
        final code = src.replaceAllMapped(
            RegExp(r'//[^\n]*'), (m) => ' ' * m.group(0)!.length);
        for (final m in RegExp(r'(?<![\w.])Semantics\(').allMatches(code)) {
          final args = topLevelArgs(code, m.end - 1);
          if (!args.containsKey('label')) continue;
          seen++;
          if (passes(src, m.start, args)) continue;
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${f.path}:$line');
        }
      }
    }
    expect(seen, greaterThan(50),
        reason: 'the scan found only $seen labelled Semantics; it is '
            'probably broken rather than the app having shrunk');
    expect(offenders, isEmpty,
        reason: 'add excludeSemantics: true (and onTap if the child held '
            'the tap), or a `// semantics-children: <why>` comment:\n'
            '${offenders.join('\n')}');
  });

  test('the scanner tells the three shapes apart', () {
    bool check(String src) {
      final i = src.indexOf('Semantics(');
      return passes(src, i, topLevelArgs(src, i + 'Semantics'.length));
    }

    expect(check("Semantics(label: 'a', child: Text('a'))"), isFalse);
    expect(
        check("Semantics(label: 'a', excludeSemantics: true, child: x)"),
        isTrue);
    expect(check("Semantics(label: 'a', child: ExcludeSemantics(child: x))"),
        isTrue);
    expect(
        check("// semantics-children: a group name\nSemantics(\n"
            "  container: true, label: 'a', child: x)"),
        isTrue);
    expect(
        topLevelArgs(
                "Semantics(customSemanticsActions: {CustomSemanticsAction("
                "label: 'x'): f}, child: y)",
                9)
            .containsKey('label'),
        isFalse,
        reason: 'a label inside a nested call is not this widget\'s label');
  });
}

bool passes(String src, int start, Map<String, String> args) {
  if (args['excludeSemantics']?.trim() == 'true') return true;
  if (args['child']?.trimLeft().startsWith('ExcludeSemantics(') ?? false) {
    return true;
  }
  // The contiguous `//` lines directly above the line the call starts on.
  final lines = src.substring(0, start).split('\n');
  lines.removeLast();
  for (var i = lines.length - 1; i >= 0; i--) {
    final l = lines[i].trim();
    if (!l.startsWith('//')) break;
    if (l.startsWith('// semantics-children:')) return true;
  }
  return false;
}

/// The top-level named arguments of the call whose `(` is at [open].
Map<String, String> topLevelArgs(String src, int open) {
  final out = <String, String>{};
  var depth = 0;
  var start = open + 1;
  void take(int end) {
    final arg = src.substring(start, end);
    final m = RegExp(r'^\s*(\w+)\s*:').firstMatch(arg);
    if (m != null) out[m.group(1)!] = arg.substring(m.end);
  }

  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) {
      depth--;
      if (depth == 0) {
        take(i);
        break;
      }
    }
    if (c == ',' && depth == 1) {
      take(i);
      start = i + 1;
    }
  }
  return out;
}
