// Source-scan guard for issue #1300 § 4. A page's own Scaffold cannot see the
// shell's docked centre button, so a page FAB at the default `endFloat` sat
// over it on the phone. `pageFabLocation` lifts it by `DockedFabInset`, and is
// plain `endFloat` on pushed routes and the rail, so every Scaffold that sets
// a `floatingActionButton` sets it too. The shell itself is the one owner of
// a docked location.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dockedOwners = {
  'lib/screens/home_screen.dart':
      'the shell docks the centre Log button that every page clears',
};

/// [source] with comments removed and every string literal emptied, so a
/// bracket or an argument name inside either can neither end a scan early
/// nor satisfy it. Newlines are kept, so reported lines still match.
String _codeOnly(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end;
    } else if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      final next = end < 0 ? source.length : end + 2;
      out.write('\n' * '\n'.allMatches(source.substring(i, next)).length);
      i = next;
    } else if (source[i] == "'" || source[i] == '"') {
      final triple = source.startsWith(source[i] * 3, i);
      final quote = triple ? source[i] * 3 : source[i];
      final raw = i > 0 && source[i - 1] == 'r';
      var j = i + quote.length;
      while (j < source.length && !source.startsWith(quote, j)) {
        if (!raw && source[j] == r'\') j++;
        j++;
      }
      final next = j + quote.length;
      out.write("''");
      out.write(
        '\n' *
            '\n'
                .allMatches(source.substring(i, next.clamp(0, source.length)))
                .length,
      );
      i = next;
    } else {
      out.write(source[i]);
      i++;
    }
  }
  return out.toString();
}

/// The text of a call's argument list with every nested bracket's contents
/// removed, so only the call's own named arguments remain.
String _topLevelArgs(String source, int open) {
  final out = StringBuffer();
  var depth = 0;
  for (var i = open + 1; i < source.length; i++) {
    final c = source[i];
    if (c == '(' || c == '[' || c == '{') {
      if (depth == 0) out.write(c);
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) break;
      depth--;
    } else if (depth == 0) {
      out.write(c);
    }
  }
  return out.toString();
}

void main() {
  test('every Scaffold with a FAB places it with pageFabLocation', () {
    // Reason: a page FAB at the default endFloat sat over the shell's docked
    // centre button (issue #1300 § 4); pageFabLocation is endFloat wherever
    // nothing is docked, so no Scaffold has a reason to skip it.
    final offenders = <String>[];
    var scaffoldsWithFab = 0;
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      final source = _codeOnly(entity.readAsStringSync());
      for (final m in RegExp(r'\bScaffold\(').allMatches(source)) {
        final args = _topLevelArgs(source, m.end - 1);
        if (!RegExp(r'\bfloatingActionButton\s*:').hasMatch(args)) continue;
        scaffoldsWithFab++;
        if (args.contains('floatingActionButtonLocation: pageFabLocation(')) {
          continue;
        }
        if (_dockedOwners.containsKey(path) &&
            args.contains(
              'floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked',
            )) {
          continue;
        }
        final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
        offenders.add('$path:$line');
      }
    }
    expect(
      scaffoldsWithFab,
      greaterThan(10),
      reason: 'the scan found the Scaffolds it is meant to check',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'add `floatingActionButtonLocation: pageFabLocation(context)` '
          'so the button clears the shell\'s docked centre button',
    );
  });

  test('every docked-owner exemption is still used', () {
    for (final path in _dockedOwners.keys) {
      expect(
        File(path).readAsStringSync(),
        contains('FloatingActionButtonLocation.centerDocked'),
        reason: '$path no longer docks a button; drop its exemption',
      );
    }
  });
}
