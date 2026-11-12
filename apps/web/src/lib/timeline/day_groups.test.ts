import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { groupByLocalDay } from './day_groups';

// Local-zone constructors throughout: the helper groups by the viewer's local
// day, so the fixtures are built in the same zone whatever the runner's TZ.
const at = (d: number, h: number, min = 0) => new Date(2026, 9, d, h, min).toISOString();
const now = new Date(2026, 9, 18, 12, 0);
const iso = (r: { at: string }) => r.at;

test('rows on one local day share a group, newest-first order kept', () => {
	const rows = [{ at: at(18, 9) }, { at: at(18, 7) }, { at: at(16, 6) }];
	const groups = groupByLocalDay(rows, iso, now);
	assert.equal(groups.length, 2);
	assert.deepEqual(groups[0].rows, rows.slice(0, 2));
	assert.deepEqual(groups[1].rows, rows.slice(2));
});

test('today and yesterday are flagged; older days are not', () => {
	const groups = groupByLocalDay([{ at: at(18, 1) }, { at: at(17, 23) }, { at: at(15, 8) }], iso, now);
	assert.deepEqual(
		groups.map((g) => g.relative),
		['today', 'yesterday', null],
	);
});

test('the boundary is local midnight, not a 24-hour window', () => {
	const groups = groupByLocalDay([{ at: at(18, 0, 5) }, { at: at(17, 23, 55) }], iso, now);
	assert.equal(groups.length, 2);
	assert.equal(groups[0].relative, 'today');
	assert.equal(groups[1].relative, 'yesterday');
});

test('a day that recurs out of order starts a new group with a distinct key', () => {
	const rows = [{ at: at(16, 9) }, { at: at(18, 9) }, { at: at(16, 7) }];
	const groups = groupByLocalDay(rows, iso, now);
	assert.equal(groups.length, 3);
	assert.equal(new Set(groups.map((g) => g.key)).size, 3);
	assert.equal(groups[0].key, '2026-10-16');
	assert.equal(groups[2].key, '2026-10-16#1');
});

test('each group carries its first row timestamp for the heading', () => {
	const rows = [{ at: at(14, 10) }, { at: at(14, 8) }];
	const [g] = groupByLocalDay(rows, iso, now);
	assert.equal(g.startedAt, rows[0].at);
	assert.equal(g.key, '2026-10-14');
});

test('no rows, no groups', () => {
	assert.deepEqual(groupByLocalDay([], iso, now), []);
});
