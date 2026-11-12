import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	HEAD_TO_HEAD_KINDS,
	formatHeadToHeadTime,
	headToHeadName,
	headToHeadOutcome,
	parseHeadToHeadRows,
} from './head_to_head';

const row = (over: Record<string, unknown> = {}) => ({
	friend_id: 'f1',
	friend_display_name: 'Sam',
	friend_handle: 'sam',
	friend_avatar_url: null,
	target_name: 'River Loop',
	my_run_id: 'r1',
	my_seconds: 1900,
	my_started_at: '2026-10-01T07:00:00Z',
	friend_run_id: 'r2',
	friend_seconds: 1950,
	friend_started_at: '2026-10-02T07:00:00Z',
	...over,
});

test('the three kinds the RPC takes', () => {
	assert.deepEqual([...HEAD_TO_HEAD_KINDS], ['route', 'segment', 'global_segment']);
});

test('a full row parses into both sides', () => {
	assert.deepEqual(parseHeadToHeadRows([row()]), [
		{
			friendId: 'f1',
			friendDisplayName: 'Sam',
			friendHandle: 'sam',
			friendAvatarUrl: null,
			targetName: 'River Loop',
			myRunId: 'r1',
			mySeconds: 1900,
			friendRunId: 'r2',
			friendSeconds: 1950,
		},
	]);
});

test('a row missing a side or a time is dropped', () => {
	const bad = [
		row({ friend_id: null }),
		row({ my_run_id: '' }),
		row({ friend_seconds: 0 }),
		row({ my_seconds: Number.NaN }),
		row({ target_name: '  ' }),
		null,
		'x',
	];
	assert.deepEqual(parseHeadToHeadRows(bad), []);
});

test('anything that is not a list parses to nothing', () => {
	assert.deepEqual(parseHeadToHeadRows(null), []);
	assert.deepEqual(parseHeadToHeadRows({}), []);
});

test('blank optional names come back null', () => {
	const [r] = parseHeadToHeadRows([row({ friend_handle: ' ', friend_display_name: '' })]);
	assert.equal(r.friendHandle, null);
	assert.equal(r.friendDisplayName, null);
});

test('the lower time wins, by the whole-second gap', () => {
	assert.deepEqual(headToHeadOutcome(1900, 1950), { winner: 'me', marginSeconds: 50 });
	assert.deepEqual(headToHeadOutcome(2000, 1950), { winner: 'friend', marginSeconds: 50 });
});

test('times that round to the same second are a tie', () => {
	assert.deepEqual(headToHeadOutcome(100.4, 99.6), { winner: 'tie', marginSeconds: 0 });
	assert.deepEqual(headToHeadOutcome(60, 60), { winner: 'tie', marginSeconds: 0 });
});

test('a time under an hour prints m:ss', () => {
	assert.equal(formatHeadToHeadTime(0), '0:00');
	assert.equal(formatHeadToHeadTime(59.6), '1:00');
	assert.equal(formatHeadToHeadTime(1950), '32:30');
});

test('an hour or more prints h:mm:ss', () => {
	assert.equal(formatHeadToHeadTime(3600), '1:00:00');
	assert.equal(formatHeadToHeadTime(3725), '1:02:05');
});

test('a negative or non-finite time prints 0:00', () => {
	assert.equal(formatHeadToHeadTime(-5), '0:00');
	assert.equal(formatHeadToHeadTime(Number.POSITIVE_INFINITY), '0:00');
});

test('a handle wins over the display name', () => {
	assert.equal(headToHeadName('sam', 'Sam Smith'), '@sam');
	assert.equal(headToHeadName(' sam ', null), '@sam');
});

test('with no handle the display name, else null', () => {
	assert.equal(headToHeadName(null, ' Sam Smith '), 'Sam Smith');
	assert.equal(headToHeadName('', ''), null);
	assert.equal(headToHeadName(undefined, undefined), null);
});
