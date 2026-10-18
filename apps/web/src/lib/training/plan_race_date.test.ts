import { test } from 'node:test';
import assert from 'node:assert/strict';
import { planRaceDate, raceDateChange, type RaceDateWorkout } from './plan_race_date.ts';
import { shiftIsoDate } from './plan_bulk_ops.ts';

// A ten-week half plan from Sunday 2026-06-07: base 0-1, build 2-5, peak 6-7,
// taper 8, race 9. A long run every Sunday, the race on week 9's Sunday and
// six easy days after it, as the generator writes them. Today is in week 2.
const S = '2026-06-07';
const TODAY = '2026-06-24';
const phases = ['base', 'base', 'build', 'build', 'build', 'build', 'peak', 'peak', 'taper', 'race'];
const plan = { start_date: S, end_date: shiftIsoDate(S, 69), trimmed_at: null, status: 'active' };
const weeks = phases.map((phase, i) => ({ id: `w${i}`, week_index: i, phase }));
function workouts(): RaceDateWorkout[] {
	const out: RaceDateWorkout[] = weeks.map((w, i) => ({
		id: i === 9 ? 'race' : `long${i}`,
		week_id: w.id,
		scheduled_date: shiftIsoDate(S, 7 * i),
		kind: i === 9 ? 'race' : 'long',
		completed_run_id: null,
		manually_completed: i === 0
	}));
	for (let d = 1; d <= 6; d++) {
		out.push({
			id: `easy${d}`,
			week_id: 'w9',
			scheduled_date: shiftIsoDate(S, 63 + d),
			kind: 'easy',
			completed_run_id: null,
			manually_completed: false
		});
	}
	return out;
}
const change = (raceDateIso: string, over: Partial<{ todayIso: string; workouts: RaceDateWorkout[] }> = {}) =>
	raceDateChange({ plan, weeks, workouts: over.workouts ?? workouts(), raceDateIso, todayIso: over.todayIso ?? TODAY });

test('an earlier race drops the latest build weeks first and moves the race', () => {
	assert.deepEqual(change(shiftIsoDate(S, 52)), {
		ok: true,
		change: {
			raceDateIso: shiftIsoDate(S, 52),
			weekDelta: -2,
			dropWeekIds: ['w4', 'w5'],
			insertAt: null,
			insertCount: 0,
			repeatWeekId: null,
			raceWorkoutId: 'race'
		}
	});
});

test('once the build runs out the peak goes, never the taper', () => {
	const r = change(shiftIsoDate(S, 35));
	assert.ok(r.ok);
	assert.deepEqual(r.change.dropWeekIds, ['w3', 'w4', 'w5', 'w7']);
	assert.equal(r.change.weekDelta, -4);
});

test('a race too close for the taper is refused with the earliest day it can keep', () => {
	assert.deepEqual(change(shiftIsoDate(S, 21)), { ok: false, reason: 'too_soon', earliestIso: shiftIsoDate(S, 28) });
});

test('a later race repeats the last build week before the peak', () => {
	assert.deepEqual(change(shiftIsoDate(S, 77)), {
		ok: true,
		change: {
			raceDateIso: shiftIsoDate(S, 77),
			weekDelta: 2,
			dropWeekIds: [],
			insertAt: 6,
			insertCount: 2,
			repeatWeekId: 'w5',
			raceWorkoutId: 'race'
		}
	});
});

test('a later race once the peak has started goes in before the taper', () => {
	const r = change(shiftIsoDate(S, 77), { todayIso: shiftIsoDate(S, 45) });
	assert.ok(r.ok);
	assert.equal(r.change.insertAt, 7);
	assert.equal(r.change.repeatWeekId, 'w5');
});

test('a move inside race week changes no weeks', () => {
	const r = change(shiftIsoDate(S, 67));
	assert.ok(r.ok);
	assert.equal(r.change.weekDelta, 0);
	assert.deepEqual(r.change.dropWeekIds, []);
	assert.equal(r.change.insertAt, null);
});

test('race week under way cannot take a week in front of it', () => {
	assert.deepEqual(change(shiftIsoDate(S, 75), { todayIso: shiftIsoDate(S, 64) }), {
		ok: false,
		reason: 'race_week_started'
	});
});

test('another race in a week that would move is in the way', () => {
	const wos = workouts().map((w) =>
		w.id === 'long7' ? { ...w, kind: 'race', race_priority: 'B' } : w
	);
	assert.deepEqual(change(shiftIsoDate(S, 77), { workouts: wos }), { ok: false, reason: 'in_the_way' });
});

test('a completed workout in a week that would move is in the way', () => {
	const wos = workouts().map((w) => (w.id === 'long6' ? { ...w, manually_completed: true } : w));
	assert.deepEqual(change(shiftIsoDate(S, 52), { workouts: wos }), { ok: false, reason: 'in_the_way' });
});

test('past, invalid, unchanged and too-far dates are refused', () => {
	assert.deepEqual(change(TODAY), { ok: false, reason: 'past' });
	assert.deepEqual(change('2026-02-31'), { ok: false, reason: 'invalid' });
	assert.deepEqual(change(plan.end_date), { ok: false, reason: 'unchanged' });
	assert.deepEqual(change(shiftIsoDate(S, 63 + 7 * 53)), { ok: false, reason: 'too_far' });
});

test('a plan with no race ahead offers nothing to move', () => {
	assert.equal(planRaceDate(plan, weeks), plan.end_date);
	assert.equal(planRaceDate({ ...plan, trimmed_at: '2026-06-20T00:00:00Z' }, weeks), null);
	assert.equal(planRaceDate({ ...plan, status: 'completed' }, weeks), null);
	assert.equal(
		planRaceDate(plan, weeks.map((w) => (w.week_index === 9 ? { ...w, phase: 'graduation' } : w))),
		null
	);
	assert.deepEqual(change(shiftIsoDate(S, 80), { todayIso: shiftIsoDate(S, 70) }), {
		ok: false,
		reason: 'no_race'
	});
});
