import 'dart:async';
import 'dart:developer' as developer;

/// Deferred-commit undo — the widget-free core of the mobile app's undo
/// contract, and the Dart twin of web `core/undo_queue.ts`.
///
/// Three contracts were on the table and only one of them can be honest
/// for the actions we adopt it on:
///
///   1. A compensating inverse (re-insert what was deleted) mints a NEW
///      server id, and anything the original row owned — cascaded
///      replies, a Storage object's bytes — is already unrecoverable. An
///      "Undo" that hands back a different row is a lie.
///   2. A soft delete + restore is the honest answer for a *trash*
///      feature, but it costs a `deleted_at` column on every adopting
///      table, an RLS/read-path filter everywhere, and a retention story.
///   3. Deferring the mutation until the undo window closes means
///      **nothing is destroyed while undo is on offer**, so undo cannot
///      fail. That is this module.
///
/// The row leaves the caller's local list immediately (the action feels
/// done) while `commit` is held. Undo cancels the pending commit and
/// calls `restore`; the server was never touched. A commit that later
/// fails also calls `restore`, so a list never claims a row is gone
/// while the server still holds it — unless the account that queued it
/// is no longer the one signed in (the session ended while the commit
/// was in flight). That failure is logged and nothing else: no banner to
/// a signed-out reader, and no restore into what is now another
/// account's list.
///
/// One slot, deliberately: a second destruction commits the first
/// immediately rather than stacking bars whose ordering the user would
/// have to reason about.
///
/// Kept free of Flutter and of `Timer` so it is host-testable against a
/// fake clock (see test/undo_queue_test.dart); the overlay host lives in
/// widgets/undo_bar.dart.

/// The undo window in seconds, keyed by the `undo_window_s` pref.
/// `0` turns the time limit off entirely — the WCAG 2.2.1 "Turn off"
/// route, so a screen-reader or motor-impaired user is never racing a
/// countdown to reach the only undo affordance.
const List<int> kUndoWindowChoicesS = [8, 30, 0];
const int kDefaultUndoWindowS = 8;

/// Normalises a stored `undo_window_s` bag value. An absent, corrupt, or
/// unrecognised value falls back to the default rather than to `0` — a
/// garbage bag must not silently pin every destructive action open
/// forever, which would leave the user's list disagreeing with the
/// server until they navigate.
int undoWindowSFromPref(Object? raw) {
  if (raw is! num || !raw.isFinite) return kDefaultUndoWindowS;
  final value = raw.toInt();
  if (value != raw) return kDefaultUndoWindowS;
  return kUndoWindowChoicesS.contains(value) ? value : kDefaultUndoWindowS;
}

class DeferredDestruction {
  const DeferredDestruction({
    required this.message,
    required this.commit,
    required this.restore,
    this.onCommitError,
  });

  /// Already-localized sentence for the undo bar ("Porridge removed").
  final String message;

  /// The server mutation. Runs when the window closes — never at the
  /// moment the user taps delete.
  final Future<void> Function() commit;

  /// Puts the caller's local state back exactly as it was. Run on undo
  /// and on a commit failure.
  final void Function() restore;

  /// Surfaces a commit failure at the call site (a banner).
  final void Function(Object error)? onCommitError;
}

class PendingUndo {
  const PendingUndo({
    required this.id,
    required this.message,
    required this.windowMs,
    required this.paused,
  });

  final int id;
  final String message;

  /// How long the bar has to run, in ms. `0` means there is no time
  /// limit at all — the user's chosen "until I dismiss it" window.
  final int windowMs;
  final bool paused;
}

class UndoQueueDeps {
  const UndoQueueDeps({
    required this.windowMs,
    required this.setTimer,
    required this.clearTimer,
    required this.now,
    required this.onChange,
    this.owner,
    this.log,
  });

  /// The undo window in ms, read at defer time. `0` or less disables
  /// the timer entirely (WCAG 2.2.1 "turn off").
  final int Function() windowMs;
  final Object Function(void Function() cb, int ms) setTimer;
  final void Function(Object handle) clearTimer;
  final int Function() now;
  final void Function(PendingUndo? pending) onChange;

  /// The signed-in account, read when a destruction is queued and again
  /// when its commit fails. Absent, every destruction has one owner.
  final String? Function()? owner;

  /// Where a commit that failed after its account changed is reported.
  /// Absent, it goes to `dart:developer`'s log.
  final void Function(String message, Object error)? log;
}

class _Entry {
  _Entry({
    required this.id,
    required this.owner,
    required this.destruction,
    required this.windowMs,
    required this.remainingMs,
    required this.startedAt,
  });

  final int id;
  final String? owner;
  final DeferredDestruction destruction;
  final int windowMs;
  int remainingMs;
  int startedAt;
  bool paused = false;
  Object? timer;
  bool settled = false;
}

class UndoQueue {
  UndoQueue(this._deps);

  final UndoQueueDeps _deps;

  String? _owner() => _deps.owner?.call();

  void _log(String message, Object error) {
    final log = _deps.log;
    if (log != null) {
      log(message, error);
    } else {
      developer.log(message, name: 'undo', error: error);
    }
  }

  int _nextId = 1;
  _Entry? _current;

  bool hasPending() => _current != null;

  void _publish() {
    final c = _current;
    _deps.onChange(c == null
        ? null
        : PendingUndo(
            id: c.id,
            message: c.destruction.message,
            windowMs: c.windowMs,
            paused: c.paused,
          ));
  }

  void _disarm() {
    final c = _current;
    final timer = c?.timer;
    if (timer != null) {
      _deps.clearTimer(timer);
      c!.timer = null;
    }
  }

  void _arm() {
    final c = _current;
    if (c == null || c.windowMs <= 0) return;
    c.startedAt = _deps.now();
    c.timer = _deps.setTimer(() => unawaited(flush()), c.remainingMs);
  }

  /// Detaches the pending entry so a concurrent flush/undo/defer can't
  /// act on it twice. Returns null when there was nothing pending.
  _Entry? _take() {
    final c = _current;
    if (c == null || c.settled) return null;
    c.settled = true;
    _disarm();
    _current = null;
    _publish();
    return c;
  }

  /// Commits that have left the slot and not yet settled. [_take] detaches
  /// an entry before its commit runs, so without this a flush that found
  /// the slot empty could not see a commit the timer or [defer] had already
  /// started.
  final Set<Future<void>> _inFlight = {};

  Future<void> _settle(_Entry taken) {
    final destruction = taken.destruction;
    Future<void> run() async {
      try {
        await destruction.commit();
      } catch (error) {
        if (_owner() != taken.owner) {
          _log(
            'undo: a held delete failed after the account that made it '
            'signed out',
            error,
          );
          return;
        }
        destruction.restore();
        destruction.onCommitError?.call(error);
      }
    }

    final settling = run();
    _inFlight.add(settling);
    settling.then(
      (_) => _inFlight.remove(settling),
      onError: (Object _) => _inFlight.remove(settling),
    );
    return settling;
  }

  /// Commit the pending destruction now — the dismiss button, a
  /// navigation, a second destruction arriving, or a sign-out. Completes
  /// once every commit this queue has started has settled, including one
  /// the window timer or a later [defer] set going before this call: a
  /// sign-out that awaits it ends the session only after a failure has
  /// restored and reported to the account that made the delete.
  Future<void> flush() async {
    final taken = _take();
    final own = taken == null ? null : _settle(taken);
    final others = _inFlight.where((f) => !identical(f, own)).toList();
    await Future.wait(
      others.map((f) => f.then((_) {}, onError: (Object _) {})),
    );
    if (own != null) await own;
  }

  void defer(DeferredDestruction destruction) {
    unawaited(flush());
    final requested = _deps.windowMs();
    final windowMs = requested < 0 ? 0 : requested;
    _current = _Entry(
      id: _nextId++,
      owner: _owner(),
      destruction: destruction,
      windowMs: windowMs,
      remainingMs: windowMs,
      startedAt: _deps.now(),
    );
    _arm();
    _publish();
  }

  void undo() {
    final taken = _take();
    if (taken == null) return;
    taken.destruction.restore();
  }

  void pause() {
    final c = _current;
    if (c == null || c.paused || c.windowMs <= 0) return;
    final elapsed = _deps.now() - c.startedAt;
    final remaining = c.remainingMs - elapsed;
    c.remainingMs = remaining < 0 ? 0 : remaining;
    _disarm();
    c.paused = true;
    _publish();
  }

  void resume() {
    final c = _current;
    if (c == null || !c.paused || c.windowMs <= 0) return;
    c.paused = false;
    _arm();
    _publish();
  }
}
