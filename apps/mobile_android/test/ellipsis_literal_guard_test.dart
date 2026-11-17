// A user-facing Dart string literal writes the one-character ellipsis "…"
// (U+2026), never three full stops (decisions § 2539, widened in § 2556).
// `l10n_parity_test.dart` holds the ARBs to it; this holds the literals in
// `lib/` that never reach a catalogue: `Text('Loading...')`, a hint, a
// placeholder name. Three full stops can wrap between the dots and read as
// three sentences to a screen reader.
//
// The scan reads every string literal's own text (comments, spread `...` and
// cascade `..` are code, not literals, so they never match). It skips:
//   - lib/l10n/gen/: generated from the ARBs, which have their own guard;
//   - a literal anywhere inside a call to one of [nonUserFacingCalls]: log
//     lines a runner never sees, and a RegExp whose `...` means three
//     characters.
// Keep that list short; a literal a runner can read is never excused.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const nonUserFacingCalls = {'debugPrint', 'print', 'log', 'RegExp'};

class DartLiteral {
  DartLiteral(this.offset, this.text, this.excused);
  final int offset;
  final String text;
  final bool excused;
}

/// Every string literal in [source], each with its text outside any
/// interpolation and whether a call in [nonUserFacingCalls] encloses it.
List<DartLiteral> dartStringLiterals(String source) {
  final out = <DartLiteral>[];
  final calls = <String?>[];

  bool excused() => calls.any(nonUserFacingCalls.contains);

  String? identifierBefore(int end) {
    var j = end - 1;
    while (j >= 0 && (source[j] == ' ' || source[j] == '\n')) {
      j--;
    }
    final stop = j + 1;
    while (j >= 0 && RegExp(r'[A-Za-z0-9_$.]').hasMatch(source[j])) {
      j--;
    }
    if (j + 1 == stop) return null;
    final name = source.substring(j + 1, stop);
    return name.split('.').last;
  }

  late int Function(int, bool) code;

  int string(int start) {
    var j = start;
    var raw = false;
    if (source[j] == 'r') {
      raw = true;
      j++;
    }
    final quote = source[j];
    final triple = source.startsWith(quote * 3, j);
    final close = triple ? quote * 3 : quote;
    j += close.length;
    final text = StringBuffer();
    while (j < source.length && !source.startsWith(close, j)) {
      final c = source[j];
      if (!raw && c == r'\') {
        text.write(source.substring(j, j + 2));
        j += 2;
      } else if (!raw && c == r'$' && j + 1 < source.length && source[j + 1] == '{') {
        j = code(j + 2, true);
      } else {
        text.write(c);
        j++;
      }
    }
    out.add(DartLiteral(start, text.toString(), excused()));
    return j + close.length;
  }

  /// Steps over code from [start]; with [toBrace], stops after the `}` that
  /// closes an interpolation and returns the offset past it.
  code = (int start, bool toBrace) {
    var j = start;
    var depth = 0;
    final callDepth = calls.length;
    while (j < source.length) {
      final c = source[j];
      if (source.startsWith('//', j)) {
        while (j < source.length && source[j] != '\n') {
          j++;
        }
      } else if (source.startsWith('/*', j)) {
        final end = source.indexOf('*/', j + 2);
        j = end < 0 ? source.length : end + 2;
      } else if (c == "'" || c == '"') {
        j = string(j);
      } else if (c == 'r' &&
          j + 1 < source.length &&
          (source[j + 1] == "'" || source[j + 1] == '"') &&
          (j == 0 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(source[j - 1]))) {
        j = string(j);
      } else if (c == '(') {
        calls.add(identifierBefore(j));
        j++;
      } else if (c == ')') {
        if (calls.length > callDepth) calls.removeLast();
        j++;
      } else if (c == '{') {
        depth++;
        j++;
      } else if (c == '}') {
        if (toBrace && depth == 0) {
          calls.length = callDepth;
          return j + 1;
        }
        depth--;
        j++;
      } else {
        j++;
      }
    }
    return j;
  };

  code(0, false);
  return out;
}

/// `file:line: text` for every literal in [source] that writes three full stops.
List<String> ellipsisOffenders(String path, String source) => [
      for (final lit in dartStringLiterals(source))
        if (!lit.excused && lit.text.contains('...'))
          '$path:${'\n'.allMatches(source.substring(0, lit.offset)).length + 1}: ${lit.text}',
    ];

void main() {
  test('no user-facing string literal in lib/ writes three full stops', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.replaceAll(r'\', '/').contains('lib/l10n/gen/'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files.length, greaterThan(100), reason: 'the scan found lib/');
    final offenders = [
      for (final f in files) ...ellipsisOffenders(f.path, f.readAsStringSync()),
    ];
    expect(offenders, isEmpty, reason: 'write "…" (U+2026), not "..."');
  });

  group('the scanner', () {
    List<String> scan(String src) => ellipsisOffenders('x.dart', src);

    test('catches the slips it exists for', () {
      expect(scan("Text('Loading...')"), hasLength(1));
      expect(scan('hintText: "Search places..."'), hasLength(1));
      expect(scan("Text('''\nWait...\n''')"), hasLength(1));
      expect(scan(r"Text('Saving ${name}...')"), hasLength(1));
      expect(scan("Text(r'Raw...')"), hasLength(1));
      expect(scan("debugPrint('x'); Text('Loading...')"), hasLength(1));
      expect(scan(r"Text('${f('a')}...')"), hasLength(1));
    });

    test('passes code and the excused calls', () {
      expect(scan("Text('Loading…')"), isEmpty);
      expect(scan("final m = {...s, 'a': 1}; list..add('b');"), isEmpty);
      expect(scan("// Text('Loading...')\n/* 'x...' */"), isEmpty);
      expect(scan("debugPrint('retrying...')"), isEmpty);
      expect(scan(r"debugPrint('retrying ${n}...')"), isEmpty);
      expect(scan("developer.log('flush...', name: 'x')"), isEmpty);
      expect(scan("RegExp(r'a...b')"), isEmpty);
    });

    test('reports the line the literal starts on', () {
      expect(scan("a\nb\nText('x...')"), ['x.dart:3: x...']);
    });
  });
}
