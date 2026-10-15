// Unit tests for the AI plan-request trust boundary. Run via
// `npx tsx --test apps/web/src/lib/training/plan_request/inputs.test.ts`.
//
// `validatePlanInputs` is the only thing standing between the model's tool
// call and the plan wizard, so every clamp, whitelist, default and
// assumption branch is pinned here.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { lengthLimit } from '../../core/column_limits';
import {
	DEFAULT_DAYS_PER_WEEK,
	DEFAULT_GOAL_EVENT,
	MAX_PLAN_WEEKS,
	MIN_PLAN_WEEKS,
	PLAN_REQUEST_ASSUMPTIONS,
	isoEpochDay,
	validatePlanInputs,
} from './inputs';

const TODAY = '2026-10-15';

/// A complete, sane extraction — each test perturbs one field of it.
const FULL = {
	goal_event: 'distance_half',
	race_date: '2027-03-14',
	goal_time_sec: 7140,
	recent_5k_sec: 1590,
	days_per_week: 4,
	weeks: 16,
	beginner_walk_run: false,
	plan_name: 'Sub-2 half',
};

test('a complete, sane extraction passes through unchanged with no assumptions', () => {
	assert.deepEqual(validatePlanInputs(FULL, TODAY), {
		goalEvent: 'distance_half',
		raceDate: '2027-03-14',
		goalTimeSec: 7140,
		recent5kSec: 1590,
		daysPerWeek: 4,
		weeks: 16,
		beginnerWalkRun: false,
		planName: 'Sub-2 half',
		assumptions: [],
	});
});

test('an empty extraction is all defaults, and says which were assumed', () => {
	const r = validatePlanInputs({}, TODAY);
	assert.equal(r.goalEvent, DEFAULT_GOAL_EVENT);
	assert.equal(r.daysPerWeek, DEFAULT_DAYS_PER_WEEK);
	assert.equal(r.raceDate, null);
	assert.equal(r.goalTimeSec, null);
	assert.equal(r.recent5kSec, null);
	assert.equal(r.weeks, null);
	assert.equal(r.beginnerWalkRun, false);
	assert.equal(r.planName, null);
	assert.deepEqual(r.assumptions, ['goal_event_default', 'days_per_week_default']);
});

test('never throws on junk, and junk collapses to the defaults', () => {
	for (const junk of [null, undefined, 42, 'text', [], [1, 2], true, () => 1]) {
		const r = validatePlanInputs(junk, TODAY);
		assert.equal(r.goalEvent, DEFAULT_GOAL_EVENT);
		assert.equal(r.daysPerWeek, DEFAULT_DAYS_PER_WEEK);
	}
	const hostile = validatePlanInputs(
		{
			goal_event: { toString: () => 'distance_5k' },
			race_date: 20270314,
			goal_time_sec: '7140',
			recent_5k_sec: NaN,
			days_per_week: Infinity,
			weeks: '16',
			beginner_walk_run: 'true',
			plan_name: 99,
		},
		TODAY,
	);
	assert.equal(hostile.goalEvent, DEFAULT_GOAL_EVENT);
	assert.equal(hostile.goalTimeSec, null);
	assert.equal(hostile.recent5kSec, null);
	assert.equal(hostile.daysPerWeek, DEFAULT_DAYS_PER_WEEK);
	assert.equal(hostile.weeks, null);
	assert.equal(hostile.beginnerWalkRun, false);
	assert.equal(hostile.planName, null);
	assert.equal(hostile.raceDate, null);
	assert.ok(hostile.assumptions.includes('race_date_dropped'));
});

test('goal_event is whitelisted to the four standard rungs', () => {
	for (const event of ['distance_5k', 'distance_10k', 'distance_half', 'distance_full']) {
		const r = validatePlanInputs({ goal_event: event }, TODAY);
		assert.equal(r.goalEvent, event);
		assert.ok(!r.assumptions.includes('goal_event_default'));
	}
	for (const bad of ['custom', 'distance_50k', 'half', '', null]) {
		const r = validatePlanInputs({ goal_event: bad }, TODAY);
		assert.equal(r.goalEvent, DEFAULT_GOAL_EVENT, String(bad));
		assert.ok(r.assumptions.includes('goal_event_default'));
	}
});

test('beginner_walk_run forces a 5K goal and drops any goal time', () => {
	const r = validatePlanInputs(
		{ goal_event: 'distance_full', goal_time_sec: 14_400, beginner_walk_run: true },
		TODAY,
	);
	assert.equal(r.beginnerWalkRun, true);
	assert.equal(r.goalEvent, 'distance_5k');
	assert.equal(r.goalTimeSec, null);
	assert.ok(r.assumptions.includes('beginner_5k'));
	assert.ok(!r.assumptions.includes('goal_event_default'));
	assert.ok(!r.assumptions.includes('goal_time_dropped'));
});

test('a beginner who only asked for a 5K is not told anything was assumed about it', () => {
	const asked5k = validatePlanInputs({ goal_event: 'distance_5k', beginner_walk_run: true }, TODAY);
	assert.ok(!asked5k.assumptions.includes('beginner_5k'));
	const askedNothing = validatePlanInputs({ beginner_walk_run: true }, TODAY);
	assert.equal(askedNothing.goalEvent, 'distance_5k');
	assert.ok(!askedNothing.assumptions.includes('beginner_5k'));
	assert.ok(!askedNothing.assumptions.includes('goal_event_default'));
});

test('beginner_walk_run accepts only a literal true', () => {
	for (const v of [1, 'yes', 'true', {}, null]) {
		assert.equal(validatePlanInputs({ beginner_walk_run: v }, TODAY).beginnerWalkRun, false);
	}
});

test('goal time is kept only inside the 2:30-15:00 per km pace band for its distance', () => {
	// 5K: 12:30 is 2:30/km exactly, 75:00 is 15:00/km exactly.
	assert.equal(validatePlanInputs({ goal_event: 'distance_5k', goal_time_sec: 750 }, TODAY).goalTimeSec, 750);
	assert.equal(validatePlanInputs({ goal_event: 'distance_5k', goal_time_sec: 4500 }, TODAY).goalTimeSec, 4500);
	for (const sec of [749, 4501, 0, -1800]) {
		const r = validatePlanInputs({ goal_event: 'distance_5k', goal_time_sec: sec }, TODAY);
		assert.equal(r.goalTimeSec, null, String(sec));
		assert.ok(r.assumptions.includes('goal_time_dropped'), String(sec));
	}
	// "1:45" misread as 105 seconds for a half — a 5 s/km pace.
	const misread = validatePlanInputs({ goal_event: 'distance_half', goal_time_sec: 105 }, TODAY);
	assert.equal(misread.goalTimeSec, null);
});

test('the pace band is checked against the resolved goal, including the default', () => {
	// 25:00 is a fine 5K but a 1:11/km half — the defaulted goal is a half.
	const r = validatePlanInputs({ goal_time_sec: 1500 }, TODAY);
	assert.equal(r.goalEvent, 'distance_half');
	assert.equal(r.goalTimeSec, null);
	assert.ok(r.assumptions.includes('goal_time_dropped'));
});

test('a goal time of ten hours or more is dropped — the hours field caps at 9', () => {
	// 10:00:00 for a marathon is 8:32/km, inside the pace band.
	const r = validatePlanInputs({ goal_event: 'distance_full', goal_time_sec: 36_000 }, TODAY);
	assert.equal(r.goalTimeSec, null);
	const under = validatePlanInputs({ goal_event: 'distance_full', goal_time_sec: 35_999 }, TODAY);
	assert.equal(under.goalTimeSec, 35_999);
});

test('goal time is rounded to whole seconds', () => {
	const r = validatePlanInputs({ goal_event: 'distance_10k', goal_time_sec: 3000.4 }, TODAY);
	assert.equal(r.goalTimeSec, 3000);
});

test('recent 5K is kept only inside 12:00 to 59:59', () => {
	assert.equal(validatePlanInputs({ recent_5k_sec: 720 }, TODAY).recent5kSec, 720);
	assert.equal(validatePlanInputs({ recent_5k_sec: 3599 }, TODAY).recent5kSec, 3599);
	assert.equal(validatePlanInputs({ recent_5k_sec: 1590.6 }, TODAY).recent5kSec, 1591);
	for (const sec of [719, 3600, 0, -5, 90_000]) {
		const r = validatePlanInputs({ recent_5k_sec: sec }, TODAY);
		assert.equal(r.recent5kSec, null, String(sec));
		assert.ok(r.assumptions.includes('recent_5k_dropped'), String(sec));
	}
});

test('days per week is an integer clamped to 3-7, and a clamp is an assumption', () => {
	for (const n of [3, 4, 5, 6, 7]) {
		const r = validatePlanInputs({ days_per_week: n }, TODAY);
		assert.equal(r.daysPerWeek, n);
		assert.ok(!r.assumptions.some((a) => a.startsWith('days_per_week')));
	}
	for (const [raw, want] of [
		[1, 3],
		[0, 3],
		[-2, 3],
		[9, 7],
	] as const) {
		const r = validatePlanInputs({ days_per_week: raw }, TODAY);
		assert.equal(r.daysPerWeek, want, String(raw));
		assert.ok(r.assumptions.includes('days_per_week_clamped'), String(raw));
	}
});

test('a value that is only rounded into the band is not reported as clamped', () => {
	const days = validatePlanInputs({ days_per_week: 4.6 }, TODAY);
	assert.equal(days.daysPerWeek, 5);
	assert.ok(!days.assumptions.includes('days_per_week_clamped'));
	const weeks = validatePlanInputs({ weeks: 11.6 }, TODAY);
	assert.equal(weeks.weeks, 12);
	assert.ok(!weeks.assumptions.includes('weeks_clamped'));
});

test('weeks is an integer clamped to the wizard band; a missing or non-positive value is null', () => {
	assert.equal(validatePlanInputs({ weeks: 12 }, TODAY).weeks, 12);
	assert.equal(validatePlanInputs({ weeks: 2 }, TODAY).weeks, MIN_PLAN_WEEKS);
	assert.equal(validatePlanInputs({ weeks: 52 }, TODAY).weeks, MAX_PLAN_WEEKS);
	assert.ok(validatePlanInputs({ weeks: 52 }, TODAY).assumptions.includes('weeks_clamped'));
	assert.equal(validatePlanInputs({ weeks: 10.4 }, TODAY).weeks, 10);
	assert.equal(validatePlanInputs({ weeks: 0 }, TODAY).weeks, null);
	assert.equal(validatePlanInputs({ weeks: -8 }, TODAY).weeks, null);
	assert.equal(validatePlanInputs({}, TODAY).weeks, null);
	assert.ok(!validatePlanInputs({ weeks: 12 }, TODAY).assumptions.includes('weeks_clamped'));
});

test('race date must be a real date strictly after today and at most two years out', () => {
	assert.equal(validatePlanInputs({ race_date: '2026-10-16' }, TODAY).raceDate, '2026-10-16');
	assert.equal(validatePlanInputs({ race_date: '2028-10-15' }, TODAY).raceDate, '2028-10-15');
	for (const bad of [
		'2026-10-15',
		'2026-10-14',
		'2028-10-16',
		'2027-02-31',
		'2027-3-14',
		'next March',
		'2027-03-14T09:00:00Z',
	]) {
		const r = validatePlanInputs({ race_date: bad }, TODAY);
		assert.equal(r.raceDate, null, bad);
		assert.ok(r.assumptions.includes('race_date_dropped'), bad);
	}
});

test('an omitted race date is not reported as dropped', () => {
	assert.ok(!validatePlanInputs({ race_date: null }, TODAY).assumptions.includes('race_date_dropped'));
	assert.ok(!validatePlanInputs({}, TODAY).assumptions.includes('race_date_dropped'));
});

test('an unusable today refuses every race date rather than guessing', () => {
	assert.equal(validatePlanInputs({ race_date: '2027-03-14' }, 'not-a-date').raceDate, null);
});

test('plan name is trimmed, control characters removed, and capped to the column', () => {
	assert.equal(validatePlanInputs({ plan_name: '  Spring\u0000 half\n\tplan  ' }, TODAY).planName, 'Spring half plan');
	assert.equal(validatePlanInputs({ plan_name: '   ' }, TODAY).planName, null);
	assert.equal(validatePlanInputs({ plan_name: '\u0007\u001b' }, TODAY).planName, null);
	const cap = lengthLimit('training_plans.name');
	const long = validatePlanInputs({ plan_name: 'x'.repeat(cap + 50) }, TODAY).planName;
	assert.equal(long?.length, cap);
	// Capped by code point, so an astral character is never split in half.
	const astral = validatePlanInputs({ plan_name: '\u{1F3C3}'.repeat(cap + 5) }, TODAY).planName;
	assert.equal(Array.from(astral ?? '').length, cap);
});

test('every assumption the validator can emit is in the published list', () => {
	const emitted = new Set<string>();
	for (const raw of [
		{},
		{ days_per_week: 9, weeks: 52, race_date: 'x', goal_time_sec: 1, recent_5k_sec: 1 },
		{ beginner_walk_run: true, goal_event: 'distance_full' },
	]) {
		for (const a of validatePlanInputs(raw, TODAY).assumptions) emitted.add(a);
	}
	for (const a of emitted) {
		assert.ok((PLAN_REQUEST_ASSUMPTIONS as readonly string[]).includes(a), a);
	}
	assert.equal(emitted.size, PLAN_REQUEST_ASSUMPTIONS.length);
});

test('isoEpochDay refuses rolled-over and malformed dates', () => {
	assert.equal(isoEpochDay('1970-01-02'), 1);
	assert.equal(isoEpochDay('2027-02-29'), null);
	assert.equal(isoEpochDay('2028-02-29') !== null, true);
	assert.equal(isoEpochDay(20270314), null);
});
