// A handler that awaits a read and then opens a screen, sheet or dialog lets
// a second tap in the read's window open a second copy (issue #1374 NS-11):
// two run details stacked over each other, two gear pickers whose second Save
// overwrote the first. `SingleFlight.openOnce` (lib/widgets/single_flight.dart)
// drops the second tap.
//
// This parses every file under lib/ and, for each async body, looks for an
// opener (`push…`, `showModalBottomSheet`, `showDialog`, …) that comes after
// an await of something that is not itself modal. Awaiting a dialog, sheet,
// route or picker is not a window: the barrier takes the second tap. A body
// passes when it runs inside `openOnce` — as the closure handed to it, or as
// a function that closure calls by name in the same file.
//
// A body that is safe for a reason the scan cannot see opts out with a
// `// single-flight:` comment on the opener's line or the line above, saying
// why. The bodies not yet converted are counted per file in `_unconverted`,
// which may only shrink: a file whose count rises fails, and so does one whose
// count falls without the map being lowered.

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _marker = 'single-flight:';

/// Calls that open something modal: a route, a sheet, a dialog.
final _opener = RegExp(
    r'^(push|pushReplacement|pushNamed|pushAndRemoveUntil|'
    r'pushNamedAndRemoveUntil|pushReplacementNamed|showModalBottomSheet|'
    r'showDialog|showGeneralDialog|showCupertinoDialog|'
    r'showCupertinoModalPopup|showSearch|showMenu)$');

/// An awaited call by these names is modal itself (or leaves the app), so
/// the second tap meets a barrier, not a window.
final _modalAwait = RegExp(
    r'^(show[A-Z]\w*|push|pushReplacement|pushNamed|confirm\w*|prompt\w*|'
    r'pick\w*|maybePop|returnToShell|ensureSignedIn)$');

/// Bodies not yet routed through openOnce, per file. May only shrink.
const _unconverted = <String, int>{
  'lib/screens/club_detail_screen.dart': 3,
  'lib/screens/club_invite_screen.dart': 1,
  'lib/screens/course_drive_screen.dart': 1,
  'lib/screens/event_detail_screen.dart': 4,
  'lib/screens/group_thread_screen.dart': 1,
  'lib/screens/period_summary_screen.dart': 1,
  'lib/screens/plan_detail_screen.dart': 2,
  'lib/screens/plan_library_screen.dart': 1,
  'lib/screens/plan_new_screen.dart': 3,
  'lib/screens/race_detail_screen.dart': 2,
  'lib/screens/route_detail_screen.dart': 2,
  'lib/screens/routine_public_library_screen.dart': 1,
  'lib/screens/run_screen.dart': 3,
  'lib/screens/season_plan_screen.dart': 1,
  'lib/widgets/coach_share_card.dart': 1,
  'lib/widgets/plan_overlap_dialog.dart': 1,
  'lib/widgets/run_park_course_chips.dart': 1,
  'lib/widgets/upcoming_event_card.dart': 1,
};

String? _calledName(Expression e) {
  final x = e.unParenthesized;
  if (x is MethodInvocation) return x.methodName.name;
  if (x is FunctionExpressionInvocation) {
    final f = x.function.unParenthesized;
    if (f is SimpleIdentifier) return f.name;
  }
  return null;
}

/// Awaits and openers directly in one body, skipping nested closures, which
/// are bodies of their own.
class _BodyScan extends RecursiveAstVisitor<void> {
  /// Where a read's await ends (a window opens).
  final reads = <int>[];

  /// Where an await of something modal ends: the runner was inside it, so
  /// the window a read opened before it has closed.
  final modals = <int>[];
  final openers = <MethodInvocation>[];

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitAwaitExpression(AwaitExpression node) {
    super.visitAwaitExpression(node);
    var inner = node.expression.unParenthesized;
    // `await x.timeout(...)` / `.then(...)` wraps the call that matters.
    while (inner is MethodInvocation &&
        (inner.methodName.name == 'timeout' ||
            inner.methodName.name == 'then') &&
        inner.target != null) {
      inner = inner.target!.unParenthesized;
    }
    final name = _calledName(inner);
    if (name != null && (_modalAwait.hasMatch(name) || _opener.hasMatch(name))) {
      modals.add(node.end);
      return;
    }
    reads.add(node.end);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (_opener.hasMatch(node.methodName.name)) openers.add(node);
  }
}

/// Names reached from inside an `openOnce(...)` argument in [unit].
Set<String> _guardedNames(CompilationUnit unit) {
  final names = <String>{};
  unit.accept(_OpenOnceArgs(names));
  return names;
}

class _OpenOnceArgs extends RecursiveAstVisitor<void> {
  _OpenOnceArgs(this.names);
  final Set<String> names;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'openOnce') {
      for (final arg in node.argumentList.arguments) {
        arg.accept(_Names(names));
      }
    }
    super.visitMethodInvocation(node);
  }
}

class _Names extends RecursiveAstVisitor<void> {
  _Names(this.names);
  final Set<String> names;
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) => names.add(node.name);
}

bool _insideOpenOnce(AstNode body) {
  final fn = body.parent;
  if (fn is! FunctionExpression) return false;
  AstNode? p = fn.parent;
  if (p is NamedExpression) p = p.parent;
  if (p is ArgumentList) {
    final call = p.parent;
    return call is MethodInvocation && call.methodName.name == 'openOnce';
  }
  return false;
}

String? _bodyName(FunctionBody body) {
  final p = body.parent;
  if (p is MethodDeclaration) return p.name.lexeme;
  if (p is FunctionExpression && p.parent is FunctionDeclaration) {
    return (p.parent! as FunctionDeclaration).name.lexeme;
  }
  return null;
}

class _Bodies extends RecursiveAstVisitor<void> {
  final bodies = <FunctionBody>[];
  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {
    if (node.isAsynchronous) bodies.add(node);
    super.visitBlockFunctionBody(node);
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    if (node.isAsynchronous) bodies.add(node);
    super.visitExpressionFunctionBody(node);
  }
}

/// The unguarded bodies in [source], as `line` of the first late opener.
List<int> unguardedOpeners(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final lines = source.split('\n');
  final guarded = _guardedNames(unit);
  final finder = _Bodies();
  unit.accept(finder);
  final out = <int>[];
  for (final body in finder.bodies) {
    if (_insideOpenOnce(body)) continue;
    final name = _bodyName(body);
    if (name != null && guarded.contains(name)) continue;
    final scan = _BodyScan();
    body.visitChildren(scan);
    if (scan.reads.isEmpty) continue;
    // An opener is late when a read's await ended after the last modal await
    // that precedes it: that read is the window a second tap lands in.
    bool late(int at) {
      final read = scan.reads.where((r) => r <= at).fold(-1, (a, b) => b > a ? b : a);
      if (read < 0) return false;
      final modal = scan.modals.where((m) => m <= at).fold(-1, (a, b) => b > a ? b : a);
      return read > modal;
    }
    for (final opener in scan.openers) {
      if (!late(opener.offset)) continue;
      final line = unit.lineInfo.getLocation(opener.offset).lineNumber;
      final here = lines[line - 1];
      final above = line >= 2 ? lines[line - 2] : '';
      if (here.contains(_marker) || above.contains(_marker)) continue;
      out.add(line);
      break;
    }
  }
  return out;
}

void main() {
  test('the scan bites on a read-then-push and passes the guarded forms', () {
    const bad = '''
class S {
  Future<void> open() async {
    final run = await api.fetchRun();
    Navigator.of(context).push(route(run));
  }
}''';
    const guarded = '''
class S {
  final _nav = SingleFlight();
  void tap() => _nav.openOnce(() async {
        final run = await api.fetchRun();
        await Navigator.of(context).push(route(run));
      });
  Future<void> named() async {
    final run = await api.fetchRun();
    showDialog(context: context, builder: (_) => Text(run));
  }
  void tap2() => _nav.openOnce(named);
}''';
    const modal = '''
class S {
  Future<void> confirmThenPush() async {
    final ok = await showDialog<bool>(context: context, builder: b);
    if (ok == true) Navigator.of(context).push(route());
  }
}''';
    expect(unguardedOpeners(bad), hasLength(1));
    expect(unguardedOpeners(guarded), isEmpty);
    expect(unguardedOpeners(modal), isEmpty);
  });

  test('every read-then-open is single-flight, or counted as unconverted', () {
    final counts = <String, int>{};
    final where = <String, List<int>>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (path.contains('/l10n/gen/')) continue;
      final hits = unguardedOpeners(f.readAsStringSync());
      if (hits.isEmpty) continue;
      counts[path] = hits.length;
      where[path] = hits;
    }
    final drift = <String>[];
    for (final path in {...counts.keys, ..._unconverted.keys}) {
      final now = counts[path] ?? 0;
      final pinned = _unconverted[path] ?? 0;
      if (now > pinned) {
        drift.add('$path: $now unguarded (allowed $pinned), at lines '
            '${where[path]}. Route the handler through SingleFlight.openOnce.');
      } else if (now < pinned) {
        drift.add('$path: $now unguarded, below the $pinned pinned. Lower '
            '_unconverted to match.');
      }
    }
    expect(drift, isEmpty, reason: drift.join('\n'));
  });
}
