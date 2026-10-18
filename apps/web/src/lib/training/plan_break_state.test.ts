import { test } from 'node:test';
import assert from 'node:assert/strict';
import { breakState } from './plan_break_state.ts';
import { shiftIsoDate } from './plan_bulk_ops.ts';

// The plan_break pair's fixture shape: ten weeks from Sunday 2026-06-07, the
// race on the end date, week 1's long run the last thing done, today week 4's
// Tuesday, so a 22-day break from 2026-06-15.
const S = '2026-06-07';
const TODAY = shiftIsoDate(S, 30);
const phases = ['base', 'base', 'build', 'build', 'build', 'build', 'peak', 'peak', 'taper', 'race'];
const plan = { id: 'p', start_date: S, end_date: shiftIsoDate(S, 63), status: 'active', trimmed_at: null };
const weeks = phases.map((phase, i) => ({ id: `w${i}`, week_index: i, phase }));
const workouts = phases.map((phase, i) => ({
	id: `x${i}`,
	week_id: `w${i}`,
	scheduled_date: shiftIsoDate(S, 7 * i),
	kind: phase === 'race' ? 'race' : 'long',
	completed_run_id: null,
	manually_completed: i <= 1
}));
const FROM = shiftIsoDate(S, 8);

test('while the reads are in flight the state is pending and nothing shows', () => {
	assert.deepEqual(breakState(plan, weeks, workouts, TODAY, undefined), {
		pending: true,
		found: null,
		showing: false,
		window: null
	});
});

test('failed reads hide the offer and let the other cards show', () => {
	assert.deepEqual(breakState(plan, weeks, workouts, TODAY, null), {
		pending: false,
		found: null,
		showing: false,
		window: null
	});
});

test('an unanswered break shows, with its window to today', () => {
	const s = breakState(plan, weeks, workouts, TODAY, { runDatesIso: [], dismissedPref: null });
	assert.equal(s.pending, false);
	assert.equal(s.showing, true);
	assert.equal(s.found?.fromIso, FROM);
	assert.deepEqual(s.window, { fromIso: FROM, untilIso: TODAY });
});

test('an answered break stops showing but keeps its window', () => {
	const pref = { plan_id: 'p', from: FROM, until: TODAY };
	const s = breakState(plan, weeks, workouts, TODAY, { runDatesIso: [], dismissedPref: pref });
	assert.equal(s.showing, false);
	assert.deepEqual(s.window, { fromIso: FROM, untilIso: TODAY });
});

test('a malformed row hides the offer instead of throwing out of the page', () => {
	const broken = [...workouts, null] as unknown as typeof workouts;
	const s = breakState(plan, weeks, broken, TODAY, { runDatesIso: [], dismissedPref: null });
	assert.deepEqual(s, { pending: false, found: null, showing: false, window: null });
});
