import { test } from 'node:test';
import assert from 'node:assert/strict';
import { repeatWeekChange, rerunFrame, rerunPlacement } from './plan_repeat_week.ts';
import { shiftIsoDate } from './plan_bulk_ops.ts';
import type { RaceDatePlan, RaceDateWorkout } from './plan_race_date.ts';

// A ten-week plan from Sunday 2026-06-07. The race plan: base 0-1, build 2-5,
// peak 6-7, taper 8, race 9 on its last Sunday, the end date. The walk-run
// plan: every week base, no race, ending on week 9's Saturday. A long run
// every Sunday and an easy run every Wednesday, weeks 0-1 done. Today is week
// 4's Tuesday.
const S = '2026-06-07';
const TODAY = shiftIsoDate(S, 30);
const RACE = ['base', 'base', 'build', 'build', 'build', 'build', 'peak', 'peak', 'taper', 'race'];
const WALK = Array.from({ length: 10 }, () => 'base');

function plan(phases: string[], over: Partial<RaceDatePlan> = {}): RaceDatePlan {
	const end = phases[phases.length - 1] === 'race' ? 63 : 69;
	return { start_date: S, end_date: shiftIsoDate(S, end), status: 'active', trimmed_at: null, ...over };
}
function weeks(phases: string[]) {
	return phases.map((phase, i) => ({ id: `w${i}`, week_index: i, phase }));
}
function workouts(phases: string[]): RaceDateWorkout[] {
	return phases.flatMap((phase, i) => {
		const race = phase === 'race';
		const long: RaceDateWorkout = {
			id: race ? 'race' : `long${i}`,
			week_id: `w${i}`,
			scheduled_date: shiftIsoDate(S, 7 * i),
			kind: race ? 'race' : 'long',
			completed_run_id: null,
			manually_completed: i <= 1
		};
		if (race) return [long];
		return [
			long,
			{
				id: `easy${i}`,
				week_id: `w${i}`,
				scheduled_date: shiftIsoDate(S, 7 * i + 3),
				kind: 'easy',
				completed_run_id: null,
				manually_completed: i <= 1
			}
		];
	});
}
function run(phases: string[], weekId: string, over: { plan?: Partial<RaceDatePlan>; todayIso?: string; workouts?: RaceDateWorkout[] } = {}) {
	return repeatWeekChange({
		plan: plan(phases, over.plan),
		weeks: weeks(phases),
		workouts: over.workouts ?? workouts(phases),
		weekId,
		todayIso: over.todayIso ?? TODAY
	});
}

test('a walk-run plan repeats this week next week and ends a week later', () => {
	assert.deepEqual(run(WALK, 'w4'), {
		ok: true,
		change: {
			weekId: 'w4',
			copyIndex: 5,
			copyStartIso: shiftIsoDate(S, 35),
			dropWeekId: null,
			endIso: shiftIsoDate(S, 76),
			raceDateIso: null
		}
	});
});

test('last week runs again after this week, not inside it', () => {
	const r = run(WALK, 'w3');
	assert.ok(r.ok);
	assert.equal(r.change.copyIndex, 5);
	assert.equal(r.change.copyStartIso, shiftIsoDate(S, 35));
});

test('a race plan keeps race day by dropping its latest build week', () => {
	assert.deepEqual(run(RACE, 'w4'), {
		ok: true,
		change: {
			weekId: 'w4',
			copyIndex: 5,
			copyStartIso: shiftIsoDate(S, 35),
			dropWeekId: 'w5',
			endIso: shiftIsoDate(S, 63),
			raceDateIso: shiftIsoDate(S, 63)
		}
	});
});

test('with the build behind it, a race plan drops its latest peak week', () => {
	const r = run(RACE, 'w6', { todayIso: shiftIsoDate(S, 44) });
	assert.ok(r.ok);
	assert.equal(r.change.dropWeekId, 'w7');
});

test('a race plan with no pre-taper week left to drop has no room', () => {
	const r = run(RACE, 'w7', { todayIso: shiftIsoDate(S, 51) });
	assert.deepEqual(r, { ok: false, reason: 'no_room' });
});

test('a week two back, or one not started, cannot run again', () => {
	assert.deepEqual(run(WALK, 'w2'), { ok: false, reason: 'not_repeatable' });
	assert.deepEqual(run(WALK, 'w5'), { ok: false, reason: 'not_repeatable' });
	assert.deepEqual(run(WALK, 'nope'), { ok: false, reason: 'not_repeatable' });
});

test('the taper never runs again', () => {
	const r = run(RACE, 'w8', { todayIso: shiftIsoDate(S, 58) });
	assert.deepEqual(r, { ok: false, reason: 'not_repeatable' });
});

test('the last week has nothing after it to push back', () => {
	const r = run(WALK, 'w9', { todayIso: shiftIsoDate(S, 65) });
	assert.deepEqual(r, { ok: false, reason: 'last_week' });
});

test('a paused, template, trimmed, unstarted or finished plan is not active', () => {
	for (const over of [
		{ plan: { status: 'paused' } },
		{ plan: { is_template: true } },
		{ plan: { trimmed_at: '2026-06-20T00:00:00Z' } },
		{ todayIso: shiftIsoDate(S, -1) },
		{ todayIso: shiftIsoDate(S, 70) }
	]) {
		assert.deepEqual(run(WALK, 'w4', over), { ok: false, reason: 'not_active' });
	}
});

test('a done workout or a B race in a week that would move is in the way', () => {
	const done = workouts(WALK).map((w) => (w.id === 'easy7' ? { ...w, manually_completed: true } : w));
	assert.deepEqual(run(WALK, 'w4', { workouts: done }), { ok: false, reason: 'in_the_way' });
	const bRace = workouts(RACE).map((w) => (w.id === 'long5' ? { ...w, kind: 'race' } : w));
	assert.deepEqual(run(RACE, 'w4', { workouts: bRace }), { ok: false, reason: 'in_the_way' });
});

test('the shared rerun drops as many weeks as it copies, build first, then the latest peak', () => {
	const p = plan(RACE);
	const frame = rerunFrame(p, weeks(RACE), workouts(RACE), TODAY);
	assert.ok(frame);
	assert.deepEqual(frame.drops.map((w) => w.id), ['w5', 'w7', 'w6']);
	const two = rerunPlacement(frame, p, 2);
	assert.ok(two.ok);
	assert.deepEqual(two.drops.map((w) => w.id), ['w5', 'w7']);
	assert.equal(two.endIso, p.end_date);
	assert.deepEqual(rerunPlacement(frame, p, 4), { ok: false, reason: 'no_room' });
});

test('the shared rerun moves a plan without a race back by its copies', () => {
	const p = plan(WALK);
	const frame = rerunFrame(p, weeks(WALK), workouts(WALK), TODAY);
	assert.ok(frame);
	assert.equal(frame.current, 4);
	assert.deepEqual(rerunPlacement(frame, p, 3), { ok: true, drops: [], endIso: shiftIsoDate(S, 69 + 21) });
	assert.equal(rerunFrame(p, weeks(WALK), workouts(WALK), shiftIsoDate(S, 65)), null);
});
