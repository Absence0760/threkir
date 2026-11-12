import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/undo_queue.dart';
import '../lib/widgets/undo_bar.dart';

class _AuthApi extends ApiClient {
  String? uid = 'a';
  final _controller = StreamController<String?>.broadcast();

  @override
  String? get userId => uid;

  @override
  Stream<String?> get authUserChanges => _controller.stream;

  void become(String? next) {
    uid = next;
    _controller.add(next);
  }
}

class _Spy {
  int restored = 0;
  int committed = 0;
  final List<Object> errors = [];
}

DeferredDestruction _destruction(_Spy spy, {Future<void> Function()? commit}) =>
    DeferredDestruction(
      message: 'Removed',
      commit: commit ?? () async => spy.committed++,
      restore: () => spy.restored++,
      onCommitError: spy.errors.add,
    );

Future<_AuthApi> _mount(WidgetTester tester) async {
  final api = _AuthApi();
  await tester.pumpWidget(
    UndoSessionGuard(api: api, child: const SizedBox.shrink()),
  );
  return api;
}

/// Mobile's half of web's root-layout effect (decisions § 2309, § 2317): a
/// session that ends without our Sign out runs Undo, and a commit already
/// in flight when it ends fails silently.
void main() {
  setUp(() => setUndoWindowS(0));
  tearDown(() {
    undoQueue.undo();
    debugResetUndo();
  });

  // Reason: a delete held in its window when the token was revoked (or
  // another account signed in) committed later with no session, or as the
  // next account.
  testWidgets('a session that ends some other way runs Undo, never the commit',
      (tester) async {
    final api = await _mount(tester);
    final spy = _Spy();
    undoQueue.defer(_destruction(spy));
    api.become(null);
    await tester.pump();
    expect(spy.restored, 1);
    expect(spy.committed, 0);
    expect(undoQueue.hasPending(), isFalse);
  });

  testWidgets('switching straight to another account runs Undo too',
      (tester) async {
    final api = await _mount(tester);
    final spy = _Spy();
    undoQueue.defer(_destruction(spy));
    api.become('b');
    await tester.pump();
    expect(spy.restored, 1);
    expect(spy.committed, 0);
  });

  testWidgets('a token refresh for the same account is not a change',
      (tester) async {
    final api = await _mount(tester);
    final spy = _Spy();
    undoQueue.defer(_destruction(spy));
    api.become('a');
    await tester.pump();
    expect(spy.restored, 0);
    expect(undoQueue.hasPending(), isTrue);
  });

  // Reason: the DM delete's failure banner is said on the root navigator,
  // which outlives every screen, so a commit that failed after sign-out
  // told the signed-out reader "couldn't delete" and restored the row.
  testWidgets('a commit in flight that fails after the session ended is not '
      'bannered or restored', (tester) async {
    final api = await _mount(tester);
    final spy = _Spy();
    final held = Completer<void>();
    undoQueue.defer(_destruction(spy, commit: () => held.future));
    final flushing = undoQueue.flush();
    api.become(null);
    await tester.pump();
    held.completeError(StateError('no session'));
    await flushing;
    expect(spy.restored, 0);
    expect(spy.errors, isEmpty);
  });

  testWidgets('a commit that fails while its account is still signed in '
      'still restores and reports', (tester) async {
    await _mount(tester);
    final spy = _Spy();
    final held = Completer<void>();
    undoQueue.defer(_destruction(spy, commit: () => held.future));
    final flushing = undoQueue.flush();
    held.completeError(StateError('23503'));
    await flushing;
    expect(spy.restored, 1);
    expect(spy.errors, hasLength(1));
  });
}
