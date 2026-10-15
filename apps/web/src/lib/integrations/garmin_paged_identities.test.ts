// Walked identity collection for the cross-provider dedupe guard. Pre-fix the
// guard did a bare `.select().eq('user_id', uid)` which PostgREST silently
// caps at 1000 rows — so a pro with 1000+ runs compared against an arbitrary
// slice and re-imported duplicates anyway. Then it paged with `.range()`,
// whose OFFSET drops a row at a page boundary when a sync lands mid-import.
// `collectRunIdentities` now walks by keyset cursor (`walkKeyset`, whose
// paging is pinned in core/keyset_page.test.ts). These pin the collector.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { KEYSET_WALK_PAGE_SIZE } from '../core/keyset_page';
import { collectRunIdentities, RUN_DEDUPE_ORDER, type RawRunRow } from './garmin_dedupe';

/// A fake keyset source of `count` runs, newest first, one second apart. It
/// answers the cursor filter `walkKeyset` sends by locating the row the
/// cursor names (ids are unique and the rows are already in walk order).
function keysetSource(count: number) {
	const rows: RawRunRow[] = Array.from({ length: count }, (_, i) => ({
		id: `r-${String(count - i).padStart(5, '0')}`,
		started_at: new Date(Date.UTC(2026, 0, 1, 0, 0, count - i)).toISOString(),
		distance_m: 5000 + i,
	}));
	const calls: Array<{ after: string | null; limit: number }> = [];
	const fetchPage = async (after: string | null, limit: number) => {
		calls.push({ after, limit });
		let from = 0;
		if (after !== null) {
			const id = /id\.lt\."([^"]+)"/.exec(after)?.[1];
			from = rows.findIndex((r) => r.id === id) + 1;
			assert.ok(from > 0, `cursor names no row: ${after}`);
		}
		return { data: rows.slice(from, from + limit), error: null };
	};
	return { fetchPage, calls };
}

test('collectRunIdentities — 1200 runs are ALL collected (not capped at 1000)', async () => {
	const { fetchPage, calls } = keysetSource(1200);
	const ids = await collectRunIdentities(fetchPage);
	assert.equal(ids.length, 1200, 'every run must be compared, not just the first 1000');
	assert.equal(calls[0].after, null);
	assert.match(calls[1].after ?? '', /started_at\.lt\./, 'page 2 starts after the last row of page 1');
});

test('collectRunIdentities — walks newest first with the id tie-break', () => {
	assert.deepEqual(
		RUN_DEDUPE_ORDER.map((k) => `${k.column} ${k.ascending ? 'asc' : 'desc'}`),
		['started_at desc', 'id desc'],
	);
});

test('collectRunIdentities — a page error ends the walk without throwing', async () => {
	let call = 0;
	const ids = await collectRunIdentities(async () => {
		call++;
		return call === 1
			? { data: [{ id: 'a', started_at: '2026-01-01T09:00:00Z', distance_m: 5000 }], error: null }
			: { data: null, error: new Error('reset') };
	}, 1);
	assert.equal(ids.length, 1);
});

test('collectRunIdentities — non-finite start times are dropped', async () => {
	let served = false;
	const ids = await collectRunIdentities(async () => {
		if (served) return { data: [], error: null };
		served = true;
		return {
			data: [
				{ id: 'a', started_at: 'not-a-date', distance_m: 5000 },
				{ id: 'b', started_at: null, distance_m: 5000 },
				{ id: 'c', started_at: '2026-01-01T09:00:00Z', distance_m: 5000 },
			],
			error: null,
		};
	});
	assert.equal(ids.length, 1);
	assert.equal(ids[0].distanceM, 5000);
});

test('the walk asks for the PostgREST cap per page', async () => {
	const { fetchPage, calls } = keysetSource(3);
	await collectRunIdentities(fetchPage);
	assert.equal(calls[0].limit, KEYSET_WALK_PAGE_SIZE);
	assert.equal(KEYSET_WALK_PAGE_SIZE, 1000);
});
