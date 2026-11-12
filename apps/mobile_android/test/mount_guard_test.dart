// A State's `setState` or `context` must not be used after an `await` until
// `mounted` has been checked again.
//
// An await hands control back to the event loop; the user can leave the
// screen before it resumes, and `setState` on a disposed State throws while a
// stale `context` resolves against a tree that is gone. The OS photo and file
// pickers are the sharpest case — they leave the app entirely — but a network
// read, a dialog or a pushed route all yield the same way, so the rule is
// about every await, not a list of known-slow calls.
//
// This parses each file under lib/ and walks every async body of a State
// subclass statement by statement, tracking whether an await has happened on
// the current path since the last mounted check. It understands the guards
// the code actually writes: `if (!mounted) return;` (also `context.mounted`
// and inside an `||` chain), `if (mounted) ...` and `mounted && ...` (also in
// an `&&` chain, after an awaited operand), early exits, both arms of an
// if/else, loops whose body awaits, and try/catch/finally. A closure is a body
// of its own: it runs later, so an await outside it says nothing about it, and
// its own async body is walked from a clean start.
//
// A use that is safe for a reason the walk cannot see opts out with a
// `// mount-safe:` comment on the line or the line above, saying why. The
// marker is local, matching the other source guards, so it cannot go on
// covering the next use added to the same file.
//
// decisions § 2479.

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _marker = 'mount-safe:';

/// What one statement leaves behind: whether an await is outstanding on the
/// paths that continue past it, and whether every path through it exits.
class _Jumps {
  _Jumps({this.isSwitch = false});
  final bool isSwitch;
  bool broke = false;
  bool continued = false;
}

class _Flow {
  const _Flow(this.dirty, {this.exits = false});
  final bool dirty;
  final bool exits;
}

bool _isMountedRef(Expression e) {
  final x = e.unParenthesized;
  if (x is SimpleIdentifier) return x.name == 'mounted';
  if (x is PrefixedIdentifier) return x.identifier.name == 'mounted';
  if (x is PropertyAccess) return x.propertyName.name == 'mounted';
  return false;
}

bool _isNotMounted(Expression e) {
  final x = e.unParenthesized;
  return x is PrefixExpression &&
      x.operator.type == TokenType.BANG &&
      _isMountedRef(x.operand);
}

/// The operands of a left-associated chain of [op].
List<Expression> _chain(Expression e, TokenType op) {
  final x = e.unParenthesized;
  if (x is BinaryExpression && x.operator.type == op) {
    return [..._chain(x.leftOperand, op), ..._chain(x.rightOperand, op)];
  }
  return [x];
}

/// Whether a check in [operands] still holds once they have all run: a
/// later operand that awaits yields again, so only a check after the last
/// await counts.
bool _lastCheckHolds(List<Expression> operands, bool Function(Expression) check) {
  var holds = false;
  for (final o in operands) {
    if (check(o)) {
      holds = true;
    } else if (_hasAwait(o)) {
      holds = false;
    }
  }
  return holds;
}

/// True when [cond] being true proves the State is mounted at that point:
/// `mounted`, or an `&&` chain with a mounted operand after its last await.
bool _provesMounted(Expression cond) => _lastCheckHolds(
    _chain(cond, TokenType.AMPERSAND_AMPERSAND), _isMountedRef);

/// True when [cond] being FALSE proves the State is mounted: `!mounted`, or an
/// `||` chain with a `!mounted` operand after its last await.
bool _provesMountedWhenFalse(Expression cond) =>
    _lastCheckHolds(_chain(cond, TokenType.BAR_BAR), _isNotMounted);

bool _hasAwait(AstNode node) {
  var found = false;
  node.accept(_AwaitFinder(() => found = true));
  return found;
}


/// Finds awaits and unsafe uses in an expression, in evaluation order, without
/// entering closures (they are bodies of their own).
class _ExprScan extends RecursiveAstVisitor<void> {
  _ExprScan(this.dirty, this.report);
  bool dirty;
  final void Function(AstNode use) report;

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitAwaitExpression(AwaitExpression node) {
    super.visitAwaitExpression(node);
    dirty = true;
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.type;
    if (op == TokenType.AMPERSAND_AMPERSAND || op == TokenType.BAR_BAR) {
      node.leftOperand.accept(this);
      final after = dirty;
      final proves = op == TokenType.AMPERSAND_AMPERSAND
          ? _provesMounted(node.leftOperand)
          : _provesMountedWhenFalse(node.leftOperand);
      if (proves) dirty = false;
      node.rightOperand.accept(this);
      // The right operand may not run, so an await in it is only possibly
      // outstanding; a mounted proof on the left holds only inside it.
      dirty = after || dirty;
      return;
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    node.condition.accept(this);
    final base = dirty;
    dirty = _provesMounted(node.condition) ? false : base;
    node.thenExpression.accept(this);
    final thenDirty = dirty;
    dirty = _provesMountedWhenFalse(node.condition) ? false : base;
    node.elseExpression.accept(this);
    dirty = thenDirty || dirty;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (node.methodName.name == 'setState' &&
        (target == null || target is ThisExpression)) {
      node.argumentList.accept(this);
      if (dirty) report(node);
      return;
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name != 'context' || !dirty) return;
    final parent = node.parent;
    // `context.mounted` is the check itself, and a named argument label or
    // a property of something else is not this State's context.
    if (parent is PrefixedIdentifier &&
        parent.prefix == node &&
        parent.identifier.name == 'mounted') {
      return;
    }
    if (parent is Label) return;
    if (parent is PrefixedIdentifier && parent.identifier == node) return;
    if (parent is PropertyAccess && parent.propertyName == node) return;
    report(node);
  }
}

class _BodyWalk {
  _BodyWalk(this.report);
  final void Function(AstNode use) report;

  bool _expr(AstNode? e, bool dirty) {
    if (e == null) return dirty;
    final scan = _ExprScan(dirty, report);
    e.accept(scan);
    return scan.dirty;
  }

  /// The state each unlabelled `break` / `continue` leaves with, innermost
  /// loop or switch last.
  final _jumps = <_Jumps>[];

  /// Whether an await may be outstanding once [body] stops looping. The body
  /// is walked twice: the second pass starts from what the first left at its
  /// end (and at each `continue`), which is what every later iteration sees.
  /// The loop ends when its head stops it or at a `break`, so both count.
  bool _loop(
    Statement body,
    bool entry, {
    bool perIteration = false,
    bool bodyStartsMounted = false,
  }) {
    _Flow pass(bool start) =>
        stmt(body, bodyStartsMounted ? false : start || perIteration);
    _jumps.add(_Jumps());
    final first = pass(entry);
    final firstJumps = _jumps.removeLast();
    final carried = entry ||
        perIteration ||
        (!first.exits && first.dirty) ||
        firstJumps.continued;
    _jumps.add(_Jumps());
    final second = pass(carried);
    final secondJumps = _jumps.removeLast();
    return carried ||
        (!second.exits && second.dirty) ||
        firstJumps.broke ||
        secondJumps.broke ||
        secondJumps.continued;
  }

  _Flow block(List<Statement> statements, bool dirty) {
    var d = dirty;
    for (final s in statements) {
      final f = stmt(s, d);
      if (f.exits) return _Flow(f.dirty, exits: true);
      d = f.dirty;
    }
    return _Flow(d);
  }

  _Flow stmt(Statement s, bool dirty) {
    switch (s) {
      case Block():
        return block(s.statements, dirty);
      case ExpressionStatement():
        return _Flow(_expr(s.expression, dirty));
      case VariableDeclarationStatement():
        return _Flow(_expr(s.variables, dirty));
      case ReturnStatement():
        _expr(s.expression, dirty);
        return _Flow(dirty, exits: true);
      case BreakStatement():
        if (s.label != null || _jumps.isEmpty) return _Flow(true, exits: true);
        _jumps.last.broke = _jumps.last.broke || dirty;
        return _Flow(dirty, exits: true);
      case ContinueStatement():
        final loop = _jumps.lastWhere((j) => !j.isSwitch, orElse: _Jumps.new);
        if (s.label != null || _jumps.isEmpty) return _Flow(true, exits: true);
        loop.continued = loop.continued || dirty;
        return _Flow(dirty, exits: true);
      case IfStatement():
        final afterCond = _expr(s.expression, dirty);
        final cond = s.expression;
        final thenIn = _provesMounted(cond) ? false : afterCond;
        final elseIn = _provesMountedWhenFalse(cond) ? false : afterCond;
        final t = stmt(s.thenStatement, thenIn);
        final elseStatement = s.elseStatement;
        final e =
            elseStatement == null ? _Flow(elseIn) : stmt(elseStatement, elseIn);
        if (t.exits && e.exits) return _Flow(false, exits: true);
        if (t.exits) return _Flow(e.dirty);
        if (e.exits) return _Flow(t.dirty);
        return _Flow(t.dirty || e.dirty);
      case WhileStatement():
        final head = _expr(s.condition, dirty);
        return _Flow(_loop(
          s.body,
          head,
          perIteration: _hasAwait(s.condition),
          bodyStartsMounted: _provesMounted(s.condition),
        ));
      case DoStatement():
        final end = _loop(s.body, dirty, perIteration: _hasAwait(s.condition));
        return _Flow(_expr(s.condition, end));
      case ForStatement():
        var d = dirty;
        var perIteration = s.awaitKeyword != null;
        final parts = s.forLoopParts;
        if (parts is ForPartsWithDeclarations) d = _expr(parts.variables, d);
        if (parts is ForPartsWithExpression) d = _expr(parts.initialization, d);
        if (parts is ForParts) {
          final condition = parts.condition;
          if (condition != null && _hasAwait(condition)) perIteration = true;
          if (parts.updaters.any(_hasAwait)) perIteration = true;
        }
        if (parts is ForEachParts) d = _expr(parts.iterable, d);
        return _Flow(_loop(s.body, d, perIteration: perIteration));
      case TryStatement():
        final t = block(s.body.statements, dirty);
        final threw = dirty || _hasAwait(s.body);
        var out = t.exits ? null : t.dirty;
        var allExit = t.exits;
        for (final c in s.catchClauses) {
          final cf = block(c.body.statements, threw);
          if (!cf.exits) out = (out ?? false) || cf.dirty;
          allExit = allExit && cf.exits;
        }
        final fin = s.finallyBlock;
        if (fin != null) {
          final ff = block(fin.statements, threw || (out ?? false));
          if (ff.exits) return _Flow(ff.dirty, exits: true);
          out = out == null ? null : ff.dirty;
        }
        if (allExit && out == null) return _Flow(false, exits: true);
        return _Flow(out ?? false);
      case SwitchStatement():
        final d = _expr(s.expression, dirty);
        _jumps.add(_Jumps(isSwitch: true));
        var out = d;
        for (final m in s.members) {
          final f = block(m.statements, d);
          if (!f.exits) out = out || f.dirty;
        }
        final j = _jumps.removeLast();
        return _Flow(out || j.broke);
      case LabeledStatement():
        return stmt(s.statement, dirty);
      case FunctionDeclarationStatement():
        return _Flow(dirty);
      default:
        return _Flow(_expr(s, dirty));
    }
  }

  void body(FunctionBody b) {
    if (b is BlockFunctionBody) {
      block(b.block.statements, false);
    } else if (b is ExpressionFunctionBody) {
      _expr(b.expression, false);
    }
  }
}

class _AwaitFinder extends RecursiveAstVisitor<void> {
  _AwaitFinder(this.found);
  final void Function() found;
  @override
  void visitFunctionExpression(FunctionExpression node) {}
  @override
  void visitAwaitExpression(AwaitExpression node) => found();
  @override
  void visitForStatement(ForStatement node) {
    if (node.awaitKeyword != null) found();
    super.visitForStatement(node);
  }
}

/// Every async body (method, local function or closure) inside a State.
class _AsyncBodies extends RecursiveAstVisitor<void> {
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

bool _isStateType(String? name) =>
    name != null && (name == 'State' || name.endsWith('State'));

/// A State subclass, or a mixin that can only be applied to one.
bool _isStateScope(CompilationUnitMember m) => switch (m) {
      ClassDeclaration() =>
        _isStateType(m.extendsClause?.superclass.name.lexeme),
      MixinDeclaration() => m.onClause?.superclassConstraints
              .any((t) => _isStateType(t.name.lexeme)) ??
          false,
      _ => false,
    };

/// `file:line` for each unsafe use in [source].
List<String> findUnguardedUses(String source, {String path = '<source>'}) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final lines = source.split('\n');
  final out = <String>{};
  for (final decl in unit.declarations) {
    if (!_isStateScope(decl)) continue;
    final finder = _AsyncBodies();
    decl.accept(finder);
    for (final b in finder.bodies) {
      _BodyWalk((use) {
        final line = unit.lineInfo.getLocation(use.offset).lineNumber;
        final here = lines[line - 1];
        final above = line >= 2 ? lines[line - 2] : '';
        if (here.contains(_marker) || above.contains(_marker)) return;
        final what = use is MethodInvocation ? 'setState' : 'context';
        out.add('$path:$line ($what)');
      }).body(b);
    }
  }
  return out.toList();
}

String _state(String body) => '''
import 'package:flutter/material.dart';
class W extends StatefulWidget {
  @override
  State<W> createState() => _S();
}
class _S extends State<W> {
  int n = 0;
  Future<int> load() async => 1;
$body
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

void main() {
  group('the walk', () {
    final flagged = <String, String>{
      'a setState after an await': '''
  Future<void> f() async { await load(); setState(() => n = 1); }''',
      'a context use after an await': '''
  Future<void> f() async { await load(); Navigator.of(context).pop(); }''',
      'a mounted check placed after the setState it meant to guard': '''
  Future<void> f() async {
    await load();
    setState(() => n = 1);
    if (!mounted) return;
  }''',
      'an await in one arm of an if': '''
  Future<void> f(bool x) async {
    if (x) await load();
    setState(() => n = 1);
  }''',
      'an await in a try reaching the catch': '''
  Future<void> f() async {
    try { await load(); } catch (_) { setState(() => n = 1); }
  }''',
      'an await on the previous loop iteration': '''
  Future<void> f() async {
    for (var i = 0; i < 2; i++) { setState(() => n = i); await load(); }
  }''',
      'a mounted check that does not exit': '''
  Future<void> f() async {
    await load();
    if (!mounted) debugPrint('gone');
    setState(() => n = 1);
  }''',
      'an await inside the setState argument list': '''
  Future<void> f() async { setState(() {}); n = await load(); setState(() {}); }''',
      'an async closure with its own await': '''
  void f() { load().then((_) async { await load(); setState(() {}); }); }''',
      'an await in a loop body that a break leaves before its check': '''
  Future<void> f() async {
    for (var i = 0; i < 2; i++) { await load(); if (i > 0) break; if (!mounted) return; }
    setState(() {});
  }''',
      // The async-gap shapes issue #734 found.
      'an await inside a try reaching the code after it': '''
  Future<void> f() async { try { await load(); } catch (e) {} setState(() {}); }''',
      'a block whose last statement is the await': '''
  Future<void> f(bool x, bool y) async {
    if (x) { if (y) { n = 1; } await load(); }
    setState(() {});
  }''',
      'a closure whose own return does not end the block holding it': '''
  Future<void> f(bool x) async {
    if (x) { await load(); final c = () { return; }; c; }
    setState(() {});
  }''',
      'a return inside a closure argument': '''
  Future<void> f(bool x) async {
    if (x) { await load(); load().then((_) { return; }); }
    setState(() {});
  }''',
      'a switch whose last case returns but an earlier one awaits': '''
  Future<void> f(int x, bool y) async {
    switch (x) { case 1: await load(); case 2: if (y) { n = 1; } return; }
    setState(() {});
  }''',
      'a mounted check inside a catch that exits': '''
  Future<void> f() async {
    try { await load(); } catch (e) { if (!mounted) return; n = 1; return; }
    setState(() {});
  }''',
      'a setState in a mixin on State': '''
}
mixin M<T extends StatefulWidget> on State<T> {
  Future<int> load() async => 1;
  Future<void> f() async { await load(); setState(() {}); }''',
      'an await before a mounted proof on the RIGHT of an &&': '''
  Future<void> f() async { if (mounted && await load() > 0) setState(() {}); }''',
    };
    final clean = <String, String>{
      'a setState with no await before it': '''
  Future<void> f() async { setState(() => n = 1); await load(); }''',
      'if (!mounted) return between them': '''
  Future<void> f() async {
    await load();
    if (!mounted) return;
    setState(() => n = 1);
  }''',
      'context.mounted in an || chain': '''
  Future<void> f(bool x) async {
    await load();
    if (x || !context.mounted) return;
    Navigator.of(context).pop();
  }''',
      'if (mounted) around the use': '''
  Future<void> f() async { await load(); if (mounted) setState(() {}); }''',
      'an awaited operand then mounted in an && chain': '''
  Future<void> f() async { if (await load() > 0 && mounted) setState(() {}); }''',
      'an await that is followed only by a return': '''
  Future<void> f(bool x) async {
    if (x) { await load(); return; }
    setState(() => n = 1);
  }''',
      'a sync closure created after an await': '''
  Future<void> f() async {
    await load();
    if (!mounted) return;
    load().then((_) => setState(() {}));
  }''',
      'a sync callback that runs later': '''
  Future<void> f() async { await load(); final cb = () => setState(() {}); cb; }''',
      'a closure parameter that shadows context': '''
  Future<void> f() async {
    await load();
    showDialog<void>(context: this.context, builder: (context) => const SizedBox()); // mount-safe: fixture
  }''',
      'a mount-safe marker with a reason': '''
  Future<void> f() async {
    await load();
    // mount-safe: fixture
    setState(() {});
  }''',
      'a loop that breaks only after checking mounted': '''
  Future<void> f() async {
    for (var i = 0; i < 2; i++) { await load(); if (!mounted) return; if (i > 0) break; }
    setState(() {});
  }''',
      'a break that leaves a switch, not the loop around it': '''
  Future<void> f(int x) async {
    for (var i = 0; i < 2; i++) {
      switch (x) { case 1: break; }
      await load();
      if (!mounted) return;
    }
    setState(() {});
  }''',
      'a loop whose body checks mounted after its await': '''
  Future<void> f() async {
    for (var i = 0; i < 2; i++) { await load(); if (!mounted) return; }
    setState(() {});
  }''',
      // The async-gap shapes issue #734 found.
      'an if/else of awaits that then returns': '''
  Future<void> f(bool x, bool y) async {
    if (x) { if (y) { await load(); } else { await load(); } return; }
    setState(() {});
  }''',
      'a try/catch of an await that then returns': '''
  Future<void> f(bool x) async {
    if (x) { try { await load(); } catch (e) { n = 1; } return; }
    setState(() {});
  }''',
      'a return of a map literal after an await': '''
  Future<Object?> f(bool x) async {
    if (x) { await load(); return {1: 2}; }
    setState(() {});
    return null;
  }''',
      'a return of a switch expression after an await': '''
  Future<int> f(bool x, int y) async {
    if (x) { await load(); return switch (y) { 1 => 2, _ => 3 }; }
    setState(() {});
    return 0;
  }''',
      'a commented-out setState': '''
  Future<void> f() async { await load(); /* setState(() {}); */ }''',
      'a mounted ternary': '''
  Future<void> f() async { await load(); mounted ? setState(() {}) : null; }''',
      'a class that is not a State': '''
}
class Plain {
  void setState(void Function() f) {}
  Future<int> load() async => 1;
  Future<void> f() async { await load(); setState(() {}); }''',
    };
    for (final e in flagged.entries) {
      test('flags ${e.key}', () {
        expect(findUnguardedUses(_state(e.value)), isNotEmpty, reason: e.key);
      });
    }
    for (final e in clean.entries) {
      test('spares ${e.key}', () {
        expect(findUnguardedUses(_state(e.value)), isEmpty, reason: e.key);
      });
    }
  });

  test('no State in lib/ uses setState or context after an await without '
      'checking mounted', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.contains('/gen/'));
    for (final f in files) {
      offenders.addAll(findUnguardedUses(f.readAsStringSync(), path: f.path));
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Check `mounted` (or `context.mounted`) after the await and before '
          'the use — `if (!mounted) return;` — or, when the use is safe for '
          'a reason this walk cannot see, say why in a `// $_marker` comment '
          'on the line or the line above:\n${offenders.join('\n')}',
    );
  });
}
