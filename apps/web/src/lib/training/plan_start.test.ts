import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	nextSundayIso,
	isSundayIso,
	planStartAllowedIso,
	alignPlanStartIso,
	defaultPlanStartIso,
} from './plan_start';

test('nextSundayIso is a no-op on a Sunday', () => {
	// 2026-06-07 is a Sunday.
	assert.equal(nextSundayIso('2026-06-07'), '2026-06-07');
	assert.equal(isSundayIso('2026-06-07'), true);
});

test('nextSundayIso snaps a midweek date forward to the next Sunday', () => {
	// 2026-06-03 is a Wednesday → 2026-06-07.
	assert.equal(nextSundayIso('2026-06-03'), '2026-06-07');
	assert.equal(isSundayIso('2026-06-03'), false);
});

test('nextSundayIso snaps a Saturday forward one day', () => {
	// 2026-06-06 is a Saturday → 2026-06-07.
	assert.equal(nextSundayIso('2026-06-06'), '2026-06-07');
});

test('nextSundayIso crosses a month boundary', () => {
	// 2026-06-30 is a Tuesday → 2026-07-05 (Sunday).
	assert.equal(nextSundayIso('2026-06-30'), '2026-07-05');
});

test('planStartAllowedIso exempts a walk-run plan from the Sunday rule', () => {
	// 2026-06-03 is a Wednesday, 2026-06-07 a Sunday.
	assert.equal(planStartAllowedIso('2026-06-03', true), true);
	assert.equal(planStartAllowedIso('2026-06-03', false), false);
	assert.equal(planStartAllowedIso('2026-06-07', false), true);
});

test('alignPlanStartIso keeps a walk-run start and snaps any other', () => {
	assert.equal(alignPlanStartIso('2026-06-03', true), '2026-06-03');
	assert.equal(alignPlanStartIso('2026-06-03', false), '2026-06-07');
});

test('defaultPlanStartIso starts a walk-run plan tomorrow', () => {
	// Tuesday 2026-06-30 → Wednesday 2026-07-01, across the month boundary.
	assert.equal(defaultPlanStartIso('2026-06-30', true), '2026-07-01');
});

test('defaultPlanStartIso starts any other plan on the Sunday a week or more out', () => {
	// Wednesday 2026-06-03 + 7 = Wednesday 2026-06-10 → Sunday 2026-06-14.
	assert.equal(defaultPlanStartIso('2026-06-03', false), '2026-06-14');
	// A Sunday + 7 is already a Sunday: exactly a week out, not two.
	assert.equal(defaultPlanStartIso('2026-06-07', false), '2026-06-14');
});
