// ignore_for_file: avoid_relative_lib_imports
// Mirrors apps/web/src/lib/social/dm_read_receipt.test.ts case-for-case.
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/dm_read_receipt.dart';

const _me = 'me';
const _them = 'them';

DirectMessageRow _msg(String id, String sender, [DateTime? seenAt]) =>
    DirectMessageRow(
      kind: 'text',
      id: id,
      conversationId: 'c-1',
      senderId: sender,
      recipientId: sender == _me ? _them : _me,
      body: 'body $id',
      createdAt: DateTime.utc(2026, 11, 7, 10),
      seenAt: seenAt,
    );

void main() {
  test("seenReceipt is the viewer's newest seen message", () {
    final list = [
      _msg('1', _me, DateTime.utc(2026, 11, 7, 10)),
      _msg('2', _me, DateTime.utc(2026, 11, 7, 10, 1)),
      _msg('3', _them),
      _msg('4', _me),
    ];
    expect(seenReceipt(list, _me)?.id, '2');
  });

  test("seenReceipt ignores the partner's messages and unseen ones", () {
    expect(
      seenReceipt([_msg('1', _them, DateTime.utc(2026, 11, 7)), _msg('2', _me)], _me),
      isNull,
    );
  });

  test('seenReceipt is null with no viewer or no messages', () {
    expect(seenReceipt([_msg('1', _me, DateTime.utc(2026, 11, 7))], null), isNull);
    expect(seenReceipt([], _me), isNull);
  });

  test('dmMarkReadThrough is the newest partner message', () {
    final list = [_msg('1', _them), _msg('2', _them), _msg('3', _me)];
    expect(dmMarkReadThrough(list, _them, null)?.id, '2');
  });

  test('dmMarkReadThrough is null once that message is marked', () {
    final list = [_msg('1', _them), _msg('2', _them), _msg('3', _me)];
    expect(dmMarkReadThrough(list, _them, '2'), isNull);
  });

  test('dmMarkReadThrough moves on when a newer partner message arrives', () {
    final list = [_msg('1', _them), _msg('2', _them), _msg('3', _them)];
    expect(dmMarkReadThrough(list, _them, '2')?.id, '3');
  });

  test('dmMarkReadThrough is null with nothing from the partner', () {
    expect(dmMarkReadThrough([_msg('1', _me)], _them, null), isNull);
    expect(dmMarkReadThrough([], _them, null), isNull);
  });
}
