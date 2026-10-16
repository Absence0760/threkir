import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { overlappingPlans, pickCurrentPlan } from './plan_current';

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
