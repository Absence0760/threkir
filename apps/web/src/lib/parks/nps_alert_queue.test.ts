// Invocation: npx tsx --test src/lib/parks/nps_alert_queue.test.ts

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { orderNpsAlertQueue } from './nps_alert_queue.ts';

const row = (id: number, first_seen_at: string, gone_at: string | null = null) => ({ id, first_seen_at, gone_at });

test('current flags come first, oldest first, and gone ones last', () => {
	const ordered = orderNpsAlertQueue([
		row(1, '2026-11-01T10:00:00+00:00', '2026-11-05T10:00:00+00:00'),
		row(2, '2026-11-03T10:00:00+00:00'),
		row(3, '2026-11-02T10:00:00+00:00'),
		row(4, '2026-10-01T10:00:00+00:00', '2026-11-06T10:00:00+00:00'),
	]);
	assert.deepEqual(ordered.map((r) => r.id), [3, 2, 4, 1]);
});

test('timestamps are compared as instants, not as text', () => {
	// 12:00+05:00 is 07:00 UTC, the earliest of the three, and last as text.
	const ordered = orderNpsAlertQueue([
		row(1, '2026-11-01T10:00:00.5+00:00'),
		row(2, '2026-11-01T10:00:00.123456+00:00'),
		row(3, '2026-11-01T12:00:00+05:00'),
	]);
	assert.deepEqual(ordered.map((r) => r.id), [3, 2, 1]);
});

test('id breaks a tie on the same instant', () => {
	const ordered = orderNpsAlertQueue([row(9, '2026-11-01T10:00:00+00:00'), row(4, '2026-11-01T10:00:00+00:00')]);
	assert.deepEqual(ordered.map((r) => r.id), [4, 9]);
});

test('the input is left as it was', () => {
	const input = [row(2, '2026-11-02T10:00:00+00:00'), row(1, '2026-11-01T10:00:00+00:00')];
	orderNpsAlertQueue(input);
	assert.deepEqual(input.map((r) => r.id), [2, 1]);
});
