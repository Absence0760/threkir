import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	LISTS_BY_TABLE,
	SNAPSHOT_LISTS,
	isListStale,
	listToken,
	markListsStale,
} from './list_freshness';

// The tests share one module instance, so the server-side case runs first,
// before `window` is defined for the rest.
test('markListsStale is a no-op without a window, so a server process accumulates nothing', () => {
	assert.equal(typeof (globalThis as { window?: unknown }).window, 'undefined');
	const before = SNAPSHOT_LISTS.map((l) => listToken(l));
	markListsStale(...SNAPSHOT_LISTS);
	assert.deepEqual(
		SNAPSHOT_LISTS.map((l) => listToken(l)),
		before,
	);
});

test('a token noted before a write reads as stale after it, and only for the lists the write named', () => {
	(globalThis as { window?: unknown }).window = {};
	try {
		const runs = listToken('runs');
		const plans = listToken('plans');
		assert.equal(isListStale('runs', runs), false);

		markListsStale('runs', 'history');

		assert.equal(isListStale('runs', runs), true);
		assert.equal(isListStale('plans', plans), false, 'a run write must not cost /plans its snapshot');
		assert.equal(isListStale('runs', listToken('runs')), false, 'a load after the write is current');
	} finally {
		delete (globalThis as { window?: unknown }).window;
	}
});

test('a snapshot without a token, or with an empty one, is stale', () => {
	// Snapshots live in sessionStorage, so one captured before the token
	// existed restores with the field missing; a page that never finished a
	// load captures ''.
	for (const list of SNAPSHOT_LISTS) {
		assert.equal(isListStale(list, undefined), true);
		assert.equal(isListStale(list, ''), true);
	}
});

test('a token from another page load (another epoch) is stale even at the same count', () => {
	const [, count] = listToken('routes').split(':');
	assert.equal(isListStale('routes', `someotherepoch:${count}`), true);
});

test('every list a table maps to is a snapshotted list, and each list is reachable from a table', () => {
	const reached = new Set<string>();
	for (const lists of Object.values(LISTS_BY_TABLE)) {
		for (const list of lists) {
			assert.ok((SNAPSHOT_LISTS as readonly string[]).includes(list), list);
			reached.add(list);
		}
	}
	assert.deepEqual([...reached].sort(), [...SNAPSHOT_LISTS].sort());
});

test('a run shows on /runs and the /history timeline, and moves the /routes run_count', () => {
	assert.deepEqual([...LISTS_BY_TABLE.runs].sort(), ['history', 'routes', 'runs']);
	assert.deepEqual([...LISTS_BY_TABLE.gym_workouts], ['history']);
	assert.deepEqual([...LISTS_BY_TABLE.food_log], ['history']);
	assert.deepEqual([...LISTS_BY_TABLE.training_plans], ['plans']);
	assert.deepEqual([...LISTS_BY_TABLE.routes], ['routes']);
});
