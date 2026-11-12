import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { JsonObject } from '../types';
import {
	keepKnownColumns,
	PROFILE_RESTORE_COLUMNS,
	ROUTE_RESTORE_COLUMNS,
	RUN_RESTORE_COLUMNS,
} from './restore_columns';

test('an archived run carrying the dropped runs.kind keeps every other column', () => {
	const archived: JsonObject = {
		id: 'r1',
		user_id: 'u1',
		kind: 'run',
		distance_m: 5000,
		duration_s: 1500,
		started_at: '2026-01-01T07:00:00Z',
	};
	const { row, dropped } = keepKnownColumns(archived, RUN_RESTORE_COLUMNS);
	assert.deepEqual(dropped, ['kind']);
	assert.deepEqual(row, {
		id: 'r1',
		user_id: 'u1',
		distance_m: 5000,
		duration_s: 1500,
		started_at: '2026-01-01T07:00:00Z',
	});
});

test('prototype-chain names in a user-supplied archive are dropped, not admitted as columns', () => {
	const archived = JSON.parse(
		'{"id":"r1","__proto__":{"polluted":true},"constructor":"x","toString":"y","hasOwnProperty":"z"}',
	) as JsonObject;
	const { row, dropped } = keepKnownColumns(archived, RUN_RESTORE_COLUMNS);
	assert.deepEqual(row, { id: 'r1' });
	assert.deepEqual(
		[...dropped].sort(),
		['__proto__', 'constructor', 'hasOwnProperty', 'toString'],
	);
	assert.equal(Object.getPrototypeOf(row), Object.prototype);
	assert.equal((row as Record<string, unknown>).polluted, undefined);
	assert.equal(({} as Record<string, unknown>).polluted, undefined);
});

test('null and falsy values on known columns survive, since they are real data', () => {
	const archived: JsonObject = {
		id: 'r1',
		route_id: null,
		is_public: false,
		elevation_gain_m: 0,
		external_id: '',
	};
	const { row, dropped } = keepKnownColumns(archived, RUN_RESTORE_COLUMNS);
	assert.deepEqual(dropped, []);
	assert.deepEqual(row, archived);
	assert.ok(Object.hasOwn(row, 'route_id'));
});

test("one table's column set does not admit another table's columns", () => {
	const archived: JsonObject = {
		id: 'x1',
		name: 'Loop',
		geom: 'LINESTRING(0 0,1 1)',
		distance_m: 5000,
	};
	const asRun = keepKnownColumns(archived, RUN_RESTORE_COLUMNS);
	assert.deepEqual(asRun.dropped, ['name', 'geom']);
	const asRoute = keepKnownColumns(archived, ROUTE_RESTORE_COLUMNS);
	assert.deepEqual(asRoute.dropped, []);
	const asProfile = keepKnownColumns(archived, PROFILE_RESTORE_COLUMNS);
	assert.deepEqual(asProfile.dropped, ['name', 'geom', 'distance_m']);
});

test('a row naming every known column round-trips intact, in input order, without mutating the input', () => {
	const archived: JsonObject = {};
	for (const key of Object.keys(PROFILE_RESTORE_COLUMNS)) archived[key] = `v:${key}`;
	archived.legacy_field = 'gone';
	const before = JSON.stringify(archived);
	const { row, dropped } = keepKnownColumns(archived, PROFILE_RESTORE_COLUMNS);
	assert.deepEqual(dropped, ['legacy_field']);
	assert.deepEqual(Object.keys(row), Object.keys(PROFILE_RESTORE_COLUMNS));
	assert.equal(JSON.stringify(archived), before);
	assert.notEqual(row, archived);
});
