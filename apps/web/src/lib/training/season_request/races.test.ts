// Unit tests for the AI season-request trust boundary. Run via
// `npx tsx --test apps/web/src/lib/training/season_request/races.test.ts`.
//
// `validateSeasonRaces` is the only thing between the model's tool call and
// the race list the runner confirms, so every drop, clamp, default and
// assumption branch is pinned here.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	MAX_SEASON_RACES,
	MAX_SEASON_RACE_NAME_CHARS,
	SEASON_REQUEST_ASSUMPTIONS,
	validateSeasonRaces,
} from './races';

const TODAY = '2026-10-16';

const RICHMOND = { name: 'Richmond Marathon', date: '2026-11-14', distance_km: 42.195, priority: 'B' };
const TWO_OCEANS = { name: 'Two Oceans', date: '2027-04-04', distance_km: 56, priority: 'B' };
const COMRADES = { name: 'Comrades', date: '2027-06-13', distance_km: 89, priority: 'A', goal_time_sec: 10 * 3600 };

function v(races: unknown[]) {
	return validateSeasonRaces({ races }, TODAY);
}

test('a sane season passes through, sorted by date, with no assumptions', () => {
	assert.deepEqual(v([COMRADES, RICHMOND, TWO_OCEANS]), {
		races: [
			{ name: 'Richmond Marathon', date: '2026-11-14', distanceM: 42_195, priority: 'B', goalTimeSec: null },
			{ name: 'Two Oceans', date: '2027-04-04', distanceM: 56_000, priority: 'B', goalTimeSec: null },
			{ name: 'Comrades', date: '2027-06-13', distanceM: 89_000, priority: 'A', goalTimeSec: 36_000 },
		],
		assumptions: [],
	});
});

test('accepts the bare array as well as the tool input object', () => {
	assert.deepEqual(validateSeasonRaces([COMRADES], TODAY), v([COMRADES]));
});

test('a non-object, a missing races list or garbage yields an empty list', () => {
	for (const raw of [null, undefined, 42, 'races', {}, { races: 'x' }, { races: null }]) {
		assert.deepEqual(validateSeasonRaces(raw, TODAY), { races: [], assumptions: [] }, JSON.stringify(raw));
	}
});

// ───────────────────────── name ─────────────────────────

test('an entry that is not an object, or has no usable name, is dropped', () => {
	for (const bad of [null, 7, 'Comrades', [], { ...COMRADES, name: undefined }, { ...COMRADES, name: '  \n ' }, { ...COMRADES, name: 12 }]) {
		const r = v([bad, RICHMOND]);
		assert.equal(r.races.length, 1, JSON.stringify(bad));
		assert.ok(r.assumptions.includes('race_dropped_invalid'));
	}
});

test('a name loses control characters and runs of whitespace, and is capped', () => {
	const r = v([{ ...COMRADES, name: '  Comrades\u0000\n  Marathon ' }]);
	assert.equal(r.races[0].name, 'Comrades Marathon');
	const long = v([{ ...COMRADES, name: 'x'.repeat(500) }]);
	assert.equal(long.races[0].name.length, MAX_SEASON_RACE_NAME_CHARS);
});

test('the name cap counts code points, not UTF-16 units', () => {
	const r = v([{ ...COMRADES, name: '🏃'.repeat(200) }]);
	assert.equal(Array.from(r.races[0].name).length, MAX_SEASON_RACE_NAME_CHARS);
});

// ───────────────────────── date ─────────────────────────

test('a missing, malformed or impossible date drops the race', () => {
	for (const date of [undefined, null, '', '14 Nov', '2026/11/14', '2027-02-31', '2027-13-01', 20261114]) {
		const r = v([{ ...RICHMOND, date }]);
		assert.deepEqual(r.races, [], String(date));
		assert.deepEqual(r.assumptions, ['race_dropped_date']);
	}
});

test('today is not a future race date; tomorrow is', () => {
	// Today is neither a future date nor a partial date in the past, so it
	// must not roll to next year either.
	assert.deepEqual(v([{ ...RICHMOND, date: TODAY }]).races, [], 'today is refused');
	assert.equal(v([{ ...RICHMOND, date: '2026-10-17' }]).races[0].date, '2026-10-17');
});

test('a date exactly two years out is kept; one day later is dropped', () => {
	assert.equal(v([{ ...RICHMOND, date: '2028-10-16' }]).races[0].date, '2028-10-16');
	const r = v([{ ...RICHMOND, date: '2028-10-17' }]);
	assert.deepEqual(r.races, []);
	assert.deepEqual(r.assumptions, ['race_dropped_date']);
});

test('a partial date resolved to this year moves to next year, and says so', () => {
	const r = v([{ ...TWO_OCEANS, date: '2026-04-04' }]);
	assert.equal(r.races[0].date, '2027-04-04');
	assert.ok(r.assumptions.includes('race_date_next_year'));
});

test('yesterday rolls forward a year', () => {
	const r = v([{ ...RICHMOND, date: '2026-10-15' }]);
	assert.equal(r.races[0].date, '2027-10-15');
});

test('a date a year or more in the past is dropped, not rolled', () => {
	for (const date of ['2025-10-16', '2025-01-01', '1999-04-04']) {
		const r = v([{ ...RICHMOND, date }]);
		assert.deepEqual(r.races, [], date);
		assert.deepEqual(r.assumptions, ['race_dropped_date']);
	}
});

test('a past 29 February cannot roll into a non-leap year and is dropped', () => {
	const r = validateSeasonRaces({ races: [{ ...RICHMOND, date: '2028-02-29' }] }, '2028-10-16');
	assert.deepEqual(r.races, []);
	assert.deepEqual(r.assumptions, ['race_dropped_date']);
});

test('an unreadable today keeps nothing', () => {
	assert.deepEqual(validateSeasonRaces({ races: [RICHMOND] }, 'not-a-date').races, []);
});

// ───────────────────────── distance ─────────────────────────

test('a distance outside 5 km .. 400 km drops the race; the bounds are inclusive', () => {
	assert.equal(v([{ ...RICHMOND, distance_km: 5 }]).races[0].distanceM, 5000);
	assert.equal(v([{ ...RICHMOND, distance_km: 400 }]).races[0].distanceM, 400_000);
	for (const distance_km of [4.99, 400.01, 0, -42, 1e9, undefined, null, '42.195', NaN, Infinity]) {
		const r = v([{ ...RICHMOND, distance_km }]);
		assert.deepEqual(r.races, [], String(distance_km));
		assert.deepEqual(r.assumptions, ['race_dropped_distance']);
	}
});

test('a distance within half a percent of a standard road distance snaps to it', () => {
	assert.equal(v([{ ...RICHMOND, distance_km: 42.2 }]).races[0].distanceM, 42_195);
	assert.equal(v([{ ...RICHMOND, distance_km: 21.1 }]).races[0].distanceM, 21_097.5);
	assert.equal(v([{ ...RICHMOND, distance_km: 10.03 }]).races[0].distanceM, 10_000);
	assert.equal(v([{ ...RICHMOND, distance_km: 160.934 }]).races[0].distanceM, 160_934);
	assert.equal(v([{ ...RICHMOND, distance_km: 43 }]).races[0].distanceM, 43_000, 'a 43 km trail race is not a marathon');
});

test('a non-standard distance rounds to the metre', () => {
	assert.equal(v([{ ...RICHMOND, distance_km: 87.6543 }]).races[0].distanceM, 87_654);
});

// ───────────────────────── goal time ─────────────────────────

test('a goal time inside the pace band is kept, rounded', () => {
	assert.equal(v([{ ...RICHMOND, goal_time_sec: 12_600.4 }]).races[0].goalTimeSec, 12_600);
	// A 30 h 100-miler is 11:11/km — far slower than the plan wizard allows.
	assert.equal(v([{ ...RICHMOND, distance_km: 160.934, goal_time_sec: 30 * 3600 }]).races[0].goalTimeSec, 108_000);
});

test('a goal time outside 2:30 .. 20:00 per km is dropped and the race kept', () => {
	for (const goal_time_sec of [0, -1, 100, 42.195 * 149, 42.195 * 1201, 1e12]) {
		const r = v([{ ...RICHMOND, goal_time_sec }]);
		assert.equal(r.races.length, 1);
		assert.equal(r.races[0].goalTimeSec, null, String(goal_time_sec));
		assert.ok(r.assumptions.includes('goal_time_dropped'));
	}
});

test('a non-numeric goal time is ignored without an assumption', () => {
	for (const goal_time_sec of ['3:30', null, undefined, NaN]) {
		const r = v([{ ...COMRADES, goal_time_sec }]);
		assert.equal(r.races[0].goalTimeSec, null);
		assert.deepEqual(r.assumptions, []);
	}
});

// ───────────────────────── duplicates, sort, cap ─────────────────────────

test('the same date and distance collapse into one race', () => {
	const r = v([RICHMOND, { ...RICHMOND, name: 'Richmond' }]);
	assert.equal(r.races.length, 1);
	assert.equal(r.races[0].name, 'Richmond Marathon');
	assert.ok(r.assumptions.includes('race_duplicate_merged'));
});

test('the same name on the same date collapses whatever the distance, case-blind', () => {
	const r = v([RICHMOND, { ...RICHMOND, name: 'RICHMOND MARATHON', distance_km: 21.1 }]);
	assert.equal(r.races.length, 1);
	assert.equal(r.races[0].distanceM, 42_195);
});

test('a merge keeps the stronger stated priority and the first goal time found', () => {
	const r = v([
		{ ...RICHMOND, priority: 'C' },
		{ ...RICHMOND, priority: 'A', goal_time_sec: 12_600 },
		{ ...RICHMOND, priority: 'B', goal_time_sec: 13_000 },
	]);
	assert.equal(r.races.length, 1);
	assert.equal(r.races[0].priority, 'A');
	assert.equal(r.races[0].goalTimeSec, 12_600);
});

test('a stated priority beats a defaulted one on merge', () => {
	const r = v([{ ...RICHMOND, priority: undefined }, { ...RICHMOND, priority: 'C' }, TWO_OCEANS, { ...COMRADES }]);
	assert.equal(r.races[0].priority, 'C');
	assert.ok(!r.assumptions.includes('priority_default'));
});

test('two different races on one day both stay, the longer first', () => {
	const r = v([
		{ name: 'Disney 10K', date: '2027-01-08', distance_km: 10, priority: 'C' },
		{ name: 'Disney Marathon', date: '2027-01-08', distance_km: 42.195, priority: 'A' },
	]);
	assert.deepEqual(r.races.map((x) => x.name), ['Disney Marathon', 'Disney 10K']);
});

test('more than twelve races keep the earliest twelve', () => {
	const many = Array.from({ length: 15 }, (_, i) => ({
		name: `Race ${i}`,
		date: `2027-${String(i % 12 + 1).padStart(2, '0')}-${i < 12 ? '10' : '20'}`,
		distance_km: 10,
		priority: 'C',
	}));
	const r = v([...many, { ...COMRADES, date: '2028-06-13' }]);
	assert.equal(r.races.length, MAX_SEASON_RACES);
	assert.ok(r.assumptions.includes('races_capped'));
	assert.ok(!r.races.some((x) => x.name === 'Comrades'), 'the latest race fell past the cap');
	// With Comrades capped away, no A remains — the longest kept race becomes A.
	assert.ok(r.assumptions.includes('priority_a_assigned'));
	assert.equal(r.races.filter((x) => x.priority === 'A').length, 1);
});

// ───────────────────────── priority ─────────────────────────

test('priority is read case-blind and an unreadable one defaults to B', () => {
	const r = v([{ ...RICHMOND, priority: ' c ' }, { ...TWO_OCEANS, priority: 'primary' }, COMRADES]);
	assert.deepEqual(r.races.map((x) => x.priority), ['C', 'B', 'A']);
	assert.deepEqual(r.assumptions, ['priority_default']);
});

test('with no A race, the longest becomes A', () => {
	const r = v([{ ...COMRADES, priority: 'B' }, RICHMOND, TWO_OCEANS]);
	assert.deepEqual(r.races.map((x) => x.priority), ['B', 'B', 'A']);
	assert.deepEqual(r.assumptions, ['priority_a_assigned']);
});

test('with no priorities at all, every race is B except the longest', () => {
	const strip = ({ priority: _p, ...rest }: Record<string, unknown>) => rest;
	const r = v([strip(RICHMOND), strip(TWO_OCEANS), strip(COMRADES)]);
	assert.deepEqual(r.races.map((x) => x.priority), ['B', 'B', 'A']);
	assert.deepEqual(r.assumptions, ['priority_default', 'priority_a_assigned']);
});

test('a tie for longest gives A to the later race', () => {
	const r = v([
		{ name: 'Spring marathon', date: '2027-03-01', distance_km: 42.195 },
		{ name: 'Autumn marathon', date: '2027-10-01', distance_km: 42.195 },
	]);
	assert.deepEqual(r.races.map((x) => x.priority), ['B', 'A']);
});

test('several A races are allowed and left alone', () => {
	const r = v([{ ...RICHMOND, priority: 'A' }, COMRADES]);
	assert.deepEqual(r.races.map((x) => x.priority), ['A', 'A']);
	assert.deepEqual(r.assumptions, []);
});

// ───────────────────────── assumptions ─────────────────────────

test('assumptions are unique and listed in declaration order', () => {
	const r = v([
		{ ...RICHMOND, date: 'x' },
		{ ...RICHMOND, date: 'y' },
		{ ...RICHMOND, distance_km: 1 },
		{ ...TWO_OCEANS, date: '2026-04-04', priority: undefined },
		null,
	]);
	assert.deepEqual(r.assumptions, [
		'race_dropped_invalid',
		'race_dropped_date',
		'race_dropped_distance',
		'race_date_next_year',
		'priority_default',
		'priority_a_assigned',
	]);
	for (const a of r.assumptions) assert.ok((SEASON_REQUEST_ASSUMPTIONS as readonly string[]).includes(a));
});

test('every race that comes back sits inside the bands the clients parse against', () => {
	const r = v([RICHMOND, TWO_OCEANS, COMRADES, { ...RICHMOND, date: '2026-05-01', name: 'Rolled' }]);
	for (const race of r.races) {
		assert.ok(race.date > TODAY && race.date <= '2028-10-16');
		assert.ok(race.distanceM >= 5000 && race.distanceM <= 400_000);
		assert.ok(['A', 'B', 'C'].includes(race.priority));
		assert.ok(race.name.length > 0 && race.name.length <= MAX_SEASON_RACE_NAME_CHARS);
	}
});
