import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	planToMarkdown,
	planToJson,
	parsePlanMarkdown,
	parsePlanJson,
	type ExportPlan,
} from './plan_serialize';

const SAMPLE: ExportPlan = {
	name: 'Spring Marathon',
	goalEvent: 'distance_full',
	goalDistanceM: 42195,
	goalTimeSec: 3 * 3600 + 30 * 60,
	startDate: '2026-06-07',
	workouts: [
		{ week_index: 0, scheduled_date: '2026-06-07', kind: 'long', target_distance_m: 24_000, target_pace_sec_per_km: 330, notes: 'Easy long run' },
		{ week_index: 0, scheduled_date: '2026-06-08', kind: 'rest', target_distance_m: null, target_pace_sec_per_km: null, notes: null },
		{ week_index: 0, scheduled_date: '2026-06-09', kind: 'tempo', target_distance_m: 10_000, target_pace_sec_per_km: 270, notes: null },
		{ week_index: 1, scheduled_date: '2026-06-14', kind: 'long', target_distance_m: 27_000, target_pace_sec_per_km: 330, notes: null },
		{ week_index: 1, scheduled_date: '2026-06-16', kind: 'interval', target_distance_m: 8_000, target_pace_sec_per_km: 240, notes: '6x800' },
	],
};

function flatten(p: ReturnType<typeof parsePlanMarkdown>) {
	return p.generated.weeks.flatMap((w) =>
		w.workouts.map((wo) => ({
			week_index: w.week_index,
			scheduled_date: wo.scheduled_date,
			kind: wo.kind,
			target_distance_m: wo.target_distance_m,
			target_pace_sec_per_km: wo.target_pace_sec_per_km,
			notes: wo.notes,
		})),
	);
}

// ─────────────────────── Markdown round-trip ───────────────────────

test('planToMarkdown → parsePlanMarkdown round-trips the workouts', () => {
	const md = planToMarkdown(SAMPLE);
	const parsed = parsePlanMarkdown(md);
	assert.equal(parsed.name, SAMPLE.name);
	assert.equal(parsed.goalEvent, SAMPLE.goalEvent);
	assert.equal(parsed.goalDistanceM, SAMPLE.goalDistanceM);
	assert.equal(parsed.goalTimeSec, SAMPLE.goalTimeSec);
	assert.equal(parsed.startDate, SAMPLE.startDate);
	assert.deepEqual(flatten(parsed), SAMPLE.workouts);
});

test('planToMarkdown emits a header table + one row per workout', () => {
	const md = planToMarkdown(SAMPLE);
	assert.match(md, /^# Spring Marathon/);
	assert.match(md, /\| Week \| Date \| Type \| Distance \| Pace \| Notes \|/);
	const rows = md.split('\n').filter((l) => l.startsWith('| ') && !/Week \| Date/.test(l) && !/---/.test(l));
	assert.equal(rows.length, SAMPLE.workouts.length);
});

test('parsePlanMarkdown recomputes phase from week position', () => {
	const base = new Date('2026-06-07T00:00:00Z').getTime();
	const workouts = Array.from({ length: 6 }, (_, wk) => ({
		week_index: wk,
		scheduled_date: new Date(base + wk * 7 * 86_400_000).toISOString().slice(0, 10),
		kind: 'long' as const,
		target_distance_m: 20_000,
		target_pace_sec_per_km: 330,
		notes: null,
	}));
	const parsed = parsePlanMarkdown(planToMarkdown({ ...SAMPLE, workouts }));
	// phaseFor(0, 6) → base; the final week is always 'race'.
	assert.equal(parsed.generated.weeks[0].phase, 'base');
	assert.equal(parsed.generated.weeks[5].phase, 'race');
});

test('parsePlanMarkdown sums weekly volume from the workout distances', () => {
	const parsed = parsePlanMarkdown(planToMarkdown(SAMPLE));
	assert.equal(parsed.generated.weeks[0].target_volume_m, 24_000 + 10_000);
	assert.equal(parsed.generated.weeks[1].target_volume_m, 27_000 + 8_000);
});

test('parsePlanMarkdown accepts a hand-written table with mile distances', () => {
	const md = [
		'# Coach plan',
		'- Goal event: distance_10k',
		'- Start date: 2026-07-05',
		'| Week | Date | Type | Distance | Pace | Notes |',
		'| --- | --- | --- | --- | --- | --- |',
		'| 1 | 2026-07-05 | long | 10 mi | 5:30 | |',
		'| 1 | 2026-07-07 | easy | 5 mi |  | recovery |',
	].join('\n');
	const parsed = parsePlanMarkdown(md);
	const flat = flatten(parsed);
	assert.equal(flat.length, 2);
	assert.ok(Math.abs(flat[0].target_distance_m! - 10 * 1609.344) < 0.01);
	assert.equal(flat[0].target_pace_sec_per_km, 330);
	assert.equal(flat[1].notes, 'recovery');
});

test('parsePlanMarkdown accepts a hand-written row that omits the trailing Notes column', () => {
	const md = [
		'# Coach plan',
		'| Week | Date | Type | Distance | Pace |',
		'| --- | --- | --- | --- | --- |',
		'| 1 | 2026-07-05 | easy | 5 km | 5:00 |',
	].join('\n');
	const parsed = parsePlanMarkdown(md);
	const flat = flatten(parsed);
	assert.equal(flat.length, 1, 'the notes-less row must not be silently dropped');
	assert.equal(flat[0].kind, 'easy');
	assert.equal(flat[0].notes, null);
});

test('fmtPaceCell / fmtHmsCell never emit a :60 seconds field for a fractional input', () => {
	// 359.6 s/km must format as 6:00, not 5:60 (which re-parses a minute off).
	const withFractionalPace = {
		...SAMPLE,
		workouts: [{ ...SAMPLE.workouts[0], target_pace_sec_per_km: 359.6 }],
	};
	const md = planToMarkdown(withFractionalPace);
	assert.ok(!/:60\b/.test(md), `markdown contained a :60 field:\n${md}`);
	const parsed = parsePlanMarkdown(md);
	assert.equal(flatten(parsed)[0].target_pace_sec_per_km, 360);
});

// ─────────────────────── error handling ───────────────────────

test('parsePlanMarkdown throws on an unknown workout kind', () => {
	const md = [
		'| Week | Date | Type | Distance | Pace | Notes |',
		'| --- | --- | --- | --- | --- | --- |',
		'| 1 | 2026-07-05 | sprintz | 5 km | | |',
	].join('\n');
	assert.throws(() => parsePlanMarkdown(md), /Unknown workout type/);
});

test('parsePlanMarkdown throws on a malformed date', () => {
	const md = [
		'| Week | Date | Type | Distance | Pace | Notes |',
		'| --- | --- | --- | --- | --- | --- |',
		'| 1 | 07/05/2026 | easy | 5 km | | |',
	].join('\n');
	assert.throws(() => parsePlanMarkdown(md), /Bad date/);
});

test('parsePlanMarkdown throws when there are no rows', () => {
	assert.throws(() => parsePlanMarkdown('# Just a title\n\nno table here'), /No workout rows/);
});

test('parsePlanMarkdown defaults goalEvent to custom + infers distance from longest run', () => {
	const md = [
		'| Week | Date | Type | Distance | Pace | Notes |',
		'| --- | --- | --- | --- | --- | --- |',
		'| 1 | 2026-07-05 | long | 30 km | | |',
		'| 1 | 2026-07-07 | easy | 8 km | | |',
	].join('\n');
	const parsed = parsePlanMarkdown(md);
	assert.equal(parsed.goalEvent, 'custom');
	assert.equal(parsed.goalDistanceM, 30_000);
});

// ─────────────────────── JSON round-trip ───────────────────────

test('planToJson → parsePlanJson round-trips the workouts', () => {
	const parsed = parsePlanJson(planToJson(SAMPLE));
	assert.equal(parsed.name, SAMPLE.name);
	assert.equal(parsed.goalDistanceM, SAMPLE.goalDistanceM);
	assert.deepEqual(flatten(parsed), SAMPLE.workouts);
});

test('parsePlanJson throws on non-JSON + on missing workouts', () => {
	assert.throws(() => parsePlanJson('not json {'), /valid JSON/);
	assert.throws(() => parsePlanJson('{"name":"x"}'), /workouts array/);
});

test('notes with a pipe survive the round-trip (sanitized to a slash)', () => {
	const withPipe: ExportPlan = {
		...SAMPLE,
		workouts: [
			{ week_index: 0, scheduled_date: '2026-06-07', kind: 'easy', target_distance_m: 5000, target_pace_sec_per_km: null, notes: 'do 4x | strides' },
		],
	};
	const parsed = parsePlanMarkdown(planToMarkdown(withPipe));
	assert.equal(flatten(parsed)[0].notes, 'do 4x / strides');
});

// ─────────────────────── Race columns ───────────────────────

const RACE_PLAN: ExportPlan = {
	name: 'Comrades block',
	goalEvent: 'custom',
	goalDistanceM: 91_000,
	goalTimeSec: 11 * 3600,
	startDate: '2027-03-28',
	workouts: [
		{ week_index: 0, scheduled_date: '2027-03-28', kind: 'long', target_distance_m: 30_000, target_pace_sec_per_km: 360, notes: null, target_duration_seconds: null, race_name: null, race_priority: null },
		{ week_index: 1, scheduled_date: '2027-04-04', kind: 'race', target_distance_m: 56_000, target_pace_sec_per_km: null, notes: 'Two Oceans', target_duration_seconds: 6 * 3600 + 30 * 60, race_name: 'Two Oceans Ultra', race_priority: 'B' },
		{ week_index: 2, scheduled_date: '2027-04-11', kind: 'race', target_distance_m: 91_000, target_pace_sec_per_km: null, notes: null, target_duration_seconds: null, race_name: 'Comrades', race_priority: 'A' },
	],
};

function flattenRaces(p: ReturnType<typeof parsePlanMarkdown>) {
	return p.generated.weeks.flatMap((w) =>
		w.workouts.map((wo) => ({
			week_index: w.week_index,
			scheduled_date: wo.scheduled_date,
			kind: wo.kind,
			target_distance_m: wo.target_distance_m,
			target_pace_sec_per_km: wo.target_pace_sec_per_km,
			notes: wo.notes,
			target_duration_seconds: wo.target_duration_seconds,
			race_name: wo.race_name ?? null,
			race_priority: wo.race_priority ?? null,
		})),
	);
}

test('planToMarkdown adds Race, Priority and Goal columns only when a race carries one', () => {
	assert.match(planToMarkdown(RACE_PLAN), /\| Week \| Date \| Type \| Distance \| Pace \| Notes \| Race \| Priority \| Goal \|/);
	assert.doesNotMatch(planToMarkdown(SAMPLE), /Priority/);
});

test('race columns round-trip through Markdown and JSON', () => {
	assert.deepEqual(flattenRaces(parsePlanMarkdown(planToMarkdown(RACE_PLAN))), RACE_PLAN.workouts);
	assert.deepEqual(flattenRaces(parsePlanJson(planToJson(RACE_PLAN))), RACE_PLAN.workouts);
});

test('parsePlanMarkdown maps columns by header name, in any order and case', () => {
	const md = [
		'# Reordered',
		'| date | WEEK | Type | Race | Priority | Goal | Distance |',
		'| --- | --- | --- | --- | --- | --- | --- |',
		'| 2027-02-06 | 1 | race | parkrun | c | 22:30 | 5 km |',
		'| 2027-02-07 | 1 | easy |  |  |  | 8 km |',
	].join('\n');
	const rows = flattenRaces(parsePlanMarkdown(md));
	assert.deepEqual(rows[0], {
		week_index: 0,
		scheduled_date: '2027-02-06',
		kind: 'race',
		target_distance_m: 5000,
		target_pace_sec_per_km: null,
		notes: null,
		target_duration_seconds: 22 * 60 + 30,
		race_name: 'parkrun',
		race_priority: 'C',
	});
	assert.equal(rows[1].kind, 'easy');
	assert.equal(rows[1].target_distance_m, 8000);
	assert.equal(rows[1].race_name, null);
});

test('parsePlanMarkdown reads the legacy six-column table positionally, extra cells folding into notes', () => {
	const md = [
		'| Week | Date | Type | Distance | Pace | Notes |',
		'| --- | --- | --- | --- | --- | --- |',
		'| 1 | 2027-02-06 | race | 5 km | 4:30 | parkrun | PB attempt |',
	].join('\n');
	const [row] = flattenRaces(parsePlanMarkdown(md));
	assert.equal(row.notes, 'parkrun|PB attempt');
	assert.equal(row.target_pace_sec_per_km, 270);
	assert.equal(row.race_name, null);
	assert.equal(row.race_priority, null);
	assert.equal(row.target_duration_seconds, null);
});

test('parsePlanMarkdown rejects race fields on a non-race row and a bad priority or goal', () => {
	const table = (row: string) =>
		[
			'| Week | Date | Type | Distance | Race | Priority | Goal |',
			'| --- | --- | --- | --- | --- | --- | --- |',
			row,
		].join('\n');
	assert.throws(() => parsePlanMarkdown(table('| 1 | 2027-02-06 | long | 30 km | Big Run |  |  |')), /only apply to race rows/);
	assert.throws(() => parsePlanMarkdown(table('| 1 | 2027-02-06 | easy | 8 km |  | B |  |')), /only apply to race rows/);
	assert.throws(() => parsePlanMarkdown(table('| 1 | 2027-02-06 | race | 5 km | parkrun | D |  |')), /priority "D"/);
	assert.throws(() => parsePlanMarkdown(table('| 1 | 2027-02-06 | race | 5 km | parkrun |  | fast |')), /goal time "fast"/);
});

test('a piped race name, a priority-only race, a goal-only race and the plan goal time survive the round-trip', () => {
	const plan: ExportPlan = {
		name: 'Spring double',
		goalEvent: 'distance_half',
		goalDistanceM: 21_097.5,
		goalTimeSec: 1 * 3600 + 35 * 60 + 20,
		startDate: '2027-03-07',
		workouts: [
			{ week_index: 0, scheduled_date: '2027-03-07', kind: 'race', target_distance_m: 5000, target_pace_sec_per_km: null, notes: null, target_duration_seconds: null, race_name: null, race_priority: 'C' },
			{ week_index: 1, scheduled_date: '2027-03-14', kind: 'race', target_distance_m: 10_000, target_pace_sec_per_km: null, notes: null, target_duration_seconds: 42 * 60 + 5, race_name: null, race_priority: null },
			{ week_index: 2, scheduled_date: '2027-03-21', kind: 'race', target_distance_m: 21_100, target_pace_sec_per_km: null, notes: null, target_duration_seconds: null, race_name: 'City | Half', race_priority: 'A' },
		],
	};
	for (const parsed of [parsePlanMarkdown(planToMarkdown(plan)), parsePlanJson(planToJson(plan))]) {
		assert.equal(parsed.goalTimeSec, plan.goalTimeSec);
		assert.deepEqual(
			flattenRaces(parsed).map((r) => [r.race_name, r.race_priority, r.target_duration_seconds]),
			[
				[null, 'C', null],
				[null, null, 42 * 60 + 5],
				['City / Half', 'A', null],
			],
		);
	}
});

test('parsePlanMarkdown keeps a 120-character race name and rejects a 121-character one', () => {
	const table = (race: string) =>
		['| Week | Date | Type | Distance | Race |', '| --- | --- | --- | --- | --- |', `| 1 | 2027-02-06 | race | 5 km | ${race} |`].join('\n');
	const longest = 'R'.repeat(120);
	assert.equal(flattenRaces(parsePlanMarkdown(table(longest)))[0].race_name, longest);
	assert.throws(() => parsePlanMarkdown(table(longest + 'R')), /longer than 120 characters/);
});

test('parsePlanMarkdown refuses a workout dated before the plan\'s own start date', () => {
	const md = (start: string) =>
		[
			'# Early row',
			`- Start date: ${start}`,
			'| Week | Date | Type | Distance | Pace | Notes |',
			'| --- | --- | --- | --- | --- | --- |',
			'| 1 | 2027-03-07 | easy | 5 km | | |',
			'| 1 | 2027-03-10 | long | 12 km | | |',
		].join('\n');
	assert.throws(() => parsePlanMarkdown(md('2027-03-08')), /2027-03-07 is before the plan's start date, 2027-03-08/);
	assert.equal(parsePlanMarkdown(md('2027-03-07')).startDate, '2027-03-07');
	assert.equal(parsePlanMarkdown(md('2027-03-01')).startDate, '2027-03-01');
});
