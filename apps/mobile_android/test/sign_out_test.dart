import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/sign_out.dart';
import '../lib/undo_queue.dart';
import '../lib/widgets/undo_bar.dart';

/// Mirror of web `stores/sign_out.test.ts`'s settle cases: a delete still
/// inside its undo window commits before the session ends, and settling
/// never holds the sign-out hostage.
void main() {
  tearDown(debugResetUndo);

  test('the cap is five seconds, matching web', () {
    expect(kSignOutSettleTimeout, const Duration(seconds: 5));
  });

  test('a pending delete commits before the session ends', () async {
    final order = <String>[];
    await signOutAfterSettling(
      settlePending: () async => order.add('settle'),
      signOut: () async => order.add('signOut'),
    );
    expect(order, ['settle', 'signOut']);
  });

  test('the real undo queue is settled: its held commit runs first',
      () async {
    setUndoWindowS(0);
    final order = <String>[];
    var restored = 0;
    undoQueue.defer(DeferredDestruction(
      message: 'Removed',
      commit: () async => order.add('commit'),
      restore: () => restored++,
    ));
    await signOutAfterSettling(
      settlePending: undoQueue.flush,
      signOut: () async => order.add('signOut'),
    );
    expect(order, ['commit', 'signOut']);
    expect(restored, 0);
    expect(undoQueue.hasPending(), isFalse);
  });

  test('a settle that throws is logged and the sign-out still runs',
      () async {
    var signedOut = false;
    await signOutAfterSettling(
      settlePending: () async => throw StateError('offline'),
      signOut: () async => signedOut = true,
    );
    expect(signedOut, isTrue);
  });

  testWidgets('a stalled settle holds the sign-out for at most the cap',
      (tester) async {
    final stalled = Completer<void>();
    var signedOut = false;
    unawaited(signOutAfterSettling(
      settlePending: () => stalled.future,
      signOut: () async => signedOut = true,
    ));
    await tester.pump(kSignOutSettleTimeout - const Duration(milliseconds: 1));
    expect(signedOut, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(signedOut, isTrue);
  });

  test('the sign-out itself failing still reaches the caller', () async {
    await expectLater(
      signOutAfterSettling(
        settlePending: () async {},
        signOut: () async => throw StateError('refused'),
      ),
      throwsStateError,
    );
  });

  // Reason: Settings → Sign out and delete-account ended the session with a
  // delete still held, so its timer fired later with no session or as the
  // next account. Every path that ends the session settles first.
  test('every sign-out in lib/ settles the undo queue first', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('sign_out.dart')) continue;
      final src = f.readAsStringSync();
      if (!RegExp(r'\.signOut\b').hasMatch(src)) continue;
      if (!src.contains('undoQueue.flush')) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });
}
