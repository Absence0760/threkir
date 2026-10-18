import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	STARTER_PLANS,
	starterById,
	instantiateStarter,
	starterSummary
} from './starter_plans';
import { GOAL_DISTANCES_M, walkRunDefaultWeeks } from './training';

test('STARTER_PLANS catalogue has the expected presets', () => {
	const ids = STARTER_PLANS.map((s) => s.id);
	assert.deepEqual(ids, ['c25k', 'half_12wk', 'marathon_16wk']);
});

test('starterById finds a preset and returns undefined for an unknown id', () => {
	assert.equal(starterById('marathon_16wk')?.goalEvent, 'distance_full');
	assert.equal(starterById('nope'), undefined);
});

test('instantiateStarter returns null for an unknown id', () => {
	assert.equal(instantiateStarter('nope', '2026-07-01'), null);
});

test('C25K starter is a walk-run plan over the full progression', () => {
	const plan = instantiateStarter('c25k', '2026-07-01');
	assert.ok(plan);
	assert.equal(plan!.weeks.length, walkRunDefaultWeeks());
	assert.equal(plan!.goalDistanceM, GOAL_DISTANCES_M.distance_5k);
	const kinds = plan!.weeks.flatMap((w) => w.workouts.map((x) => x.kind));
	assert.ok(kinds.includes('walk_run'), 'C25K should produce walk_run workouts');
});

test('half-marathon starter is 12 weeks at the half distance', () => {
	const plan = instantiateStarter('half_12wk', '2026-07-01');
	assert.ok(plan);
	assert.equal(plan!.weeks.length, 12);
	assert.equal(plan!.goalDistanceM, GOAL_DISTANCES_M.distance_half);
});

test('marathon starter is 16 weeks at the full distance', () => {
	const plan = instantiateStarter('marathon_16wk', '2026-07-01');
	assert.ok(plan);
	assert.equal(plan!.weeks.length, 16);
	assert.equal(plan!.goalDistanceM, GOAL_DISTANCES_M.distance_full);
});

test('an instantiated starter anchors at the given start date', () => {
	const plan = instantiateStarter('half_12wk', '2026-07-01');
	assert.ok(plan);
	// 12 weeks from 2026-07-01 → end date is in the future, after the start.
	assert.ok(plan!.endDate > '2026-07-01');
});

test('starterSummary describes C25K as 9 weeks, 3 days a week, 30-45 minute sessions', () => {
	// The shortest session is week 1 (28.5 min) and the longest week 7
	// (44 min), each rounded to the nearest 5. The graduation 5K lasts as
	// long as the runner takes, so it does not stretch the range.
	assert.deepEqual(starterSummary('c25k'), {
		weeks: 9,
		daysPerWeek: 3,
		sessionMinutes: { min: 30, max: 45 }
	});
});

test('starterSummary gives a distance-based starter no session length', () => {
	assert.deepEqual(starterSummary('half_12wk'), { weeks: 12, daysPerWeek: 4, sessionMinutes: null });
	assert.equal(starterSummary('nope'), null);
});
