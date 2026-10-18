import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	alignRestartStartIso,
	defaultRestartStartIso,
	isWalkRunPlan,
	restartedDateIso,
	restartStartAllowed,
	upcomingRaceIso
} from './plan_restart.ts';

const wo = (kind: string, scheduled_date: string) => ({ kind, scheduled_date });

test('isWalkRunPlan: walk-run, rest and race days with a walk-run', () => {
	assert.equal(isWalkRunPlan([wo('walk_run', '2026-01-01'), wo('rest', '2026-01-02'), wo('race', '2026-01-03')]), true);
});
test('isWalkRunPlan: false with any other kind', () => {
	assert.equal(isWalkRunPlan([wo('walk_run', '2026-01-01'), wo('easy', '2026-01-02')]), false);
});
test('isWalkRunPlan: false with no walk-run at all', () => {
	assert.equal(isWalkRunPlan([wo('rest', '2026-01-01')]), false);
});

test('upcomingRaceIso: null when every race is behind', () => {
	assert.equal(upcomingRaceIso([wo('race', '2026-10-01'), wo('easy', '2026-11-01')], '2026-10-18'), null);
});
test('upcomingRaceIso: a race today is ahead', () => {
	assert.equal(upcomingRaceIso([wo('race', '2026-10-18')], '2026-10-18'), '2026-10-18');
});
test('upcomingRaceIso: the earliest race ahead', () => {
	assert.equal(
		upcomingRaceIso([wo('race', '2026-12-01'), wo('race', '2026-11-01'), wo('race', '2026-09-01')], '2026-10-18'),
		'2026-11-01'
	);
});
test('upcomingRaceIso: an unreadable date is ignored', () => {
	assert.equal(upcomingRaceIso([wo('race', 'soon')], '2026-10-18'), null);
});

test('alignRestartStartIso: a date on the source weekday stays', () => {
	assert.equal(alignRestartStartIso('2026-10-25', '2026-03-01', false), '2026-10-25');
});
test('alignRestartStartIso: snaps forward to the source weekday', () => {
	assert.equal(alignRestartStartIso('2026-10-20', '2026-03-01', false), '2026-10-25');
});
test('alignRestartStartIso: a walk-run plan is left alone', () => {
	assert.equal(alignRestartStartIso('2026-10-20', '2026-03-01', true), '2026-10-20');
});
test('alignRestartStartIso: a source after the picked date', () => {
	assert.equal(alignRestartStartIso('2026-10-20', '2027-01-06', false), '2026-10-21');
});

test('defaultRestartStartIso: the source weekday at least a week out', () => {
	assert.equal(defaultRestartStartIso('2026-03-01', '2026-10-18', false), '2026-10-25');
	assert.equal(defaultRestartStartIso('2026-03-01', '2026-10-19', false), '2026-11-01');
});
test('defaultRestartStartIso: a Wednesday-anchored plan', () => {
	assert.equal(defaultRestartStartIso('2026-03-04', '2026-10-18', false), '2026-10-28');
});
test('defaultRestartStartIso: tomorrow for a walk-run plan', () => {
	assert.equal(defaultRestartStartIso('2026-03-04', '2026-10-18', true), '2026-10-19');
});

test('restartStartAllowed: refuses a date before today', () => {
	assert.equal(restartStartAllowed('2026-10-11', '2026-03-01', '2026-10-18', false), false);
});
test('restartStartAllowed: today on the source weekday', () => {
	assert.equal(restartStartAllowed('2026-10-18', '2026-03-01', '2026-10-18', false), true);
});
test('restartStartAllowed: another weekday only for walk-run', () => {
	assert.equal(restartStartAllowed('2026-10-20', '2026-03-01', '2026-10-18', false), false);
	assert.equal(restartStartAllowed('2026-10-20', '2026-03-01', '2026-10-18', true), true);
});
test('restartStartAllowed: refuses an unreadable date', () => {
	assert.equal(restartStartAllowed('', '2026-03-01', '2026-10-18', true), false);
});

test('restartedDateIso: moves a date by the start offset', () => {
	assert.equal(restartedDateIso('2026-05-24', '2026-03-01', '2026-10-25'), '2027-01-17');
});
test('restartedDateIso: an unreadable start keeps the date', () => {
	assert.equal(restartedDateIso('2026-05-24', 'x', '2026-10-25'), '2026-05-24');
});
