import { test } from 'node:test';
import assert from 'node:assert/strict';
import { currentPlanWeekIndex, planRaceCountdown } from './plan_week';

// Regression for the DST undercount (issue #338): the old code subtracted two
// local-midnight Date.getTime() values and divided by 86.4M ms. The
// 2026-03-01 → 2026-03-15 span crosses the US spring-forward on 2026-03-08, so
// in America/New_York it is 14*24h − 1h; local-ms division floored to dayIndex
// 13 → weekIndex 1 instead of the correct 14 → 2. Run under
// `TZ=America/New_York` to exercise the exact scenario; the UTC epoch-day math
// makes the result timezone-independent.
test('DST-crossing span reports the correct week (issue #338 repro)', () => {
	assert.equal(currentPlanWeekIndex('2026-03-01', '2026-03-15', 12), 2);
});

test('non-DST control span reports the correct week', () => {
	// 2026-06-01 → 2026-06-15 spans no DST transition: 14 whole days → week 2.
	assert.equal(currentPlanWeekIndex('2026-06-01', '2026-06-15', 12), 2);
});

test('day zero is week zero', () => {
	assert.equal(currentPlanWeekIndex('2026-03-01', '2026-03-01', 12), 0);
});

test('a day before the plan starts clamps to week zero', () => {
	assert.equal(currentPlanWeekIndex('2026-03-01', '2026-02-20', 12), 0);
});

test('past the last week clamps to the final week index', () => {
	assert.equal(currentPlanWeekIndex('2026-03-01', '2026-12-01', 12), 11);
});

test('a plan with no weeks yields no valid index', () => {
	// -1, not 0: weekCount - 1 underflows. Callers must guard the empty case
	// themselves — the plan-detail page and the mobile overview both return 0
	// before calling in. Mirrors the Dart twin's boundary case.
	assert.equal(currentPlanWeekIndex('2026-03-01', '2026-03-15', 0), -1);
});

test('planRaceCountdown counts down to the start before the plan begins', () => {
	assert.deepEqual(planRaceCountdown('2026-06-10', '2026-08-30', '2026-06-01'), {
		kind: 'starts_in',
		days: 9
	});
});

test('planRaceCountdown counts down to race day inside the plan', () => {
	assert.deepEqual(planRaceCountdown('2026-06-01', '2026-08-30', '2026-08-01'), {
		kind: 'race_in',
		days: 29
	});
	assert.deepEqual(planRaceCountdown('2026-06-01', '2026-08-30', '2026-08-29'), {
		kind: 'race_in',
		days: 1
	});
});

test('planRaceCountdown names race day and a race already run', () => {
	assert.deepEqual(planRaceCountdown('2026-06-01', '2026-08-30', '2026-08-30'), {
		kind: 'race_day',
		days: 0
	});
	assert.deepEqual(planRaceCountdown('2026-06-01', '2026-08-30', '2026-09-02'), {
		kind: 'race_past',
		days: 0
	});
});

test('planRaceCountdown counts whole days across a DST change', () => {
	// 2026-03-01 -> 2026-03-15 crosses the US spring-forward; local-ms
	// division would come out an hour short of 14 days.
	assert.deepEqual(planRaceCountdown('2026-01-01', '2026-03-15', '2026-03-01'), {
		kind: 'race_in',
		days: 14
	});
});
