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
// The scan is structural and covers `lib/` plus every `packages/*/lib`. It
// binds the names a caught value can travel under — a `catch (e)` /
// `catch (e, st)` block, an `onError:` / `catchError(` / `errorBuilder:`
// callback parameter, any function or closure taking an `Object e` /
// `dynamic err` / `Object? …Error` parameter, an `Object?` field a screen
// parks a failure in (or any `Object?` / `dynamic` slot named for an error),
// and the `.error` of an `AsyncSnapshot` (a `snapshot` / `snap` / `s` /
// `async`, a parameter typed `AsyncSnapshot`, or a builder's second
// parameter) — and reports one of them used raw inside a sink:
//
//   * a call that puts text in front of the runner: `showTopBanner`,
//     `showSnackBar`, `SnackBar`, `Text`, `Text.rich`, `SelectableText`,
//     `TextSpan`, `AlertDialog`, `Tooltip`, `Semantics`, or any
//     localized-message call (`l10n.x(...)`, `AppLocalizations.of(context)
//     .x(...)`) — a localized frame around a raw exception is still a raw
//     exception;
//   * an `errorText:` argument, or a `.value =` on a notifier a widget
//     listens to;
//   * an assignment (`=` or `+=`) to a field or local whose name says it
//     carries copy (`_error`, `_message`, `_status`, `_notice`, `_hint`,
//     `_text`, `_label`, `_reason`, …), which is how a catch block hands text
//     to a `build` that renders it;
//   * what a `String` helper taking the error returns, since its caller
//     renders it.
//
// A local initialised from the raw value (`final s = '$e';`) is followed as
// the raw value. An `Object?` field assigned the error is not a hit — it holds
// the error, not copy — but every place that field is rendered is. A closure
// or a `for` that rebinds the name (`.map((e) => Text('$e'))`) shadows it.
//
// Raw means `$e`, `${e}`, or `e.toString()` / `e.message` / `e.details`
// whatever follows (`e.toString().trim()` is still the exception's text), or
// `e` passed bare as an argument. A chain that ends in a classification —
// `.contains(...)`, `.startsWith(...)`, `.isEmpty`, `==`, `is` — is not copy,
// and neither is another member (`${e.code}`, `${e.statusCode}`). Calls to the
// classifiers (`friendlyError`, `rateLimitErrorMessage`, `isSignedOutError`,
// …) are blanked first, since handing them the raw value is the whole point.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _root = 'lib';
const _packages = '../../packages';

/// The scanned roots: the app's `lib/` and every shared package's `lib/`.
List<String> _roots() => [
  _root,
  if (Directory(_packages).existsSync())
    for (final d
        in Directory(_packages).listSync().whereType<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
      if (Directory('${d.path}/lib').existsSync()) '${d.path}/lib',
];

/// Sites this guard knowingly lets through, keyed `path|trimmed line`, with
/// ` #2`, ` #3`, … appended for the second and later identical lines of one
/// file, so a copy of an allowed line is a new hit rather than a free pass.
/// Every entry must still match a hit, so a fixed site has to leave this list
/// in the same change.
const _allowlist = <String, String>{
  // Reached from Settings only against a loopback backend (the Developer
  // section, `localBackend` in settings_screen.dart): the operator reading it
  // is the one debugging the watch-sim link, and the raw text is the point.
  r"lib/screens/sim_watch_screen.dart|_error = '$e';":
      'dev-only watch simulator',
  r"lib/screens/sim_watch_screen.dart|setState(() => _syncMessage = l10n.simWatchSyncFailed('$e'));":
      'dev-only watch simulator',
  r"lib/screens/sim_watch_screen.dart|setState(() => _syncMessage = l10n.simWatchPushSettingsFailed('$e'));":
      'dev-only watch simulator',
  r"lib/screens/sim_watch_screen.dart|setState(() => _syncMessage = l10n.simWatchPushCourseFailed('$e'));":
      'dev-only watch simulator',
  r"lib/screens/sim_watch_screen.dart|setState(() => _syncMessage = l10n.simWatchPushRoadbookFailed('$e'));":
      'dev-only watch simulator',
  r"lib/screens/sim_watch_screen.dart|setState(() => _syncMessage = l10n.simWatchPushWorkoutFailed('$e'));":
      'dev-only watch simulator',
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

/// Members that read a raw value without rendering it.
const _classifying = {
  'contains',
  'startsWith',
  'endsWith',
  'isEmpty',
  'isNotEmpty',
  'length',
  'hashCode',
  'indexOf',
  'lastIndexOf',
  'compareTo',
  'codeUnitAt',
};

final _catchClause = RegExp(
  r'\bcatch\s*\(\s*([A-Za-z_]\w*)(?:\s*,\s*\w+)?\s*\)\s*\{',
);
final _callbackParam = RegExp(
  r'(?:\bcatchError\(|\bonError:|\berrorBuilder:)\s*\(\s*'
  r'(?:\w+\s*,\s*)?(?:(?:Object|dynamic)\??\s+)?([A-Za-z_]\w*)'
  r'(?:\s*,\s*(?:StackTrace\??\s+)?\w+)?\s*\)\s*(\{|=>)',
);
// Any parameter list followed by a body: a function, a method or a closure.
final _paramList = RegExp(r'\(([^()]*)\)\s*(?:async\*?\s*|sync\*\s*)?(\{|=>)');
final _controlFlow = RegExp(r'\b(?:if|while|for|switch|catch)\s*$');
// What a function returns is the caller's copy when it is a String.
final _returnsString = RegExp(r'\bString\??\s+[A-Za-z_]\w*\s*$');
final _errorParam = RegExp(
  r'\b(?:Object|dynamic)\??\s+(e|err|ex|exception|\w*[eE]rror)\b',
);
final _forIn = RegExp(
  r'\bfor\s*\(\s*(?:final|var|[\w<>?]+)\s+(?:[\w<>?]+\s+)?([A-Za-z_]\w*)\s+in\b',
);
final _localDecl = RegExp(
  r'\b(?:final|var|String\??)\s+([A-Za-z_]\w*)\s*=(?!=)',
);
final _returnStmt = RegExp(r'\breturn\b');
final _errorish = RegExp(r'(?:[eE]rr(?:or)?|[eE]xception|[fF]ailure)');
final _objectField = RegExp(
  r'\b(Object\?|dynamic)\s+([A-Za-z_]\w*)\s*(?:=\s*null\s*)?;',
);
final _snapshotDecl = RegExp(r'\bAsyncSnapshot(?:<[^()]*?>)?\s+([A-Za-z_]\w*)');
final _builderSnapshot = RegExp(
  r'\bbuilder:\s*\(\s*\w+\s*,\s*([A-Za-z_]\w*)\s*[,)]',
);
final _snapshotName = RegExp(r'^(?:\w*[sS]napshot|snap|s|async)$');
final _dotError = RegExp(r'(?<![\w.$])([A-Za-z_]\w*)\s*\.\s*error\b');
final _member = RegExp(r'\s*!?\s*\??\.\s*([A-Za-z_]\w*)');

final _sinkCall = RegExp(
  r'(?<![\w.])(?:showTopBanner|showSnackBar|SnackBar|Text|Text\.rich|'
  r'SelectableText|TextSpan|AlertDialog|Tooltip|Semantics)\s*\('
  r'|\b\w*[lL]10n\.\w+\s*\('
  r'|\bAppLocalizations\.of\(\s*\w+\s*\)\.\w+\s*\(',
);
final _sinkArg = RegExp(r'\berrorText:');
final _sinkAssign = RegExp(
  r'(?<![\w.])(?:this\.)?(_?\w*(?:[Ee]rror|[Mm]essage|[Ss]tatus|[Nn]otice|'
  r'[Hh]int|[Tt]ext|[Ll]abel|[Rr]eason)\w*)\s*\+?=(?![=>])',
);
final _valueAssign = RegExp(r'\.value\s*=(?![=>])');

class _Scope {
  _Scope(this.start, this.end, this.name, [int? bodyStart])
    : bodyStart = bodyStart ?? start;
  final int start;
  final int end;
  final String name;

  /// Where the body begins: a rebinding of [name] before it is this scope's
  /// own binder, not a shadow.
  final int bodyStart;
}

class _Hit {
  _Hit(this.path, this.line, this.text, [this.occurrence = 1]);
  final String path;
  final int line;
  final String text;
  final int occurrence;
  String get key => '$path|$text${occurrence > 1 ? ' #$occurrence' : ''}';
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

int _skipSpace(String s, int i) {
  while (i < s.length && (s[i] == ' ' || s[i] == '\n' || s[i] == '\t')) {
    i++;
  }
  return i;
}

/// Whether what follows a member chain starting at [i] classifies the value
/// rather than rendering it: a classifying member anywhere in the chain, or a
/// comparison after it.
bool _classifiedChain(String s, int i) {
  while (true) {
    final m = _member.matchAsPrefix(s, i);
    if (m == null) break;
    if (_classifying.contains(m.group(1))) return true;
    i = _skipSpace(s, m.end);
    while (i < s.length && (s[i] == '(' || s[i] == '[')) {
      i = _skipSpace(s, _matchClose(s, i));
    }
  }
  i = _skipSpace(s, i);
  return s.startsWith('==', i) ||
      s.startsWith('!=', i) ||
      RegExp(r'is\b').matchAsPrefix(s, i) != null;
}

/// Whether the name ending at [i] in [s] is used as its raw text: bare, or
/// through `.toString()` / `.message` / `.details` and anything but a
/// classification after that.
bool _rawAfter(String s, int i) {
  final m = _member.matchAsPrefix(s, i);
  if (m == null) {
    final j = _skipSpace(
      s,
      s.startsWith('!', i) && !s.startsWith('!=', i) ? i + 1 : i,
    );
    if (j < s.length && (s[j] == '(' || s[j] == '[')) return false;
    return !_classifiedChain(s, j);
  }
  var j = m.end;
  switch (m.group(1)) {
    case 'toString':
      j = _skipSpace(s, j);
      if (j >= s.length || s[j] != '(') return false;
      j = _matchClose(s, j);
    case 'message':
    case 'details':
      break;
    default:
      return false;
  }
  return !_classifiedChain(s, j);
}

/// Every `(start, end)` in [code] where a closure, a nested function or a
/// `for` rebinds [name].
List<(int, int)> _rebindings(String code, String name) {
  final out = <(int, int)>[];
  for (final m in _paramList.allMatches(code)) {
    if (_controlFlow.hasMatch(code.substring(0, m.start))) continue;
    final params = m
        .group(1)!
        .replaceAll(RegExp(r'[{}\[\]]'), ' ')
        .split(',')
        .map((p) => p.split('=').first.trim())
        .map((p) => p.isEmpty ? '' : p.split(RegExp(r'[\s.]+')).last);
    if (!params.contains(name)) continue;
    final end = m.group(2) == '{'
        ? _matchClose(code, m.end - 1)
        : _expressionEnd(code, m.end, stopAtComma: false);
    out.add((m.start, end));
  }
  for (final m in _forIn.allMatches(code)) {
    if (m.group(1) != name) continue;
    final open = code.indexOf('(', m.start);
    final close = _matchClose(code, open);
    final body = _skipSpace(code, close);
    final end = body < code.length && code[body] == '{'
        ? _matchClose(code, body)
        : _expressionEnd(code, body);
    out.add((m.start, end));
  }
  return out;
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
    scopes.add(_Scope(m.start, end, name, m.end));
  }
  for (final m in _paramList.allMatches(code)) {
    final before = code.substring(0, m.start);
    if (_controlFlow.hasMatch(before)) continue;
    final params = [
      for (final p in _errorParam.allMatches(m.group(1)!)) p.group(1)!,
    ];
    if (params.isEmpty) continue;
    final arrow = m.group(2) == '=>';
    final end = arrow
        ? _expressionEnd(code, m.end, stopAtComma: false)
        : _matchClose(code, m.end - 1);
    for (final p in params) {
      scopes.add(_Scope(m.start, end, p, m.end));
    }
    if (!_returnsString.hasMatch(before)) continue;
    if (arrow) {
      spans.add((m.end, end));
    } else {
      for (final r in _returnStmt.allMatches(code.substring(m.end, end))) {
        final from = m.end + r.end;
        spans.add((from, _expressionEnd(code, from, stopAtComma: false)));
      }
    }
  }
  final snapshots = {
    for (final m in _snapshotDecl.allMatches(code)) m.group(1)!,
    for (final m in _builderSnapshot.allMatches(code)) m.group(1)!,
  };
  final fileWide = {
    for (final m in _objectField.allMatches(code))
      if ((m.group(1) == 'Object?' && m.group(2)!.startsWith('_')) ||
          _errorish.hasMatch(m.group(2)!))
        m.group(2)!,
    for (final m in _dotError.allMatches(text))
      if (_snapshotName.hasMatch(m.group(1)!) || snapshots.contains(m.group(1)))
        '${m.group(1)}.error',
  };

  final sinkOpens = <int>{};
  for (final m in _sinkCall.allMatches(code)) {
    sinkOpens.add(m.end - 1);
    spans.add((m.start, _matchClose(code, m.end - 1)));
  }
  for (final m in _sinkArg.allMatches(code)) {
    spans.add((m.end, _expressionEnd(code, m.end)));
  }
  for (final m in _valueAssign.allMatches(code)) {
    spans.add((m.end, _expressionEnd(code, m.end)));
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

  final rebound = <String, List<(int, int)>>{};
  bool shadowed(String name, int at, int bodyStart) => rebound
      .putIfAbsent(name, () => _rebindings(code, name))
      .any((r) => r.$1 >= bodyStart && r.$1 <= at && at < r.$2);

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
    final n = RegExp.escape(name);
    // `$e` interpolates the whole value; `${e…}` is read like code.
    for (final u in RegExp('\\\$$n(?![A-Za-z0-9_])').allMatches(body)) {
      if (!name.contains('.')) yield start + u.start;
    }
    for (final u in RegExp('\\\$\\{\\s*$n(?![A-Za-z0-9_])').allMatches(body)) {
      final after = _skipSpace(body, u.end);
      if (after < body.length && body[after] == '}' || _rawAfter(body, u.end)) {
        yield start + u.start;
      }
    }
    for (final u in RegExp(
      '(?<![A-Za-z0-9_\$.])$n(?![A-Za-z0-9_])',
    ).allMatches(body)) {
      final at = start + u.start;
      // Inside a string literal the interpolation patterns already decided.
      if (code[at] == ' ' && src[at] != ' ') continue;
      if (!_rawAfter(code, start + u.end)) continue;
      final open = _innermostOpen(code, at);
      if (sinkOpens.contains(open) || open < start) yield at;
    }
  }

  // A local that holds the raw text is the raw text.
  for (var i = 0; i < scopes.length; i++) {
    final s = scopes[i];
    for (final d in _localDecl.allMatches(code.substring(s.start, s.end))) {
      final from = s.start + d.end;
      final uses = rawUses(
        from,
        _expressionEnd(code, from),
        s.name,
      ).where((at) => !shadowed(s.name, at, s.bodyStart));
      if (uses.isNotEmpty) {
        scopes.add(_Scope(from, s.end, d.group(1)!));
      }
    }
  }

  final hits = <int, _Hit>{};
  for (final (start, end) in spans) {
    final names = <String, List<int>>{
      for (final n in fileWide) n: [0],
    };
    for (final s in scopes) {
      if (s.start <= start && end <= s.end) {
        (names[s.name] ??= []).add(s.bodyStart);
      }
    }
    for (final MapEntry(key: name, value: bodies) in names.entries) {
      for (final at in rawUses(start, end, name)) {
        if (bodies.every((b) => shadowed(name, at, b))) continue;
        final line = '\n'.allMatches(src.substring(0, at)).length + 1;
        hits[line] = _Hit(path, line, lines[line - 1].trim());
      }
    }
  }
  final sorted = hits.values.toList()..sort((a, b) => a.line.compareTo(b.line));
  final seen = <String, int>{};
  return [
    for (final h in sorted)
      _Hit(
        h.path,
        h.line,
        h.text,
        seen.update(h.text, (n) => n + 1, ifAbsent: () => 1),
      ),
  ];
}

void main() {
  test('the scanned roots exist', () {
    expect(
      rootExists(_root),
      isTrue,
      reason: '$_root moved; the guard is blind',
    );
    expect(
      _roots().length,
      greaterThan(1),
      reason: '$_packages moved; the shared packages are unscanned',
    );
  });

  final hits = <_Hit>[
    for (final root in _roots())
      for (final f in dartFiles(root))
        if (!f.path.contains('/l10n/'))
          ..._scan(
            f.path.replaceAll(r'\', '/').replaceFirst('../../', ''),
            f.readAsStringSync(),
          ),
  ];

  test('no raw caught error reaches user-visible copy', () {
    final offenders = [
      for (final h in hits)
        if (!_allowlist.containsKey(h.key)) h.toString(),
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
    final keys = {for (final h in hits) h.key};
    final stale = [
      for (final k in _allowlist.keys)
        if (!keys.contains(k)) k,
    ];
    expect(
      stale,
      isEmpty,
      reason: 'Drop the stale entries:\n${stale.join('\n')}',
    );
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
      final body = src.substring(
        start!.end - 1,
        _matchClose(src, start.end - 1),
      );
      return {
        for (final m in RegExp(
          r'^\s*final\s+([\w<>?, ]+?)\s+(\w+)\s*[;=]',
          multiLine: true,
        ).allMatches(body))
          m.group(2)!: m.group(1)!.replaceAll(' ', ''),
      };
    }

    test('RestoreResult.warnings is a list of RestoreWarning', () {
      expect(
        fieldsOf('lib/backup.dart', 'RestoreResult')['warnings'],
        'List<RestoreWarning>',
      );
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
    List<String> scan(String src) => [
      for (final h in _scan('x.dart', src)) h.text,
    ];

    test('flags each raw shape inside a catch', () {
      expect(
        scan(r'''
void f() {
  try {} catch (e) {
    showTopBanner(context, 'Failed: $e');
    showTopBanner(context, l10n.saveFailed(e));
    setState(() => _error = e.toString());
    _message = '${e.message}';
  }
}
'''),
        [
          r"showTopBanner(context, 'Failed: $e');",
          'showTopBanner(context, l10n.saveFailed(e));',
          'setState(() => _error = e.toString());',
          r"_message = '${e.message}';",
        ],
      );
    });

    test('lets the classified and logged shapes through', () {
      expect(
        scan(r'''
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
'''),
        isEmpty,
      );
    });

    test('reads a String helper of an error, through a local alias', () {
      expect(
        scan(r'''
String _clean(Object e) {
  final s = '$e';
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}
String label(Object error) =>
    error is StateError ? l10n.stateFailed : friendlyError(l10n, error);
String _str(Object? v) => v is String ? v : '';
'''),
        ["return s.startsWith('Exception: ') ? s.substring(11) : s;"],
      );
    });

    test('follows callbacks, Object? fields and snapshot.error', () {
      expect(
        scan(r'''
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
'''),
        [
          r"x.catchError((Object e) { showTopBanner(context, '$e'); });",
          r"y.listen(null, onError: (Object err) => setState(() => _status = '$err'));",
          r"Text('${_loadError}'),",
          'Text(snapshot.error.toString()),',
        ],
      );
    });
    test('flags a raw value with a method chained onto it', () {
      expect(
        scan(r'''
void f() {
  try {} catch (e) {
    showTopBanner(context, e.toString().replaceFirst('Exception: ', ''));
    setState(() => _error = e.toString().trim());
    _message = e.message.trim();
    Text('${e.message.trim()}');
    if (e.toString().toLowerCase().contains('x')) _status = l10n.x;
    _status = e.message.isEmpty ? l10n.a : l10n.b;
    _error = e.message == 'x' ? l10n.a : l10n.b;
  }
}
'''),
        [
          "showTopBanner(context, e.toString().replaceFirst('Exception: ', ''));",
          'setState(() => _error = e.toString().trim());',
          '_message = e.message.trim();',
          r"Text('${e.message.trim()}');",
        ],
      );
    });

    test('follows void helpers, any AsyncSnapshot, wider fields and sinks', () {
      expect(
        scan(r'''
void _show(Object e) {
  showTopBanner(context, '$e');
}
void _report(dynamic err) => Text(err.toString());
class S {
  Object? _a = null;
  Object? lastError;
  dynamic _failure;
  void f(AsyncSnapshot<int> result) {
    try {} catch (e) {
      _hint = '$e';
      _label += e.toString();
      _reason = e.message;
      _text = '$e';
      notifier.value = e.toString();
    }
    Text(result.error.toString());
  }
  Widget build() => FutureBuilder(future: f, builder: (context, snap) {
    return Column(children: [
      Text('${snap.error}'),
      Text(s.error.toString()),
      Text('${async.error}'),
      Text.rich(span, semanticsLabel: '$_a'),
      Tooltip(message: '$lastError', child: x),
      Semantics(label: '$_failure', child: x),
      TextField(decoration: InputDecoration(errorText: '$_a')),
    ]);
  });
}
'''),
        [
          r"showTopBanner(context, '$e');",
          'void _report(dynamic err) => Text(err.toString());',
          r"_hint = '$e';",
          '_label += e.toString();',
          '_reason = e.message;',
          r"_text = '$e';",
          'notifier.value = e.toString();',
          'Text(result.error.toString());',
          r"Text('${snap.error}'),",
          'Text(s.error.toString()),',
          r"Text('${async.error}'),",
          r"Text.rich(span, semanticsLabel: '$_a'),",
          r"Tooltip(message: '$lastError', child: x),",
          r"Semantics(label: '$_failure', child: x),",
          r"TextField(decoration: InputDecoration(errorText: '$_a')),",
        ],
      );
    });

    test('leaves a code, a status and a shadowing parameter alone', () {
      expect(
        scan(r'''
void f() {
  try {} catch (e) {
    showTopBanner(context, l10n.httpFailed('${e.statusCode}'));
    _message = 'code ${e.code}';
    final rows = items.map((e) => Text('$e')).toList();
    final more = [for (final e in items) Text('$e')];
    showTopBanner(context, '$e');
  }
}
'''),
        [r"showTopBanner(context, '$e');"],
      );
    });

    test('keys a repeated line by its occurrence', () {
      final keys = [
        for (final h in _scan('x.dart', r'''
void f() {
  try {} catch (e) {
    Text('$e');
    Text('$e');
  }
}
'''))
          h.key,
      ];
      expect(keys, [r"x.dart|Text('$e');", r"x.dart|Text('$e'); #2"]);
    });
  });
}
