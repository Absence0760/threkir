import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	DM_INBOX_POLL_MS,
	DM_THREAD_PAGE_SIZE,
	DM_THREAD_POLL_MS,
	compareDmOrder,
	dmPageBeforeFilter,
	dmPageFromRows,
	dmThreadRouteId,
	mergeDmMessages,
	mergeDmPollPage,
	parseDmThreadRouteId
} from './dm_thread';

const msg = (id: string, created_at: string, body = id) => ({ id, created_at, body });

test('the page size matches mobile', () => {
	assert.equal(DM_THREAD_PAGE_SIZE, 50);
});

test('order is created_at first, then id', () => {
	const a = msg('b', '2026-10-14T08:01:00+00:00');
	const b = msg('a', '2026-10-14T08:02:00+00:00');
	assert.ok(compareDmOrder(a, b) < 0);
	const c = msg('a', '2026-10-14T08:02:00+00:00');
	const d = msg('b', '2026-10-14T08:02:00+00:00');
	assert.ok(compareDmOrder(c, d) < 0);
	assert.equal(compareDmOrder(c, c), 0);
});

test('two messages in the same millisecond are ordered by their microseconds', () => {
	const early = msg('z', '2026-10-14T08:05:00.123456+00:00');
	const late = msg('a', '2026-10-14T08:05:00.1239+00:00');
	assert.ok(compareDmOrder(early, late) < 0);
	assert.ok(compareDmOrder(late, early) > 0);
});

test('a trimmed fraction and a full one compare as the same instant', () => {
	const short = msg('a', '2026-10-14T08:05:00.12+00:00');
	const long = msg('b', '2026-10-14T08:05:00.120000+00:00');
	assert.ok(compareDmOrder(short, long) < 0, 'tie on time falls through to id');
	const whole = msg('a', '2026-10-14T08:05:00+00:00');
	assert.ok(compareDmOrder(whole, short) < 0);
});

test('the older-page filter is keyed on the oldest message shown, ties by id', () => {
	assert.equal(
		dmPageBeforeFilter(msg('m-5', '2026-10-14T08:05:00.123456+00:00')),
		'created_at.lt."2026-10-14T08:05:00.123456+00:00",' +
			'and(created_at.eq."2026-10-14T08:05:00.123456+00:00",id.lt."m-5")'
	);
});

test('a read with one row past the limit has more, drops the probe, renders oldest first', () => {
	const rows = [
		msg('m-3', '2026-10-14T08:03:00+00:00'),
		msg('m-2', '2026-10-14T08:02:00+00:00'),
		msg('m-1', '2026-10-14T08:01:00+00:00')
	];
	const page = dmPageFromRows(rows, 2);
	assert.equal(page.hasMore, true);
	assert.deepEqual(
		page.messages.map((m) => m.id),
		['m-2', 'm-3']
	);
	assert.deepEqual(
		rows.map((m) => m.id),
		['m-3', 'm-2', 'm-1'],
		'the caller’s rows are not reversed in place'
	);
});

test('a read at or under the limit is the whole rest of the thread', () => {
	const rows = [msg('m-2', '2026-10-14T08:02:00+00:00'), msg('m-1', '2026-10-14T08:01:00+00:00')];
	const page = dmPageFromRows(rows, 2);
	assert.equal(page.hasMore, false);
	assert.deepEqual(
		page.messages.map((m) => m.id),
		['m-1', 'm-2']
	);
	assert.deepEqual(dmPageFromRows([], 2), { messages: [], hasMore: false });
});

test('an earlier page merges in front, without duplicating an id both pages hold', () => {
	const shown = [msg('m-3', '2026-10-14T08:03:00+00:00'), msg('m-4', '2026-10-14T08:04:00+00:00')];
	const earlier = [msg('m-1', '2026-10-14T08:01:00+00:00'), msg('m-3', '2026-10-14T08:03:00+00:00')];
	assert.deepEqual(
		mergeDmMessages(shown, earlier).map((m) => m.id),
		['m-1', 'm-3', 'm-4']
	);
});

test('a sent message merges into place and a later copy of an id wins', () => {
	const shown = [msg('m-1', '2026-10-14T08:01:00+00:00')];
	const sent = msg('m-2', '2026-10-14T08:02:00+00:00');
	assert.deepEqual(
		mergeDmMessages(shown, [sent]).map((m) => m.id),
		['m-1', 'm-2']
	);
	const edited = msg('m-1', '2026-10-14T08:01:00+00:00', 'newer copy');
	assert.equal(mergeDmMessages(shown, [edited])[0].body, 'newer copy');
});

test('a partner thread routes by the partner id', () => {
	const partnerId = '11111111-1111-1111-1111-111111111111';
	const id = dmThreadRouteId({ partnerId, deletedPartnerKey: null });
	assert.equal(id, partnerId);
	assert.deepEqual(parseDmThreadRouteId(id), { kind: 'partner', partnerId });
});

test('a deleted partner routes by its key and parses back to it', () => {
	const key = '22222222-2222-2222-2222-222222222222';
	const id = dmThreadRouteId({ partnerId: null, deletedPartnerKey: key });
	assert.equal(id, `deleted-${key}`);
	assert.deepEqual(parseDmThreadRouteId(id), { kind: 'deleted', deletedPartnerKey: key });
});

test('a thread with neither a partner nor a key has no route', () => {
	assert.throws(() => dmThreadRouteId({ partnerId: null, deletedPartnerKey: null }));
});

test('the poll cadences match mobile', () => {
	assert.equal(DM_THREAD_POLL_MS, 10_000);
	assert.equal(DM_INBOX_POLL_MS, 30_000);
});

test('a poll page that overlaps the screen is merged without duplicating a row', () => {
	const shown = [msg('a', '2026-10-14T08:00:00Z'), msg('b', '2026-10-14T08:01:00Z')];
	const page = {
		messages: [msg('b', '2026-10-14T08:01:00Z', 'b edited'), msg('c', '2026-10-14T08:02:00Z')],
		hasMore: true
	};
	const out = mergeDmPollPage(shown, page, false);
	assert.deepEqual(
		out.messages.map((m) => m.id),
		['a', 'b', 'c']
	);
	assert.equal(out.messages[1].body, 'b edited', 'the fresh copy replaces the shown one');
	assert.equal(out.hasMore, false, 'an overlapping page leaves "load earlier" as it was');
	assert.equal(out.gap, false);
});

test('a poll page that does not reach the newest shown message replaces the list', () => {
	const shown = [msg('a', '2026-10-14T08:00:00Z'), msg('b', '2026-10-14T08:01:00Z')];
	const page = {
		messages: [msg('x', '2026-10-14T09:00:00Z'), msg('y', '2026-10-14T09:01:00Z')],
		hasMore: true
	};
	const out = mergeDmPollPage(shown, page, false);
	assert.deepEqual(
		out.messages.map((m) => m.id),
		['x', 'y']
	);
	assert.equal(out.hasMore, true);
	assert.equal(out.gap, true);
});

test('a page older than the newest shown message is merged, not a gap', () => {
	const shown = [msg('a', '2026-10-14T08:00:00Z'), msg('z', '2026-10-14T10:00:00Z')];
	const page = {
		messages: [msg('x', '2026-10-14T09:00:00Z'), msg('y', '2026-10-14T09:01:00Z')],
		hasMore: true
	};
	const out = mergeDmPollPage(shown, page, false);
	assert.equal(out.gap, false);
	assert.deepEqual(
		out.messages.map((m) => m.id),
		['a', 'x', 'y', 'z']
	);
});

test('a complete page never reads as a gap', () => {
	const shown = [msg('a', '2026-10-14T08:00:00Z')];
	const page = { messages: [msg('x', '2026-10-14T09:00:00Z')], hasMore: false };
	const out = mergeDmPollPage(shown, page, false);
	assert.deepEqual(
		out.messages.map((m) => m.id),
		['a', 'x']
	);
	assert.equal(out.gap, false);
});

test('a poll into an empty conversation takes the page and its hasMore', () => {
	const page = { messages: [msg('x', '2026-10-14T09:00:00Z')], hasMore: true };
	const out = mergeDmPollPage([], page, false);
	assert.deepEqual(
		out.messages.map((m) => m.id),
		['x']
	);
	assert.equal(out.hasMore, true);
	assert.equal(out.gap, false);
});
