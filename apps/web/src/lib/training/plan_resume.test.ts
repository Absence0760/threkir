import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resumeShift } from './plan_resume.ts';

const base = { startIso: '2026-06-01', weekCount: 12 };

test('paused in week 2, resumed three weeks later: weeks 3 on move back three weeks', () => {
	assert.deepEqual(resumeShift({ ...base, pausedOnIso: '2026-06-17', todayIso: '2026-07-08' }), {
		fromWeekIndex: 3,
		weeks: 3
	});
});

test('paused and resumed inside the same plan week offers nothing', () => {
	assert.equal(resumeShift({ ...base, pausedOnIso: '2026-06-15', todayIso: '2026-06-20' }), null);
});

test('resumed in the very next plan week moves the rest back one week', () => {
	assert.deepEqual(resumeShift({ ...base, pausedOnIso: '2026-06-20', todayIso: '2026-06-22' }), {
		fromWeekIndex: 3,
		weeks: 1
	});
});

test('a pause before the plan started, or an unknown pause date, offers nothing', () => {
	assert.equal(resumeShift({ ...base, pausedOnIso: '2026-05-20', todayIso: '2026-06-22' }), null);
	assert.equal(resumeShift({ ...base, pausedOnIso: null, todayIso: '2026-06-22' }), null);
});

test('a pause in the last week has no later week to move', () => {
	assert.equal(resumeShift({ ...base, pausedOnIso: '2026-08-18', todayIso: '2026-09-15' }), null);
});

test('a very long pause is capped at 52 weeks', () => {
	assert.deepEqual(resumeShift({ ...base, pausedOnIso: '2026-06-02', todayIso: '2028-06-02' }), {
		fromWeekIndex: 1,
		weeks: 52
	});
});

test('an unreadable date offers nothing rather than reading as week 0', () => {
	assert.equal(resumeShift({ ...base, pausedOnIso: 'not-a-date', todayIso: '2026-07-08' }), null);
});
