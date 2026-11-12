import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	currentSeason,
	isPlanFinished,
	isWorkoutMissed,
	overlappingPlans,
	pickCurrentPlan,
	plansFollowing,
	planWorkoutStatus
} from './plan_current';

const marathon = { id: 'marathon', start_date: '2026-08-02', end_date: '2026-11-15' };
const ultra = { id: 'ultra', start_date: '2026-11-16', end_date: '2027-06-14' };
const later = { id: 'later', start_date: '2027-07-01', end_date: '2027-09-30' };

test('pickCurrentPlan: the plan covering today is current, the next one upcoming', () => {
	const r = pickCurrentPlan([ultra, marathon], '2026-10-15');
	assert.equal(r.current?.id, 'marathon');
	assert.equal(r.upcoming?.id, 'ultra');
});

test('pickCurrentPlan: start and end days are inside the window', () => {
	assert.equal(pickCurrentPlan([marathon, ultra], '2026-08-02').current?.id, 'marathon');
	assert.equal(pickCurrentPlan([marathon, ultra], '2026-11-15').current?.id, 'marathon');
	assert.equal(pickCurrentPlan([marathon, ultra], '2026-11-15').upcoming?.id, 'ultra');
	const handover = pickCurrentPlan([marathon, ultra], '2026-11-16');
	assert.equal(handover.current?.id, 'ultra');
	assert.equal(handover.upcoming, null);
});

test('pickCurrentPlan: in a gap the latest-ended plan is current and the next is upcoming', () => {
	const r = pickCurrentPlan([later, marathon, ultra], '2027-06-20');
	assert.equal(r.current?.id, 'ultra');
	assert.equal(r.upcoming?.id, 'later');
});

test('pickCurrentPlan: only future plans leaves current null and picks the earliest upcoming', () => {
	const r = pickCurrentPlan([later, ultra], '2026-10-15');
	assert.equal(r.current, null);
	assert.equal(r.upcoming?.id, 'ultra');
});

test('pickCurrentPlan: only ended plans picks the latest end, no upcoming', () => {
	const r = pickCurrentPlan([marathon, ultra], '2027-08-01');
	assert.equal(r.current?.id, 'ultra');
	assert.equal(r.upcoming, null);
});

test('pickCurrentPlan: no plans yields nothing', () => {
	const r = pickCurrentPlan([], '2026-10-15');
	assert.equal(r.current, null);
	assert.equal(r.upcoming, null);
});

test('overlappingPlans: a window touching a plan on its last day overlaps', () => {
	assert.deepEqual(
		overlappingPlans([marathon, ultra], '2026-11-15', '2027-01-31').map((p) => p.id),
		['marathon', 'ultra']
	);
});

test('overlappingPlans: a window starting the day after a plan ends does not overlap it', () => {
	assert.deepEqual(
		overlappingPlans([marathon], '2026-11-16', '2027-06-14').map((p) => p.id),
		[]
	);
});

test('overlappingPlans: a window ending on a plan start day overlaps', () => {
	assert.deepEqual(
		overlappingPlans([ultra], '2026-09-01', '2026-11-16').map((p) => p.id),
		['ultra']
	);
});

test('overlappingPlans: a window inside a plan overlaps, one wholly before it does not', () => {
	assert.deepEqual(overlappingPlans([marathon], '2026-09-01', '2026-09-07').map((p) => p.id), ['marathon']);
	assert.deepEqual(overlappingPlans([marathon], '2026-07-01', '2026-08-01').map((p) => p.id), []);
});

test('plansFollowing: the anchor first, then the plans after it in date order', () => {
	const ids = plansFollowing(marathon, [later, marathon, ultra]).map((p) => p.id);
	assert.deepEqual(ids, ['marathon', 'ultra', 'later']);
});

test('plansFollowing: a plan starting on or before the anchor end is left out', () => {
	const inside = { id: 'inside', start_date: '2026-11-15', end_date: '2026-12-31' };
	const before = { id: 'before', start_date: '2026-01-01', end_date: '2026-03-01' };
	const ids = plansFollowing(marathon, [inside, before, ultra]).map((p) => p.id);
	assert.deepEqual(ids, ['marathon', 'ultra']);
});

test('currentSeason: the current plan and the plans queued behind it, never the one before', () => {
	assert.deepEqual(
		currentSeason([later, ultra, marathon], '2026-12-01').map((p) => p.id),
		['ultra', 'later']
	);
	assert.deepEqual(
		currentSeason([later, ultra, marathon], '2026-10-15').map((p) => p.id),
		['marathon', 'ultra', 'later']
	);
});

test('currentSeason: with nothing started it begins at the upcoming plan, and is empty with no plans', () => {
	assert.deepEqual(
		currentSeason([later, ultra], '2026-10-15').map((p) => p.id),
		['ultra', 'later']
	);
	assert.deepEqual(currentSeason([], '2026-10-15'), []);
});

test('isPlanFinished: an active plan is finished from the day after its end day', () => {
	const active = { ...marathon, status: 'active' };
	assert.equal(isPlanFinished(active, '2026-11-14'), false);
	assert.equal(isPlanFinished(active, '2026-11-15'), false);
	assert.equal(isPlanFinished(active, '2026-11-16'), true);
});

test('isPlanFinished: only an active plan can be finished', () => {
	for (const status of ['paused', 'completed', 'abandoned']) {
		assert.equal(isPlanFinished({ ...marathon, status }, '2027-01-01'), false, status);
	}
});

const tempo = { scheduled_date: '2026-10-13', kind: 'tempo', completed: false, skipped: false };

test('isWorkoutMissed: a workout is missed only once its day has ended', () => {
	assert.equal(isWorkoutMissed(tempo, '2026-10-12'), false);
	assert.equal(isWorkoutMissed(tempo, '2026-10-13'), false);
	assert.equal(isWorkoutMissed(tempo, '2026-10-14'), true);
});

test('isWorkoutMissed: a done or skipped workout is never missed', () => {
	assert.equal(isWorkoutMissed({ ...tempo, completed: true }, '2026-10-20'), false);
	assert.equal(isWorkoutMissed({ ...tempo, skipped: true }, '2026-10-20'), false);
});

test('isWorkoutMissed: a past rest day is not missed', () => {
	assert.equal(isWorkoutMissed({ ...tempo, kind: 'rest' }, '2026-10-20'), false);
});

test('planWorkoutStatus: done beats skipped, rest is its own state, today is upcoming', () => {
	assert.equal(planWorkoutStatus({ ...tempo, completed: true, skipped: true }, '2026-10-20'), 'done');
	assert.equal(planWorkoutStatus({ ...tempo, skipped: true }, '2026-10-01'), 'skipped');
	assert.equal(planWorkoutStatus({ ...tempo, kind: 'rest' }, '2026-10-01'), 'rest');
	assert.equal(planWorkoutStatus(tempo, '2026-10-13'), 'upcoming');
	assert.equal(planWorkoutStatus(tempo, '2026-10-14'), 'missed');
});
