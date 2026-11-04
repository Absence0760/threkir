// A caught exception never reaches a runner's screen as its own text.
//
// `'$e'`, `e.toString()` and `e.message` are written for whoever reads the
// log: a PostgrestException's SQL detail, a SocketException's host and errno,
// an `Instance of '_ClientException'`, all in English whatever the app's
// locale. Every user-visible error goes through `friendlyError` (or
// `friendlyAuthError` on the sign-in screens, or the screen's own localized
// copy), and the raw value stays in `debugPrint`
// (docs/architecture/conventions.md § Error handling, "mobile error copy").
//
// The scan is structural. It binds the names a caught value can travel under —
// a `catch (e)` / `catch (e, st)` block, an `onError:` / `catchError(` /
// `errorBuilder:` callback parameter, an `Object?` field a screen parks a
// failure in, and any `snapshot.error` — and reports one of them used raw
// inside a sink:
//
//   * a call that puts text in front of the runner: `showTopBanner`,
//     `showSnackBar`, `SnackBar`, `Text`, `SelectableText`, `TextSpan`,
//     `AlertDialog`, or any localized-message call (`l10n.x(...)`,
//     `AppLocalizations.of(context).x(...)`) — a localized frame around a raw
//     exception is still a raw exception;
//   * an assignment to a field or local whose name says it carries copy
//     (`_error`, `_message`, `_status`, `_syncMessage`, …), which is how a
//     catch block hands text to a `build` that renders it;
//   * what a `String` helper taking the error returns, since its caller
//     renders it.
//
// A local initialised from the raw value (`final s = '$e';`) is followed as
// the raw value. An `Object?` field assigned the error is not a hit — it holds
// the error, not copy — but every place that field is rendered is.
// Raw means `$e`, `${e…}`, `e.toString()`, `e.message`, `e.details`, or `e`
// passed bare as an argument. Calls to the classifiers (`friendlyError`,
// `rateLimitErrorMessage`, `isSignedOutError`, …) are blanked first, since
// handing them the raw value is the whole point. A comparison such as
// `e.message.contains(...)` or `e.message == x` is classification, not copy,
// and is not a hit.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _root = 'lib';

/// Sites this guard knowingly lets through, keyed `path|trimmed line` (or a
/// bare `path` for a whole file), each with the reason. Every entry must still
/// match a hit, so a fixed site has to leave this list in the same change.
const _allowlist = <String, String>{
  // Reached from Settings only against a loopback backend (the Developer
  // section, `localBackend` in settings_screen.dart): the operator reading it
  // is the one debugging the watch-sim link, and the raw text is the point.
  'lib/screens/sim_watch_screen.dart': 'dev-only watch simulator',
  // The import failure report's per-row "detail" column: the log-safe
  // `.code` / `.message` of the failure behind a classified, localized
  // reason, shown under a disclosure and in the CSV a migrating runner sends
  // to support. Web renders the same field (import_failures.ts, § 676).
  'lib/import_failures.dart|if (err is String) return err;':
      'import failure detail column',
  'lib/import_failures.dart|if (err is num || err is bool) return err.toString();':
      'import failure detail column',
  'lib/import_failures.dart|return s.startsWith("Instance of \'") ? \'\' : s;':
      'import failure detail column',
};

bool _allowed(_Hit h) =>
    _allowlist.containsKey(h.key) || _allowlist.containsKey(h.path);

/// Functions whose job is to turn a raw error into copy (or to classify it).
/// Their argument lists are blanked before a sink is read.
const _classifiers = {
  'friendlyError',
  'friendlyAuthError',
  'classifyAuthError',
  'isSignedOutError',
  'rateLimitErrorMessage',
  'parseRateLimitError',
  'debugPrint',
};

final _catchClause = RegExp(
  r'\bcatch\s*\(\s*([A-Za-z_]\w*)(?:\s*,\s*\w+)?\s*\)\s*\{',
);
final _callbackParam = RegExp(
  r'(?:\bcatchError\(|\bonError:|\berrorBuilder:)\s*\(\s*'
  r'(?:\w+\s*,\s*)?(?:(?:Object|dynamic)\??\s+)?([A-Za-z_]\w*)'
  r'(?:\s*,\s*(?:StackTrace\??\s+)?\w+)?\s*\)\s*(\{|=>)',
);
// A function that turns an error into a String is a sink of its own: what it
// returns is what the caller renders.
final _stringHelper = RegExp(
  r'\bString\??\s+[A-Za-z_]\w*\s*\(([^()]*)\)\s*(\{|=>)',
);
final _errorParam = RegExp(
  r'\b(?:Object|dynamic)\??\s+(e|err|ex|exception|\w*[eE]rror)\b',
);
final _localDecl = RegExp(
  r'\b(?:final|var|String\??)\s+([A-Za-z_]\w*)\s*=(?!=)',
);
final _returnStmt = RegExp(r'\breturn\b');
final _objectField = RegExp(r'\bObject\?\s+(_\w+)\s*;');
final _snapshotError = RegExp(r'\b\w*[sS]napshot\.error\b');

final _sinkCall = RegExp(
  r'(?<![\w.])(?:showTopBanner|showSnackBar|SnackBar|Text|SelectableText|'
  r'TextSpan|AlertDialog)\s*\('
  r'|\b\w*[lL]10n\.\w+\s*\('
  r'|\bAppLocalizations\.of\(\s*\w+\s*\)\.\w+\s*\(',
);
final _sinkAssign = RegExp(
  r'(?<![\w.])(?:this\.)?(_?\w*(?:[Ee]rror|[Mm]essage|[Ss]tatus|[Nn]otice)'
  r'\w*)\s*=(?![=>])',
);

class _Scope {
  _Scope(this.start, this.end, this.name);
  final int start;
  final int end;
  final String name;
}

class _Hit {
  _Hit(this.path, this.line, this.text);
  final String path;
  final int line;
  final String text;
  String get key => '$path|$text';
  @override
  String toString() => '$path:$line  $text';
}

/// Comments blanked, string literals kept: interpolations are what we read.
String _blankComments(String src) {
  final code = blankNonCode(src);
  final out = src.split('');
  var i = 0;
  while (i < src.length) {
    final isComment = src.startsWith('//', i) || src.startsWith('/*', i);
    if (isComment && code[i] == ' ') {
      final block = src.startsWith('/*', i);
      final end = src.indexOf(block ? '*/' : '\n', i + 2);
      final stop = end < 0 ? src.length : (block ? end + 2 : end);
      for (var j = i; j < stop; j++) {
        if (out[j] != '\n') out[j] = ' ';
      }
      i = stop;
    } else {
      i++;
    }
  }
  return out.join();
}

/// Index just past the bracket that closes the one opened at [open].
int _matchClose(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return code.length;
}

/// End of the expression starting at [from]: the first `;` (or `,` when
/// [stopAtComma]) at depth zero, or the closer of a bracket opened before it.
int _expressionEnd(String code, int from, {bool stopAtComma = true}) {
  var depth = 0;
  for (var i = from; i < code.length; i++) {
    final c = code[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) return i;
      depth--;
    }
    if (depth == 0 && (c == ';' || (stopAtComma && c == ','))) return i;
  }
  return code.length;
}

/// The bracket still open at [at], or -1.
int _innermostOpen(String code, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    final c = code[i];
    if (c == ')' || c == ']' || c == '}') depth++;
    if (c == '(' || c == '[' || c == '{') {
      if (depth == 0) return i;
      depth--;
    }
  }
  return -1;
}

/// Interpolated into a string: raw wherever it sits in a sink.
List<RegExp> _interpolated(String name) {
  final n = RegExp.escape(name);
  return [
    RegExp('\\\$$n(?![A-Za-z0-9_])'),
    RegExp('\\\$\\{\\s*$n(?![A-Za-z0-9_])'),
  ];
}

/// Used as a value: raw only when the sink itself takes it — an argument of
/// the sink call, or the top level of an assigned or returned expression. An
/// argument to some other call (`rateLimitErrorMessage(message: e.message)`)
/// is that call's business, and a comparison is classification.
RegExp _valueUse(String name) {
  final n = RegExp.escape(name);
  return RegExp(
    '(?<![A-Za-z0-9_\$.])$n'
    '(?:\\??\\.(?:toString\\(\\)|message|details)(?![A-Za-z0-9_]))?'
    '(?!\\s*(?:\\.[A-Za-z]|\\?\\.|==|!=|\\(|\\[|[A-Za-z0-9_]|\\bis\\b))',
  );
}

void _blankRange(List<String> chars, int from, int to) {
  for (var i = from; i < to && i < chars.length; i++) {
    if (chars[i] != '\n') chars[i] = ' ';
  }
}

List<_Hit> _scan(String path, String src) {
  final code = blankNonCode(src);
  final text = _blankComments(src);
  final lines = src.split('\n');
  final scopes = <_Scope>[];
  final spans = <(int, int)>[];

  for (final m in _catchClause.allMatches(code)) {
    final name = m.group(1)!;
    if (name == '_') continue;
    final open = m.end - 1;
    scopes.add(_Scope(open, _matchClose(code, open), name));
  }
  for (final m in _callbackParam.allMatches(code)) {
    final name = m.group(1)!;
    if (name == '_') continue;
    final end = m.group(2) == '{'
        ? _matchClose(code, m.end - 1)
        : _expressionEnd(code, m.end);
    scopes.add(_Scope(m.start, end, name));
  }
  for (final m in _stringHelper.allMatches(code)) {
    final params = [
      for (final p in _errorParam.allMatches(m.group(1)!)) p.group(1)!,
    ];
    if (params.isEmpty) continue;
    final arrow = m.group(2) == '=>';
    final end = arrow
        ? _expressionEnd(code, m.end, stopAtComma: false)
        : _matchClose(code, m.end - 1);
    for (final p in params) {
      scopes.add(_Scope(m.start, end, p));
    }
    if (arrow) {
      spans.add((m.end, end));
    } else {
      for (final r in _returnStmt.allMatches(code.substring(m.end, end))) {
        final from = m.end + r.end;
        spans.add((from, _expressionEnd(code, from, stopAtComma: false)));
      }
    }
  }
  final fileWide = {
    for (final m in _objectField.allMatches(code)) m.group(1)!,
    for (final m in _snapshotError.allMatches(code)) m.group(0)!,
  };

  final sinkOpens = <int>{};
  for (final m in _sinkCall.allMatches(code)) {
    sinkOpens.add(m.end - 1);
    spans.add((m.start, _matchClose(code, m.end - 1)));
  }
  for (final m in _sinkAssign.allMatches(code)) {
    // A named argument or a parameter default is not an assignment target,
    // and an `Object?` field or an untyped local holds the error itself —
    // the sink is wherever that is rendered, which this scan follows.
    final before = code.substring(0, m.start).trimRight();
    if (before.endsWith('(') || before.endsWith(',')) continue;
    if (RegExp(r'\b(?:final|var|Object\??)$').hasMatch(before)) continue;
    if (fileWide.contains(m.group(1))) continue;
    spans.add((m.end, _expressionEnd(code, m.end)));
  }

  /// Offsets in [start, end) where [name] is used raw.
  Iterable<int> rawUses(int start, int end, String name) sync* {
    final chars = text.substring(start, end).split('');
    final local = text.substring(start, end);
    for (final fn in _classifiers) {
      for (final c in RegExp('(?<![\\w.])$fn\\s*\\(').allMatches(local)) {
        final close = _matchClose(text, start + c.end - 1) - start;
        _blankRange(chars, c.start, close);
      }
    }
    final body = chars.join();
    for (final re in _interpolated(name)) {
      for (final u in re.allMatches(body)) {
        yield start + u.start;
      }
    }
    for (final u in _valueUse(name).allMatches(body)) {
      final at = start + u.start;
      // Inside a string literal the interpolation patterns already decided.
      if (code[at] == ' ' && src[at] != ' ') continue;
      final open = _innermostOpen(code, at);
      if (sinkOpens.contains(open) || open < start) yield at;
    }
  }

  // A local that holds the raw text is the raw text.
  for (var i = 0; i < scopes.length; i++) {
    final s = scopes[i];
    for (final d in _localDecl.allMatches(code.substring(s.start, s.end))) {
      final from = s.start + d.end;
      if (rawUses(from, _expressionEnd(code, from), s.name).isNotEmpty) {
        scopes.add(_Scope(from, s.end, d.group(1)!));
      }
    }
  }

  final hits = <int, _Hit>{};
  for (final (start, end) in spans) {
    final names = {
      ...fileWide,
      for (final s in scopes)
        if (s.start <= start && end <= s.end) s.name,
    };
    for (final name in names) {
      for (final at in rawUses(start, end, name)) {
        final line = '\n'.allMatches(src.substring(0, at)).length + 1;
        hits[line] = _Hit(path, line, lines[line - 1].trim());
      }
    }
  }
  return hits.values.toList()..sort((a, b) => a.line.compareTo(b.line));
}

void main() {
  test('the scanned root exists', () {
    expect(rootExists(_root), isTrue, reason: '$_root moved; the guard is blind');
  });

  final hits = <_Hit>[
    for (final f in dartFiles(_root))
      if (!f.path.contains('/l10n/'))
        ..._scan(f.path.replaceAll(r'\', '/'), f.readAsStringSync()),
  ];

  test('no raw caught error reaches user-visible copy', () {
    final offenders = [
      for (final h in hits)
        if (!_allowed(h)) h.toString(),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Route the caught value through friendlyError(l10n, e) (or the '
          "screen's localized copy) and keep the raw text in debugPrint — "
          'docs/architecture/conventions.md § Error handling:\n'
          '${offenders.join('\n')}',
    );
  });

  test('every allowlist entry still matches a site', () {
    final keys = {for (final h in hits) ...[h.key, h.path]};
    final stale = [
      for (final k in _allowlist.keys)
        if (!keys.contains(k)) k,
    ];
    expect(stale, isEmpty, reason: 'Drop the stale entries:\n${stale.join('\n')}');
  });

  // A restore warning is data the import screen renders through
  // `restoreWarningText`, so a caught failure can only reach it as `error`,
  // which that renderer classifies. A `String` field — or a `List<String>`
  // of warnings — would be a sink this scan cannot see: the text is built in
  // backup.dart, nowhere near the `Text` that shows it.
  group('restore warnings stay structured', () {
    Map<String, String> fieldsOf(String path, String cls) {
      final src = blankNonCode(File(path).readAsStringSync());
      final start = RegExp('\\bclass\\s+$cls\\b[^{]*\\{').firstMatch(src);
      expect(start, isNotNull, reason: '$cls moved out of $path');
      final body = src.substring(start!.end - 1, _matchClose(src, start.end - 1));
      return {
        for (final m in RegExp(r'^\s*final\s+([\w<>?, ]+?)\s+(\w+)\s*[;=]',
                multiLine: true)
            .allMatches(body))
          m.group(2)!: m.group(1)!.replaceAll(' ', ''),
      };
    }

    test('RestoreResult.warnings is a list of RestoreWarning', () {
      expect(fieldsOf('lib/backup.dart', 'RestoreResult')['warnings'],
          'List<RestoreWarning>');
    });

    test('RestoreWarning carries no free text', () {
      expect(fieldsOf('lib/restore_warning.dart', 'RestoreWarning'), {
        'kind': 'RestoreWarningKind',
        'itemId': 'String?',
        'index': 'int?',
        'columns': 'List<String>',
        'error': 'Object?',
      });
    });
  });

  group('the scanner', () {
    List<String> scan(String src) =>
        [for (final h in _scan('x.dart', src)) h.text];

    test('flags each raw shape inside a catch', () {
      expect(scan(r'''
void f() {
  try {} catch (e) {
    showTopBanner(context, 'Failed: $e');
    showTopBanner(context, l10n.saveFailed(e));
    setState(() => _error = e.toString());
    _message = '${e.message}';
  }
}
'''), [
        r"showTopBanner(context, 'Failed: $e');",
        'showTopBanner(context, l10n.saveFailed(e));',
        'setState(() => _error = e.toString());',
        r"_message = '${e.message}';",
      ]);
    });

    test('lets the classified and logged shapes through', () {
      expect(scan(r'''
void f() {
  try {} catch (e) {
    debugPrint('save failed: $e');
    showTopBanner(context, l10n.saveFailed(friendlyError(l10n, e)));
    setState(() => _error = isSignedOutError(e) ? l10n.signIn : friendlyError(l10n, e));
    if (e.message.contains('NoRoute')) _status = l10n.noRoute;
    final s = e.toString();
  }
  Text('$e');
}
'''), isEmpty);
    });

    test('reads a String helper of an error, through a local alias', () {
      expect(scan(r'''
String _clean(Object e) {
  final s = '$e';
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}
String label(Object error) =>
    error is StateError ? l10n.stateFailed : friendlyError(l10n, error);
String _str(Object? v) => v is String ? v : '';
'''), [
        "return s.startsWith('Exception: ') ? s.substring(11) : s;",
      ]);
    });

    test('follows callbacks, Object? fields and snapshot.error', () {
      expect(scan(r'''
class S {
  Object? _loadError;
  void f() {
    x.catchError((Object e) { showTopBanner(context, '$e'); });
    y.listen(null, onError: (Object err) => setState(() => _status = '$err'));
  }
  Widget build() => Column(children: [
    Text('${_loadError}'),
    Text(snapshot.error.toString()),
  ]);
}
'''), [
        r"x.catchError((Object e) { showTopBanner(context, '$e'); });",
        r"y.listen(null, onError: (Object err) => setState(() => _status = '$err'));",
        r"Text('${_loadError}'),",
        'Text(snapshot.error.toString()),',
      ]);
    });
  });
}
