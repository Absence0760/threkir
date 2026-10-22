// Unit tests for the scope of an AI plan edit across chained blocks
// (issue #1213, decisions § 2230).
// Run via `npx tsx --test apps/web/src/lib/training/plan_edit/season.test.ts`.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	aiPlanEditPayload,
	cascadeFactor,
	cascadeOps,
	chainedBase,
	offersSeasonScope,
	planSeasonEdit,
	type PlanEditBlock,
} from './season';
import type { PlanEditOp, PlanEditSnapshot } from './ops';
import { TODAY, fixture } from './test_fixture';
import { MIN_ACTIVE_WEEKS } from '../plan_ramp';

const STEADY = { weeklyM: 38_000, activeWeeks: 4 };

/// The block queued the Monday after the fixture's race: two build weeks
/// and a taper. `firstWeekKm` sets week 1's load against the 39 km the
/// fixture's last four weeks average.
function following(firstWeekKm: number): PlanEditBlock {
	const longKm = firstWeekKm - 18;
	const snapshot: PlanEditSnapshot = {
		plan: { start_date: '2026-11-09', end_date: '2026-11-29', goal_distance_m: 21_097, goal_time_seconds: null },
		weeks: [
			{ id: 'f0', week_index: 0, phase: 'build', target_volume_m: firstWeekKm * 1000 },
			{ id: 'f1', week_index: 1, phase: 'build', target_volume_m: 40_000 },
			{ id: 'f2', week_index: 2, phase: 'taper', target_volume_m: 30_000 },
		],
		workouts: [
			{ id: 'f0-easy', week_id: 'f0', scheduled_date: '2026-11-10', kind: 'easy', target_distance_m: 18_000 },
			{ id: 'f0-long', week_id: 'f0', scheduled_date: '2026-11-15', kind: 'long', target_distance_m: longKm * 1000 },
			{ id: 'f1-easy', week_id: 'f1', scheduled_date: '2026-11-17', kind: 'easy', target_distance_m: 16_000 },
			{ id: 'f1-long', week_id: 'f1', scheduled_date: '2026-11-22', kind: 'long', target_distance_m: 24_000 },
			{ id: 'f2-easy', week_id: 'f2', scheduled_date: '2026-11-24', kind: 'easy', target_distance_m: 10_000 },
			{ id: 'f2-long', week_id: 'f2', scheduled_date: '2026-11-29', kind: 'long', target_distance_m: 20_000 },
		],
	};
	return { planId: 'next', name: 'Next block', snapshot };
}

const primary = (): PlanEditBlock => ({ planId: 'this', name: 'This block', snapshot: fixture() });
const HARDER: PlanEditOp[] = [{ op: 'scale_week', weekIndex: 1, factor: 1.1 }];
const EASIER: PlanEditOp[] = [{ op: 'scale_week', weekIndex: 1, factor: 0.9 }];

test('only a uniform scale carries forward, as the mildest factor', () => {
	assert.equal(cascadeFactor([]), null);
	assert.equal(cascadeFactor([{ op: 'skip_workout', workoutId: 'x' }]), null);
	assert.equal(cascadeFactor([{ op: 'mark_recovery', weekIndex: 1 }]), null);
	assert.equal(
		cascadeFactor([
			{ op: 'scale_week', weekIndex: 1, factor: 0.8 },
			{ op: 'scale_week', weekIndex: 2, factor: 0.9 },
		]),
		0.9,
	);
	assert.equal(
		cascadeFactor([
			{ op: 'scale_week', weekIndex: 1, factor: 1.1 },
			{ op: 'scale_week', weekIndex: 2, factor: 1.05 },
		]),
		1.05,
	);
	assert.equal(
		cascadeFactor([
			{ op: 'scale_week', weekIndex: 1, factor: 1.1 },
			{ op: 'scale_week', weekIndex: 2, factor: 0.9 },
		]),
		null,
		'scales in both directions carry nothing',
	);
});

test('the carried scale reaches every open week, but a scale-up never a taper week', () => {
	const next = following(40).snapshot;
	assert.deepEqual(
		cascadeOps(next, 1.1, TODAY).map((o) => (o.op === 'scale_week' ? o.weekIndex : -1)),
		[0, 1],
	);
	assert.deepEqual(
		cascadeOps(next, 0.9, TODAY).map((o) => (o.op === 'scale_week' ? o.weekIndex : -1)),
		[0, 1, 2],
	);
});

test('a block longer than one request\'s operation cap is still scaled in full', () => {
	const weeks = Array.from({ length: 18 }, (_, i) => ({
		id: `w${i}`,
		week_index: i,
		phase: 'build',
		target_volume_m: 30_000,
	}));
	const workouts = weeks.map((w, i) => ({
		id: `x${i}`,
		week_id: w.id,
		scheduled_date: new Date(Date.UTC(2027, 0, 5 + i * 7)).toISOString().slice(0, 10),
		kind: 'easy',
		target_distance_m: 30_000,
	}));
	const block: PlanEditSnapshot = {
		plan: { start_date: '2027-01-04', end_date: '2027-05-09', goal_distance_m: 42_195, goal_time_seconds: null },
		weeks,
		workouts,
	};
	assert.equal(cascadeOps(block, 0.9, TODAY).length, 18);
});

test('the following block is graded against the block before it', () => {
	// Fixture weeks: 40, 42, 44 and 30 km planned.
	assert.deepEqual(chainedBase(fixture()), { weeklyM: 39_000, activeWeeks: MIN_ACTIVE_WEEKS });
});

test('this block only: the following block is untouched and not graded', () => {
	const edit = planSeasonEdit({
		primary: primary(),
		ops: HARDER,
		following: [following(48)],
		recent: STEADY,
		todayIso: TODAY,
		scope: 'plan',
	});
	assert.equal(edit.blocks.length, 1);
	assert.equal(edit.blocks[0].planId, 'this');
	assert.equal(edit.verdict, 'ok');
	assert.ok(aiPlanEditPayload(edit).workouts.every((w) => !w.id.startsWith('f')));
});

test('a cascade that newly lifts a following week to elevated needs a second yes', () => {
	// 48 km against 39 km is 1.23 (optimal); scaled to 52.8 km it is 1.35.
	const edit = planSeasonEdit({
		primary: primary(),
		ops: HARDER,
		following: [following(48)],
		recent: STEADY,
		todayIso: TODAY,
		scope: 'season',
	});
	assert.deepEqual(
		edit.blocks.map((b) => b.planId),
		['this', 'next'],
	);
	assert.equal(edit.blocks[0].check.verdict, 'ok');
	assert.deepEqual(edit.blocks[1].check.raisedWeeks, [{ weekIndex: 0, before: 'optimal', after: 'elevated' }]);
	assert.equal(edit.verdict, 'confirm');
});

test('a cascade that newly lifts a following week to high rejects the whole edit', () => {
	// 55 km against 39 km is 1.41 (elevated); scaled to 60.5 km it is 1.55.
	const edit = planSeasonEdit({
		primary: primary(),
		ops: HARDER,
		following: [following(55)],
		recent: STEADY,
		todayIso: TODAY,
		scope: 'season',
	});
	assert.equal(edit.blocks[1].check.verdict, 'reject');
	assert.equal(edit.verdict, 'reject');
	// The same change to this block only is still allowed.
	const own = planSeasonEdit({
		primary: primary(),
		ops: HARDER,
		following: [following(55)],
		recent: STEADY,
		todayIso: TODAY,
		scope: 'plan',
	});
	assert.equal(own.verdict, 'ok');
});

test('a scale-up leaves the following block\'s taper week at its own targets', () => {
	const edit = planSeasonEdit({
		primary: primary(),
		ops: HARDER,
		following: [following(40)],
		recent: STEADY,
		todayIso: TODAY,
		scope: 'season',
	});
	const next = edit.blocks[1].application;
	assert.deepEqual(
		next.weeks.map((w) => w.weekId),
		['f0', 'f1'],
	);
	assert.ok(!next.workouts.some((c) => c.workoutId.startsWith('f2')));
	assert.equal(next.after.workouts.find((w) => w.id === 'f0-easy')!.target_distance_m, 19_800);
});

test('easing carries into the following block, taper included, and is one payload', () => {
	const edit = planSeasonEdit({
		primary: primary(),
		ops: EASIER,
		following: [following(40)],
		recent: STEADY,
		todayIso: TODAY,
		scope: 'season',
	});
	assert.equal(edit.verdict, 'ok');
	const payload = aiPlanEditPayload(edit);
	assert.deepEqual(
		payload.weeks.map((w) => [w.id, w.target_volume_m]),
		[
			['wk1', 37_800],
			['f0', 36_000],
			['f1', 36_000],
			['f2', 27_000],
		],
	);
	assert.deepEqual(
		payload.workouts.find((w) => w.id === 'f2-long'),
		{ id: 'f2-long', target_distance_m: 18_000 },
	);
});

test('the scope choice is offered only for a uniform scale with a block to carry it into', () => {
	assert.equal(offersSeasonScope(primary(), EASIER, [following(40)], TODAY), true);
	assert.equal(offersSeasonScope(primary(), EASIER, [], TODAY), false);
	assert.equal(offersSeasonScope(primary(), [{ op: 'skip_workout', workoutId: 'b-easy' }], [following(40)], TODAY), false);
	// A following block that is all taper has nothing a scale-up may reach.
	const taperOnly = following(40);
	for (const w of taperOnly.snapshot.weeks) w.phase = 'taper';
	assert.equal(offersSeasonScope(primary(), HARDER, [taperOnly], TODAY), false);
});

test('a skip and a recovery ease reach the payload in the shape the RPC checks', () => {
	const edit = planSeasonEdit({
		primary: primary(),
		ops: [
			{ op: 'skip_workout', workoutId: 'b-easy' },
			{ op: 'mark_recovery', weekIndex: 2 },
		],
		following: [],
		recent: STEADY,
		todayIso: TODAY,
		scope: 'plan',
	});
	const payload = aiPlanEditPayload(edit);
	assert.deepEqual(payload.workouts.find((w) => w.id === 'b-easy'), { id: 'b-easy', skip: true });
	assert.deepEqual(payload.workouts.find((w) => w.id === 'c-tempo'), {
		id: 'c-tempo',
		kind: 'recovery',
		target_distance_m: 6_000,
		target_pace_sec_per_km: null,
		target_pace_tolerance_sec: null,
	});
});

test('a B race ending this block holds the next block\'s first days on a carried scale-up', () => {
	// The fixture's last-day race as a B 16 km: five days of recovery,
	// 11-09 to 11-13, reach the next block's Tuesday easy run but not its
	// Sunday long run.
	const p = primary();
	p.snapshot.workouts.find((w) => w.id === 'd-race')!.race_priority = 'B';
	const edit = planSeasonEdit({
		primary: p,
		ops: HARDER,
		following: [following(40)],
		recent: STEADY,
		todayIso: TODAY,
		scope: 'season',
	});
	const next = edit.blocks[1].application.after.workouts;
	assert.equal(next.find((w) => w.id === 'f0-easy')!.target_distance_m, 18_000);
	assert.equal(next.find((w) => w.id === 'f0-long')!.target_distance_m, 24_200);
});

test('a gap before the next block is not graded as weeks of no running', () => {
	// The same block queued two weeks later.
	const gapped = following(48);
	const later = (iso: string) => new Date(Date.parse(`${iso}T00:00:00Z`) + 14 * 86_400_000).toISOString().slice(0, 10);
	gapped.snapshot.plan = { ...gapped.snapshot.plan, start_date: later('2026-11-09'), end_date: later('2026-11-29') };
	for (const w of gapped.snapshot.workouts) w.scheduled_date = later(w.scheduled_date);
	assert.deepEqual(chainedBase(fixture()), { weeklyM: 39_000, activeWeeks: MIN_ACTIVE_WEEKS });
	const edit = planSeasonEdit({
		primary: primary(),
		ops: HARDER,
		following: [gapped],
		recent: STEADY,
		todayIso: TODAY,
		scope: 'season',
	});
	assert.equal(edit.blocks[1].check.verdict, 'confirm');
});

test('an end-date B ultra with no distance holds eleven recovery days into the next block', () => {
	// The fixture's last-day race as an undistanced B race in a 50 km-goal
	// block: 7 + (50 - 42.195) / 2 = 10.9, so 11 days of recovery, 11-09 to
	// 11-19, cover the next block's Sunday long run (11-15) too.
	const p = primary();
	p.snapshot.plan.goal_distance_m = 50_000;
	const race = p.snapshot.workouts.find((w) => w.id === 'd-race')!;
	race.target_distance_m = null;
	race.race_priority = 'B';
	const edit = planSeasonEdit({
		primary: p,
		ops: HARDER,
		following: [following(40)],
		recent: STEADY,
		todayIso: TODAY,
		scope: 'season',
	});
	const next = edit.blocks[1].application.after.workouts;
	assert.equal(next.find((w) => w.id === 'f0-easy')!.target_distance_m, 18_000);
	assert.equal(next.find((w) => w.id === 'f0-long')!.target_distance_m, 22_000);
});

test('the block before the plan holds the days its B race recovery reaches', () => {
	// The previous block ended on Sunday 10-11 with a B 50 km race: 11 days of
	// recovery run to 10-22, through this week's open sessions.
	const preceding: PlanEditBlock = {
		planId: 'before',
		name: 'Before',
		snapshot: {
			plan: { start_date: '2026-09-14', end_date: '2026-10-11', goal_distance_m: 50_000, goal_time_seconds: null },
			weeks: [{ id: 'p3', week_index: 3, phase: 'race', target_volume_m: 50_000 }],
			workouts: [
				{ id: 'p-race', week_id: 'p3', scheduled_date: '2026-10-11', kind: 'race', target_distance_m: 50_000, race_priority: 'B' },
			],
		},
	};
	const scaleWeek0: PlanEditOp[] = [{ op: 'scale_week', weekIndex: 0, factor: 1.1 }];
	const easy = (edit: ReturnType<typeof planSeasonEdit>) =>
		edit.blocks[0].application.after.workouts.find((w) => w.id === 'a-easy')!.target_distance_m;
	const input = { primary: primary(), ops: scaleWeek0, following: [], recent: STEADY, todayIso: TODAY, scope: 'plan' as const };
	assert.equal(easy(planSeasonEdit({ ...input, preceding })), 8_000);
	assert.equal(easy(planSeasonEdit(input)), 8_800);
});
