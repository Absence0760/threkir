// ignore_for_file: avoid_relative_lib_imports
import 'package:api_client/api_client.dart' show GroupMember;
import 'package:core_models/core_models.dart' show DirectMessageRow;
import 'package:flutter_test/flutter_test.dart';

import '../lib/group_messages.dart';

DirectMessageRow _m(String id, DateTime at) => DirectMessageRow(
      kind: 'text',
      isGroup: true,
      id: id,
      conversationId: 'g',
      senderId: 's',
      body: id,
      createdAt: at,
    );

GroupMember _member(String userId, String? role,
        {String state = 'active', String? name}) =>
    GroupMember(userId: userId, role: role, state: state, name: name);

void main() {
  test('a title is trimmed and must be 1 to 60 characters, counted in code points', () {
    expect(normalizeGroupTitle('  Tuesday tempo  '), 'Tuesday tempo');
    expect(normalizeGroupTitle('   '), isNull);
    expect(normalizeGroupTitle('x' * 60), 'x' * 60);
    expect(normalizeGroupTitle('x' * 61), isNull);
    // 60 emoji are 120 UTF-16 units and still 60 characters to Postgres.
    expect(normalizeGroupTitle('🏃' * 60), '🏃' * 60);
    expect(normalizeGroupTitle('🏃' * 61), isNull);
  });

  test('seats count members and live invites against the cap of 32', () {
    expect(kGroupMaxMembers, 32);
    expect(groupSeatsLeft(1, 0), 31, reason: 'the creator takes a seat');
    expect(groupSeatsLeft(10, 5), 17);
    expect(groupSeatsLeft(30, 5), 0, reason: 'never below zero');
  });

  test('roles read at the boundary', () {
    expect(parseGroupRole('owner'), 'owner');
    expect(parseGroupRole('admin'), 'admin');
    expect(parseGroupRole('member'), 'member');
    expect(parseGroupRole('moderator'), isNull);
    expect(parseGroupRole(null), isNull);
  });

  test('owner and admins manage; only the owner changes roles', () {
    expect(canManageGroup('owner'), isTrue);
    expect(canManageGroup('admin'), isTrue);
    expect(canManageGroup('member'), isFalse);
    expect(canManageGroup(null), isFalse);
    expect(canChangeGroupRoles('owner'), isTrue);
    expect(canChangeGroupRoles('admin'), isFalse);
  });

  test('removal follows remove_group_member: below your own rank, never yourself or the owner', () {
    expect(canRemoveGroupMember('owner', 'o', _member('a', 'admin')), isTrue);
    expect(canRemoveGroupMember('owner', 'o', _member('b', 'member')), isTrue);
    expect(canRemoveGroupMember('admin', 'a', _member('b', 'member')), isTrue);
    expect(canRemoveGroupMember('admin', 'a', _member('a2', 'admin')), isFalse,
        reason: 'not a peer');
    expect(canRemoveGroupMember('admin', 'a', _member('o', 'owner')), isFalse,
        reason: 'not the owner');
    expect(canRemoveGroupMember('member', 'b', _member('c', 'member')), isFalse,
        reason: 'a member removes nobody');
    expect(canRemoveGroupMember('owner', 'o', _member('o', 'owner')), isFalse,
        reason: 'not yourself');
    expect(
        canRemoveGroupMember(
            'admin', 'a', _member('i', null, state: 'invited')),
        isTrue,
        reason: 'an admin cancels an invite');
    expect(
        canRemoveGroupMember(
            'member', 'b', _member('i', null, state: 'invited')),
        isFalse);
    expect(canRemoveGroupMember('owner', null, _member('b', 'member')), isFalse,
        reason: 'signed out');
  });

  test('the roster sorts owner, admins, members, then invites, by folded name with unnamed last', () {
    final rows = [
      _member('i1', null, state: 'invited', name: 'Aaron'),
      _member('m2', 'member'),
      _member('m1', 'member', name: 'Zoë'),
      _member('m3', 'member', name: 'zoe'),
      _member('a1', 'admin', name: 'Bea'),
      _member('o1', 'owner', name: 'Yan'),
    ];
    expect(
      sortGroupMembers(rows).map((r) => r.userId).toList(),
      ['o1', 'a1', 'm1', 'm3', 'm2', 'i1'],
    );
  });

  test('the thread interleaves blocked placeholders by time and drops one whose message is shown', () {
    final msgs = [
      _m('b', DateTime.parse('2026-11-10T10:00:02.000002Z')),
      _m('d', DateTime.parse('2026-11-10T10:00:04Z')),
    ];
    final holes = [
      (id: 'a', createdAt: DateTime.parse('2026-11-10T10:00:01Z')),
      (id: 'c', createdAt: DateTime.parse('2026-11-10T10:00:02.000003Z')),
      (id: 'd', createdAt: DateTime.parse('2026-11-10T10:00:04Z')),
    ];
    final items = mergeGroupThread(msgs, holes);
    expect(
      [
        for (final i in items)
          switch (i) {
            GroupMessageItem(:final message) => 'm:${message.id}',
            GroupBlockedItem(:final id) => 'x:$id',
          },
      ],
      ['x:a', 'm:b', 'x:c', 'm:d'],
    );
  });

  test('placeholders are bounded to the loaded window only while older messages exist', () {
    final msgs = [
      _m('a', DateTime.parse('2026-11-10T10:00:00Z')),
      _m('b', DateTime.parse('2026-11-10T10:05:00Z')),
    ];
    expect(placeholdersSince(msgs, true), DateTime.parse('2026-11-10T10:00:00Z'));
    expect(placeholdersSince(msgs, false), isNull);
    expect(placeholdersSince(const [], true), isNull);
  });
}
