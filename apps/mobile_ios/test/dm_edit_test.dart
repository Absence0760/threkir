// ignore_for_file: avoid_relative_lib_imports
// Mirrors apps/web/src/lib/social/dm_edit.test.ts case-for-case.
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/dm_edit.dart';

const _me = 'me';
final _sent = DateTime.utc(2026, 11, 8, 10);
DateTime _at(int minutes) => _sent.add(Duration(minutes: minutes));

DirectMessageRow _msg({
  String sender = _me,
  DateTime? unsentAt,
  String? body = 'hello',
}) =>
    DirectMessageRow(
      id: 'm-1',
      conversationId: 'c-1',
      senderId: sender,
      recipientId: sender == _me ? 'them' : _me,
      body: body,
      createdAt: _sent,
      unsentAt: unsentAt,
    );

void main() {
  test('the window is the one edit_direct_message enforces', () {
    final dir = Directory('../backend/supabase/migrations');
    final file = dir
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('_dm_edit.sql'));
    final m = RegExp(r"c_window constant interval := interval '(\d+) minutes'")
        .firstMatch(file.readAsStringSync());
    expect(m, isNotNull, reason: 'c_window not found in the migration');
    expect(kDmEditWindow, Duration(minutes: int.parse(m!.group(1)!)));
  });

  test('the sender can edit a live message inside the window', () {
    expect(canEditDm(_msg(), _me, _at(0)), isTrue);
    expect(canEditDm(_msg(), _me, _at(14)), isTrue);
    expect(canEditDm(_msg(), _me, _at(15)), isTrue);
  });

  test('not past the window', () {
    expect(
        canEditDm(_msg(), _me, _at(15).add(const Duration(milliseconds: 1))),
        isFalse);
    expect(canEditDm(_msg(), _me, _at(60)), isFalse);
  });

  test('a created_at ahead of the local clock counts as just sent', () {
    expect(canEditDm(_msg(), _me, _at(-2)), isTrue);
  });

  test("not someone else's message, and not with no viewer", () {
    expect(canEditDm(_msg(sender: 'them'), _me, _at(1)), isFalse);
    expect(canEditDm(_msg(), null, _at(1)), isFalse);
    expect(canEditDm(_msg(), null, _at(2)), isFalse);
  });

  test('not an unsent message', () {
    expect(canEditDm(_msg(unsentAt: _sent, body: null), _me, _at(1)), isFalse);
    expect(canEditDm(_msg(body: null), _me, _at(1)), isFalse);
  });

  test('not a message with an unreadable timestamp', () {
    // Dart's createdAt is a parsed DateTime, so an unreadable timestamp fails
    // in DirectMessageRow.fromJson before it reaches canEditDm.
    expect(
      () => DirectMessageRow.fromJson({
        'id': 'm-1',
        'conversation_id': 'c-1',
        'sender_id': _me,
        'created_at': 'not a date',
      }),
      throwsA(anything),
    );
  });
}
