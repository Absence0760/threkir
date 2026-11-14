// ignore_for_file: avoid_relative_lib_imports
// The one unread-messages count every inbox badge reads (the Social hub's
// Messages button, the Social nav item): issue #1374, owner decision
// "Messages move to Social".
import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/dm_pending_hides.dart';
import '../lib/unread_messages.dart';

class _Api extends ApiClient {
  _Api(this.states);

  String? uid = 'u1';
  List<DmBadgeState> states;
  Object? error;
  int reads = 0;

  /// Each read takes the first gate, if any, and answers with what it
  /// completes with instead of [states].
  final gates = <Completer<List<DmBadgeState>>>[];
  final _auth = StreamController<String?>.broadcast();

  @override
  String? get userId => uid;

  @override
  Stream<String?> get authUserChanges => _auth.stream;

  void switchTo(String? id) {
    uid = id;
    _auth.add(id);
  }

  @override
  Future<List<DmBadgeState>> fetchDmBadgeStates() async {
    reads++;
    final e = error;
    if (e != null) throw e;
    if (gates.isNotEmpty) return gates.removeAt(0).future;
    return states;
  }
}

DmBadgeState _s(String id, int unread,
        {bool muted = false, bool archived = false, bool request = false}) =>
    (
      conversationId: id,
      unread: unread,
      muted: muted,
      archived: archived,
      request: request,
    );

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UnreadMessages unread;
  setUp(() {
    DmPendingHides.instance.debugClear();
    unread = UnreadMessages(listenToLifecycle: false);
  });
  tearDown(() => unread.dispose());

  test('counts unread in conversations neither muted, archived nor requests',
      () async {
    final api = _Api([
      _s('a', 2),
      _s('b', 5, muted: true),
      _s('c', 7, archived: true),
      _s('d', 9, request: true),
      _s('e', 1),
    ]);
    var notified = 0;
    unread.addListener(() => notified++);
    unread.bind(api);
    await _flush();
    expect(unread.value, 3);
    expect(notified, 1);
  });

  test('binding the same client again does not read again', () async {
    final api = _Api([_s('a', 1)]);
    unread.bind(api);
    await _flush();
    unread.bind(api);
    await _flush();
    expect(api.reads, 1);
  });

  test('a failed read keeps the count it had', () async {
    final api = _Api([_s('a', 2)]);
    unread.bind(api);
    await _flush();
    api.error = Exception('offline');
    await unread.refresh();
    expect(unread.value, 2);
  });

  test('another account signing in drops the old count and reads anew',
      () async {
    final api = _Api([_s('a', 4)]);
    unread.bind(api);
    await _flush();
    expect(unread.value, 4);

    api.states = [_s('z', 1)];
    api.switchTo('u2');
    await _flush();
    await _flush();
    expect(unread.value, 1);

    api.switchTo(null);
    await _flush();
    await _flush();
    expect(unread.value, 0);
  });

  test('a conversation deleted in its undo window leaves the count at once',
      () async {
    final api = _Api([_s('a', 2), _s('b', 3)]);
    unread.bind(api);
    await _flush();
    expect(unread.value, 5);

    DmPendingHides.instance.add('b');
    expect(unread.value, 2);

    // Undo: the server is asked again, and still has it.
    DmPendingHides.instance.remove('b');
    await _flush();
    expect(unread.value, 5);
  });

  test('a pending delete is applied without a read, and its commit re-reads',
      () async {
    final api = _Api([_s('a', 2), _s('b', 3)]);
    unread.bind(api);
    await _flush();
    final reads = api.reads;

    DmPendingHides.instance.add('b');
    expect(unread.value, 2);
    expect(api.reads, reads);

    api.states = [_s('a', 2)];
    DmPendingHides.instance.landed('b');
    await _flush();
    expect(api.reads, reads + 1);
    expect(unread.value, 2);
  });

  test('a read that started before a delete was committed does not count the '
      'deleted conversation', () async {
    final api = _Api([_s('a', 3), _s('b', 2)]);
    unread.bind(api);
    await _flush();
    expect(unread.value, 5);

    DmPendingHides.instance.add('a');
    expect(unread.value, 2);

    // Any removal asks for a read; this one stands in for a resume or a
    // return from the inbox that is still in flight when the delete commits.
    final stale = Completer<List<DmBadgeState>>();
    api.gates.add(stale);
    DmPendingHides.instance
      ..add('z')
      ..remove('z');
    await _flush();

    api.states = [_s('b', 2)];
    DmPendingHides.instance.landed('a');
    await _flush();
    expect(unread.value, 2);

    stale.complete([_s('a', 3), _s('b', 2)]);
    await _flush();
    expect(unread.value, 2);
  });

  test('a read that lands after the account changed is dropped', () async {
    final api = _Api([]);
    final stale = Completer<List<DmBadgeState>>();
    api.gates.add(stale);
    unread.bind(api);
    await _flush();

    api.states = [_s('b', 2)];
    api.switchTo('u2');
    await _flush();
    await _flush();
    expect(unread.value, 2);

    stale.complete([_s('a', 7)]);
    await _flush();
    expect(unread.value, 2, reason: "that read was the previous account's count");
  });

  test('a landed delete stays out of the count while the read after it is in '
      'flight, and its marker goes once that read lands', () async {
    final api = _Api([_s('a', 3), _s('b', 2)]);
    unread.bind(api);
    await _flush();
    expect(unread.value, 5);

    DmPendingHides.instance.add('a');
    expect(unread.value, 2);

    final fresh = Completer<List<DmBadgeState>>();
    api.gates.add(fresh);
    DmPendingHides.instance.landed('a');
    await _flush();
    expect(unread.value, 2,
        reason: 'the count held was read before the delete landed');
    expect(DmPendingHides.instance.debugHasMarker('a'), isTrue);

    fresh.complete([_s('b', 2)]);
    await _flush();
    expect(unread.value, 2);
    expect(DmPendingHides.instance.debugHasMarker('a'), isFalse);
  });

  test('signing out lets go of a landed delete the count was keeping',
      () async {
    final api = _Api([_s('a', 3)]);
    unread.bind(api);
    await _flush();

    final pending = Completer<List<DmBadgeState>>();
    addTearDown(() {
      if (!pending.isCompleted) pending.complete(const []);
    });
    api.gates.add(pending);
    DmPendingHides.instance
      ..add('a')
      ..landed('a');
    await _flush();
    expect(DmPendingHides.instance.debugHasMarker('a'), isTrue,
        reason: 'the count held was read before the delete landed');

    api.switchTo(null);
    await _flush();
    expect(DmPendingHides.instance.debugHasMarker('a'), isFalse);
    expect(unread.value, 0);
  });

  test('unbinding clears the count', () async {
    unread.bind(_Api([_s('a', 2)]));
    await _flush();
    unread.bind(null);
    expect(unread.value, 0);
  });
}
