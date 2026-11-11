import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	GROUP_MAX_MEMBERS,
	canChangeGroupRoles,
	canManageGroup,
	canRemoveGroupMember,
	groupIdFromRouteId,
	groupSeatsLeft,
	mergeGroupThread,
	normalizeGroupTitle,
	parseGroupRole,
	placeholdersSince,
	sortGroupMembers,
	type GroupMemberState,
} from './group_messages.ts';
import { dmThreadRouteId } from './dm_thread.ts';

test('a title is trimmed and must be 1 to 60 characters, counted in code points', () => {
	assert.equal(normalizeGroupTitle('  Tuesday tempo  '), 'Tuesday tempo');
	assert.equal(normalizeGroupTitle('   '), null);
	assert.equal(normalizeGroupTitle('x'.repeat(60)), 'x'.repeat(60));
	assert.equal(normalizeGroupTitle('x'.repeat(61)), null);
	// 60 emoji are 120 UTF-16 units and still 60 characters to Postgres.
	assert.equal(normalizeGroupTitle('🏃'.repeat(60)), '🏃'.repeat(60));
	assert.equal(normalizeGroupTitle('🏃'.repeat(61)), null);
});

test('seats count members and live invites against the cap of 32', () => {
	assert.equal(GROUP_MAX_MEMBERS, 32);
	assert.equal(groupSeatsLeft(1, 0), 31, 'the creator takes a seat');
	assert.equal(groupSeatsLeft(10, 5), 17);
	assert.equal(groupSeatsLeft(30, 5), 0, 'never below zero');
});

test('roles read at the boundary', () => {
	assert.equal(parseGroupRole('owner'), 'owner');
	assert.equal(parseGroupRole('admin'), 'admin');
	assert.equal(parseGroupRole('member'), 'member');
	assert.equal(parseGroupRole('moderator'), null);
	assert.equal(parseGroupRole(null), null);
});

test('owner and admins manage; only the owner changes roles', () => {
	assert.equal(canManageGroup('owner'), true);
	assert.equal(canManageGroup('admin'), true);
	assert.equal(canManageGroup('member'), false);
	assert.equal(canManageGroup(null), false);
	assert.equal(canChangeGroupRoles('owner'), true);
	assert.equal(canChangeGroupRoles('admin'), false);
});

test('removal follows remove_group_member: below your own rank, never yourself or the owner', () => {
	const m = (userId: string, role: GroupMemberState['role'], state: GroupMemberState['state'] = 'active') => ({
		userId,
		role,
		state,
	});
	assert.equal(canRemoveGroupMember('owner', 'o', m('a', 'admin')), true);
	assert.equal(canRemoveGroupMember('owner', 'o', m('b', 'member')), true);
	assert.equal(canRemoveGroupMember('admin', 'a', m('b', 'member')), true);
	assert.equal(canRemoveGroupMember('admin', 'a', m('a2', 'admin')), false, 'not a peer');
	assert.equal(canRemoveGroupMember('admin', 'a', m('o', 'owner')), false, 'not the owner');
	assert.equal(canRemoveGroupMember('member', 'b', m('c', 'member')), false, 'a member removes nobody');
	assert.equal(canRemoveGroupMember('owner', 'o', m('o', 'owner')), false, 'not yourself');
	assert.equal(canRemoveGroupMember('admin', 'a', m('i', null, 'invited')), true, 'an admin cancels an invite');
	assert.equal(canRemoveGroupMember('member', 'b', m('i', null, 'invited')), false);
	assert.equal(canRemoveGroupMember('owner', null, m('b', 'member')), false, 'signed out');
});

test('the roster sorts owner, admins, members, then invites, by folded name with unnamed last', () => {
	const rows = [
		{ userId: 'i1', role: null, state: 'invited' as const, name: 'Aaron' },
		{ userId: 'm2', role: 'member' as const, state: 'active' as const, name: null },
		{ userId: 'm1', role: 'member' as const, state: 'active' as const, name: 'Zoë' },
		{ userId: 'm3', role: 'member' as const, state: 'active' as const, name: 'zoe' },
		{ userId: 'a1', role: 'admin' as const, state: 'active' as const, name: 'Bea' },
		{ userId: 'o1', role: 'owner' as const, state: 'active' as const, name: 'Yan' },
	];
	assert.deepEqual(
		sortGroupMembers(rows).map((r) => r.userId),
		['o1', 'a1', 'm1', 'm3', 'm2', 'i1'],
	);
});

test('the thread interleaves blocked placeholders by time and drops one whose message is shown', () => {
	const msgs = [
		{ id: 'b', created_at: '2026-11-10T10:00:02.000002Z' },
		{ id: 'd', created_at: '2026-11-10T10:00:04Z' },
	];
	const holes = [
		{ id: 'a', created_at: '2026-11-10T10:00:01Z' },
		{ id: 'c', created_at: '2026-11-10T10:00:02.000003Z' },
		{ id: 'd', created_at: '2026-11-10T10:00:04Z' },
	];
	const items = mergeGroupThread(msgs, holes);
	assert.deepEqual(
		items.map((i) => (i.kind === 'message' ? `m:${i.message.id}` : `x:${i.id}`)),
		['x:a', 'm:b', 'x:c', 'm:d'],
	);
});

test('placeholders are bounded to the loaded window only while older messages exist', () => {
	const msgs = [
		{ id: 'a', created_at: '2026-11-10T10:00:00Z' },
		{ id: 'b', created_at: '2026-11-10T10:05:00Z' },
	];
	assert.equal(placeholdersSince(msgs, true), '2026-11-10T10:00:00Z');
	assert.equal(placeholdersSince(msgs, false), null);
	assert.equal(placeholdersSince([], true), null);
});

test('a group thread has its own route, and the route names it back', () => {
	const route = dmThreadRouteId({ partnerId: null, deletedPartnerKey: null, conversationId: 'g1', kind: 'group' });
	assert.equal(route, 'group/g1');
	assert.equal(groupIdFromRouteId(route), 'g1');
	assert.equal(
		dmThreadRouteId({ partnerId: null, deletedPartnerKey: null, conversationId: 'g2', isGroup: true }),
		'group/g2',
		'a search hit in a group opens the group',
	);
	assert.equal(groupIdFromRouteId('p1'), null);
	assert.equal(groupIdFromRouteId('group/'), null);
	assert.equal(groupIdFromRouteId(null), null);
	assert.equal(
		dmThreadRouteId({ partnerId: 'p1', deletedPartnerKey: null, conversationId: 'c1', kind: 'direct' }),
		'p1',
		'a direct conversation keeps its partner route',
	);
});
