import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	SEASON_MAX_PLAN_WEEKS,
	SEASON_RACE_NAME_MAX,
	buildSeason,
	seasonGoal,
	seasonRecoveryDays,
	type SeasonBuildResult,
	type SeasonPlanDraft,
} from './season_plan';
import { RACE_PLAN_MIN_WEEKS } from './race_plan_preset';
import type { GeneratedWorkout } from './training';
import type { SeasonRace } from './season_types';

const TODAY = '2026-08-14'; // a Friday

function race(name: string, date: string, distanceM: number, priority: 'A' | 'B' | 'C', goalTimeSec: number | null = null): SeasonRace {
	return { name, date, distanceM, priority, goalTimeSec };
}

const RICHMOND = race('Richmond Marathon', '2026-11-14', 42_195, 'A', 12_600);
const TWO_OCEANS = race('Two Oceans', '2027-04-03', 56_000, 'B', 21_600);
const COMRADES = race('Comrades', '2027-06-13', 87_000, 'A');

function build(races: SeasonRace[], daysPerWeek = 4): SeasonBuildResult {
	return buildSeason({ races, todayIso: TODAY, daysPerWeek });
}

function ok(r: SeasonBuildResult): Extract<SeasonBuildResult, { ok: true }> {
	assert.equal(r.ok, true, `expected a season, got ${JSON.stringify(r)}`);
	return r as Extract<SeasonBuildResult, { ok: true }>;
}

function workouts(p: SeasonPlanDraft): GeneratedWorkout[] {
	return p.generated.weeks.flatMap((w) => w.workouts);
}

function utcDay(iso: string): number {
	const [y, m, d] = iso.split('-').map(Number);
	return Math.floor(Date.UTC(y, m - 1, d) / 86_400_000);
}

function isSunday(iso: string): boolean {
	return (((utcDay(iso) + 4) % 7) + 7) % 7 === 0;
}

test('seasonRecoveryDays: a day per 3 km raced, held to 3-28 days', () => {
	assert.equal(seasonRecoveryDays(5_000), 3);
	assert.equal(seasonRecoveryDays(10_000), 3);
	assert.equal(seasonRecoveryDays(21_097.5), 7);
	assert.equal(seasonRecoveryDays(42_195), 14);
	assert.equal(seasonRecoveryDays(56_000), 19);
	assert.equal(seasonRecoveryDays(87_000), 28);
	assert.equal(seasonRecoveryDays(160_934), 28);
});

test('seasonGoal: a road distance maps to its event, anything else is custom', () => {
	assert.deepEqual(seasonGoal(42_195), { goalEvent: 'distance_full', goalDistanceM: 42_195 });
	assert.deepEqual(seasonGoal(42_300), { goalEvent: 'distance_full', goalDistanceM: 42_195 });
	assert.deepEqual(seasonGoal(10_000), { goalEvent: 'distance_10k', goalDistanceM: 10_000 });
	assert.deepEqual(seasonGoal(56_000), { goalEvent: 'custom', goalDistanceM: 56_000 });
});

test('buildSeason refuses an empty race list', () => {
	assert.deepEqual(build([]), { ok: false, reason: 'empty', races: [] });
});

test('buildSeason refuses a season with no A race rather than promoting one', () => {
	const r = build([race('Club 10k', '2026-10-10', 10_000, 'C'), race('Half', '2026-11-01', 21_097.5, 'B')]);
	assert.deepEqual(r, { ok: false, reason: 'no_a_race', races: [] });
});

test('buildSeason refuses an invalid race and names every one', () => {
	const r = build([
		RICHMOND,
		race('Bad date', '2026-02-31', 10_000, 'C'),
		race('No distance', '2026-10-10', 0, 'C'),
		race('x'.repeat(SEASON_RACE_NAME_MAX + 1), '2026-10-10', 5_000, 'C'),
		race('Zero goal', '2026-10-10', 5_000, 'C', 0),
	]);
	assert.equal(r.ok, false);
	assert.equal((r as { reason: string }).reason, 'invalid_race');
	assert.equal((r as { races: string[] }).races.length, 4);
	assert.equal(build([race('  ', '2026-10-10', 5_000, 'A')]).ok, false);
});

test('buildSeason refuses a race that is today or past', () => {
	const r = build([RICHMOND, race('Last week', TODAY, 5_000, 'C')]);
	assert.deepEqual(r, { ok: false, reason: 'race_not_ahead', races: ['Last week'] });
});

test('buildSeason refuses a first A race fewer than the minimum weeks away', () => {
	const r = build([race('Soon Half', '2026-09-05', 21_097.5, 'A')]);
	assert.deepEqual(r, { ok: false, reason: 'first_too_soon', races: ['Soon Half'] });
});

test('buildSeason refuses two A races too close and names both', () => {
	const r = build([race('Autumn Half', '2026-10-11', 21_097.5, 'A'), race('Fast 10k', '2026-11-08', 10_000, 'A')]);
	assert.deepEqual(r, { ok: false, reason: 'a_races_too_close', races: ['Autumn Half', 'Fast 10k'] });
});

test('one A race: a plan from the next Sunday at the goal default length, ending on race day', () => {
	const { plans, gaps, unplaced } = ok(build([race('Spring 10k', '2026-12-06', 10_000, 'A', 2_700)]));
	assert.equal(plans.length, 1);
	assert.equal(gaps.length, 0);
	assert.equal(unplaced.length, 0);
	const p = plans[0];
	assert.equal(p.name, 'Spring 10k');
	assert.equal(p.goalEvent, 'distance_10k');
	assert.equal(p.weeks, 8);
	assert.ok(isSunday(p.startDate));
	assert.equal(p.endDate, '2026-12-06');
	assert.equal(p.generated.endDate, '2026-12-06');
	const last = workouts(p).at(-1)!;
	assert.equal(last.scheduled_date, '2026-12-06');
	assert.equal(last.kind, 'race');
	assert.equal(last.race_name, 'Spring 10k');
	assert.equal(last.race_priority, 'A');
	assert.equal(last.target_duration_seconds, 2_700);
});

test('an A race off a Sunday moves the race to race day and drops the days after it', () => {
	const { plans } = ok(build([RICHMOND]));
	const p = plans[0];
	assert.equal(p.startDate, '2026-08-16');
	assert.equal(p.weeks, 13);
	const all = workouts(p);
	assert.ok(all.every((w) => w.scheduled_date <= '2026-11-14'));
	const races = all.filter((w) => w.kind === 'race');
	assert.equal(races.length, 1);
	assert.equal(races[0].scheduled_date, '2026-11-14');
	assert.equal(races[0].target_distance_m, 42_195);
	assert.equal(all.find((w) => w.scheduled_date === '2026-11-08')!.kind, 'rest');
});

test('two A races chain: the later plan starts on a Sunday after the recovery gap', () => {
	const { plans, gaps } = ok(build([RICHMOND, COMRADES]));
	assert.equal(plans.length, 2);
	const [a, b] = plans;
	assert.ok(isSunday(b.startDate));
	assert.ok(utcDay(b.startDate) - utcDay(a.endDate) - 1 >= seasonRecoveryDays(42_195));
	assert.equal(gaps.length, 1);
	assert.equal(gaps[0].afterRace, 'Richmond Marathon');
	assert.equal(gaps[0].from, '2026-11-15');
	assert.equal(gaps[0].to, '2027-01-02');
	assert.equal(gaps[0].days, 49);
	assert.equal(gaps[0].recoveryDays, 14);
});

test('a later plan fills the gap up to the maximum length', () => {
	const { plans } = ok(build([RICHMOND, COMRADES]));
	assert.equal(plans[1].weeks, SEASON_MAX_PLAN_WEEKS);
	assert.equal(plans[1].startDate, '2027-01-03');
	const close = ok(build([race('Autumn Half', '2026-10-11', 21_097.5, 'A'), race('Winter Marathon', '2026-12-13', 42_195, 'A')]));
	assert.equal(close.plans[1].startDate, '2026-10-25');
	assert.equal(close.plans[1].weeks, 8);
	assert.equal(close.gaps[0].days, 13);
});

test('a custom distance A race plans at its own distance', () => {
	const { plans } = ok(build([race('Two Oceans', '2027-04-03', 56_000, 'A')]));
	assert.equal(plans[0].goalEvent, 'custom');
	assert.equal(plans[0].goalDistanceM, 56_000);
	assert.equal(workouts(plans[0]).find((w) => w.kind === 'race')!.target_distance_m, 56_000);
});

test('a 56 km and a 90 km A race chain, the first taking the ultra default length', () => {
	const { plans, gaps } = ok(build([race('Two Oceans', '2027-04-03', 56_000, 'A'), race('Comrades', '2027-06-13', 90_000, 'A')]));
	assert.deepEqual(
		plans.map((p) => [p.name, p.goalEvent, p.goalDistanceM, p.weeks, p.startDate, p.endDate]),
		[
			['Two Oceans', 'custom', 56_000, 16, '2026-12-13', '2027-04-03'],
			['Comrades', 'custom', 90_000, 8, '2027-04-25', '2027-06-13'],
		]
	);
	assert.deepEqual([gaps[0].days, gaps[0].recoveryDays], [21, 19]);
	assert.equal(workouts(plans[1]).at(-1)!.target_distance_m, 90_000);
});

test('a B race inside a plan becomes a race workout on its date, replacing the generated one', () => {
	const { plans, unplaced } = ok(build([RICHMOND, TWO_OCEANS, COMRADES]));
	assert.equal(unplaced.length, 0);
	assert.deepEqual(plans[0].races, []);
	assert.deepEqual(plans[1].races, [TWO_OCEANS]);
	const onDay = workouts(plans[1]).filter((w) => w.scheduled_date === '2027-04-03');
	assert.equal(onDay.length, 1);
	assert.deepEqual(onDay[0], {
		scheduled_date: '2027-04-03',
		kind: 'race',
		target_distance_m: 56_000,
		target_duration_seconds: 21_600,
		target_pace_sec_per_km: 386,
		target_pace_tolerance_sec: 5,
		structure: null,
		notes: null,
		race_name: 'Two Oceans',
		race_priority: 'B',
	});
});

test('a C race with no goal time carries no pace', () => {
	const { plans } = ok(build([race('parkrun', '2026-10-03', 5_000, 'C'), RICHMOND]));
	const w = workouts(plans[0]).find((x) => x.scheduled_date === '2026-10-03')!;
	assert.equal(w.kind, 'race');
	assert.equal(w.race_priority, 'C');
	assert.equal(w.target_pace_sec_per_km, null);
	assert.equal(w.target_pace_tolerance_sec, null);
});

test('B / C races outside every plan are reported unplaced, with where they fell', () => {
	const { plans, unplaced } = ok(
		build([
			race('Early parkrun', '2026-08-15', 5_000, 'C'),
			RICHMOND,
			race('Turkey Trot', '2026-11-26', 10_000, 'C'),
			COMRADES,
			race('Winter 10k', '2027-07-04', 10_000, 'B'),
		])
	);
	assert.deepEqual(
		unplaced.map((u) => [u.race.name, u.reason]),
		[
			['Early parkrun', 'before_first_plan'],
			['Turkey Trot', 'between_plans'],
			['Winter 10k', 'after_last_plan'],
		]
	);
	assert.ok(plans.every((p) => p.races.length === 0));
});

test('a B / C race on an A race day or on a placed race day is unplaced as same_day', () => {
	const { plans, unplaced } = ok(
		build([RICHMOND, race('Shadow 5k', '2026-11-14', 5_000, 'C'), race('Club 10k', '2026-10-10', 10_000, 'B'), race('Club 5k', '2026-10-10', 5_000, 'C')])
	);
	assert.deepEqual(
		unplaced.map((u) => [u.race.name, u.reason]),
		[
			['Club 5k', 'same_day'],
			['Shadow 5k', 'same_day'],
		]
	);
	assert.deepEqual(plans[0].races.map((r) => r.name), ['Club 10k']);
});

test('every week restates its volume from the workouts it now holds', () => {
	const { plans } = ok(build([RICHMOND, TWO_OCEANS, COMRADES]));
	for (const p of plans) {
		for (const w of p.generated.weeks) {
			assert.equal(w.target_volume_m, w.workouts.reduce((s, x) => s + (x.target_distance_m ?? 0), 0));
		}
	}
});

test('plans never overlap and every window holds the minimum and maximum lengths', () => {
	const { plans } = ok(build([RICHMOND, TWO_OCEANS, COMRADES], 5));
	for (let i = 0; i < plans.length; i++) {
		const p = plans[i];
		assert.ok(p.weeks >= RACE_PLAN_MIN_WEEKS && p.weeks <= SEASON_MAX_PLAN_WEEKS);
		assert.ok(p.startDate >= TODAY);
		const days = workouts(p).map((w) => w.scheduled_date);
		assert.equal(days[0], p.startDate);
		assert.equal(days.at(-1), p.endDate);
		if (i > 0) assert.ok(p.startDate > plans[i - 1].endDate);
		assert.equal(p.daysPerWeek, 5);
	}
});

test('the race list order does not matter', () => {
	const a = ok(build([COMRADES, TWO_OCEANS, RICHMOND]));
	const b = ok(build([RICHMOND, TWO_OCEANS, COMRADES]));
	assert.deepEqual(
		a.plans.map((p) => [p.name, p.startDate, p.endDate]),
		b.plans.map((p) => [p.name, p.startDate, p.endDate])
	);
});

test('extra recovery shapes every plan in the season the way a masters age does', () => {
	const volumes = (r: SeasonBuildResult) =>
		ok(r).plans.map((p) => p.generated.weeks.map((w) => w.target_volume_m));
	const races = [RICHMOND, COMRADES];
	const masters = volumes(buildSeason({ races, todayIso: TODAY, daysPerWeek: 4, age: 60 }));
	assert.deepEqual(
		volumes(buildSeason({ races, todayIso: TODAY, daysPerWeek: 4, extraRecovery: true })),
		masters
	);
	assert.notDeepEqual(volumes(build(races)), masters);
});
