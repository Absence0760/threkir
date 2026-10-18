import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	BREAK_MIN_DAYS,
	detectPlanBreak,
	isBreakDismissed,
	planBreakChange,
	type BreakInput,
	type BreakWorkout
} from './plan_break.ts';
import { shiftIsoDate } from './plan_bulk_ops.ts';

// A ten-week half plan from Sunday 2026-06-07: base 0-1, build 2-5, peak 6-7,
// taper 8, race 9 (the race on week 9's Sunday, the plan's end date). A long
// run every Sunday and an easy run every Wednesday. Week 1's long run was the
// last thing done; today is week 4's Tuesday, 22 quiet days later.
const S = '2026-06-07';
const TODAY = shiftIsoDate(S, 30);
const RACE_PHASES = ['base', 'base', 'build', 'build', 'build', 'build', 'peak', 'peak', 'taper', 'race'];
const WALK_PHASES = ['base', 'base', 'build', 'build', 'build', 'build', 'build', 'build', 'build', 'build'];

function plan(over: Partial<BreakInput['plan']> = {}): BreakInput['plan'] {
	return { start_date: S, end_date: shiftIsoDate(S, 63), status: 'active', trimmed_at: null, ...over };
}
function weeks(phases = RACE_PHASES) {
	return phases.map((phase, i) => ({ id: `w${i}`, week_index: i, phase }));
}
function workouts(phases = RACE_PHASES): BreakWorkout[] {
	const out: BreakWorkout[] = [];
	phases.forEach((phase, i) => {
		const race = phase === 'race';
		out.push({
			id: race ? 'race' : `long${i}`,
			week_id: `w${i}`,
			scheduled_date: shiftIsoDate(S, 7 * i),
			kind: race ? 'race' : 'long',
			completed_run_id: null,
			manually_completed: i <= 1
		});
		if (!race) {
			out.push({
				id: `easy${i}`,
				week_id: `w${i}`,
				scheduled_date: shiftIsoDate(S, 7 * i + 3),
				kind: 'easy',
				completed_run_id: null,
				manually_completed: i === 0
			});
		}
	});
	return out;
}
function input(over: Partial<BreakInput> = {}): BreakInput {
	return { plan: plan(), weeks: weeks(), workouts: workouts(), runDatesIso: [], todayIso: TODAY, ...over };
}

test('22 quiet days in a race plan offer up to three weeks, kept to race day', () => {
	assert.deepEqual(detectPlanBreak(input()), {
		fromIso: shiftIsoDate(S, 8),
		days: 22,
		raceDateIso: shiftIsoDate(S, 63),
		maxWeeks: 3
	});
});

test('repeating one week runs this week again and drops the latest build week', () => {
	assert.deepEqual(planBreakChange(input(), 1), {
		weeks: 1,
		repeatWeekIds: ['w4'],
		dropWeekIds: ['w5'],
		endIso: shiftIsoDate(S, 63)
	});
});

test('once the build runs out the peak goes, latest first, never the taper', () => {
	assert.deepEqual(planBreakChange(input(), 2)?.dropWeekIds, ['w5', 'w7']);
	assert.deepEqual(planBreakChange(input(), 3), {
		weeks: 3,
		repeatWeekIds: ['w2', 'w3', 'w4'],
		dropWeekIds: ['w5', 'w6', 'w7'],
		endIso: shiftIsoDate(S, 63)
	});
});

test('a plan without a race pushes its end back and drops nothing', () => {
	const walk = input({ plan: plan({ end_date: shiftIsoDate(S, 69) }), weeks: weeks(WALK_PHASES), workouts: workouts(WALK_PHASES) });
	assert.equal(detectPlanBreak(walk)?.raceDateIso, null);
	assert.equal(detectPlanBreak(walk)?.maxWeeks, 3);
	assert.deepEqual(planBreakChange(walk, 2), {
		weeks: 2,
		repeatWeekIds: ['w3', 'w4'],
		dropWeekIds: [],
		endIso: shiftIsoDate(S, 83)
	});
});

test('a run before today ends the break; a run today does not', () => {
	assert.equal(detectPlanBreak(input({ runDatesIso: [shiftIsoDate(S, 25)] })), null);
	assert.equal(detectPlanBreak(input({ runDatesIso: [TODAY, shiftIsoDate(S, 2)] }))?.days, 22);
});

test('the break needs BREAK_MIN_DAYS quiet days', () => {
	const sixDays = shiftIsoDate(TODAY, -BREAK_MIN_DAYS + 1);
	assert.equal(detectPlanBreak(input({ runDatesIso: [shiftIsoDate(sixDays, -1)] })), null);
	assert.equal(detectPlanBreak(input({ runDatesIso: [shiftIsoDate(sixDays, -2)] }))?.days, 7);
});

test('nothing done since the start counts from the start date', () => {
	const none = workouts().map((w) => ({ ...w, manually_completed: false }));
	const r = detectPlanBreak(input({ workouts: none, todayIso: shiftIsoDate(S, 10) }));
	assert.deepEqual(r, { fromIso: S, days: 10, raceDateIso: shiftIsoDate(S, 63), maxWeeks: 1 });
});

test('only rest days in the quiet stretch is no break', () => {
	const rest = workouts().map((w) =>
		w.scheduled_date > shiftIsoDate(S, 7) && w.scheduled_date < TODAY ? { ...w, kind: 'rest' } : w
	);
	assert.equal(detectPlanBreak(input({ workouts: rest })), null);
});

test('a paused, ended-early, template or finished plan offers nothing', () => {
	assert.equal(detectPlanBreak(input({ plan: plan({ status: 'paused' }) })), null);
	assert.equal(detectPlanBreak(input({ plan: plan({ trimmed_at: '2026-06-20T00:00:00Z' }) })), null);
	assert.equal(detectPlanBreak(input({ plan: plan({ is_template: true }) })), null);
	assert.equal(detectPlanBreak(input({ todayIso: shiftIsoDate(S, 64) })), null);
});

test('before the start or in the last week there is nothing to move', () => {
	assert.equal(detectPlanBreak(input({ todayIso: shiftIsoDate(S, -1) })), null);
	assert.equal(detectPlanBreak(input({ todayIso: shiftIsoDate(S, 63) })), null);
});

test('a break that reaches the taper offers nothing to run again', () => {
	assert.equal(detectPlanBreak(input({ todayIso: shiftIsoDate(S, 58) })), null);
});

test('a race or a done workout in a week that would move refuses the change', () => {
	const walk = { plan: plan({ end_date: shiftIsoDate(S, 69) }), weeks: weeks(WALK_PHASES) };
	const bRace = workouts(WALK_PHASES).map((w) => (w.id === 'long7' ? { ...w, kind: 'race' } : w));
	assert.equal(detectPlanBreak(input({ ...walk, workouts: bRace })), null);
	const doneAhead = workouts(WALK_PHASES).map((w) => (w.id === 'easy8' ? { ...w, completed_run_id: 'r' } : w));
	assert.equal(detectPlanBreak(input({ ...walk, workouts: doneAhead })), null);
});

test('a B race mid-block is neither dropped nor moved off its day', () => {
	const bRace = workouts().map((w) => (w.id === 'long6' ? { ...w, kind: 'race' } : w));
	assert.equal(detectPlanBreak(input({ workouts: bRace }))?.maxWeeks, 1);
	assert.deepEqual(planBreakChange(input({ workouts: bRace }), 1)?.dropWeekIds, ['w5']);
	assert.equal(planBreakChange(input({ workouts: bRace }), 2), null);
});

test('weeks outside 1..maxWeeks are refused', () => {
	assert.equal(planBreakChange(input(), 0), null);
	assert.equal(planBreakChange(input(), 4), null);
	assert.equal(planBreakChange(input(), 1.5), null);
});

test('a dismissal answers only the same plan and the same break', () => {
	const pref = { plan_id: 'p', from: '2026-06-15' };
	assert.equal(isBreakDismissed(pref, 'p', '2026-06-15'), true);
	assert.equal(isBreakDismissed(pref, 'p', '2026-07-01'), false);
	assert.equal(isBreakDismissed(pref, 'q', '2026-06-15'), false);
	assert.equal(isBreakDismissed(null, 'p', '2026-06-15'), false);
	assert.equal(isBreakDismissed('p', 'p', '2026-06-15'), false);
	assert.equal(isBreakDismissed([pref], 'p', '2026-06-15'), false);
});
