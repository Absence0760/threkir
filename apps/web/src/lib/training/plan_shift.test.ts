import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { planShiftImpact } from './plan_shift';

const marathon = { id: 'marathon', status: 'active', start_date: '2026-08-02', end_date: '2026-11-15' };
const ultra = { id: 'ultra', start_date: '2026-11-16', end_date: '2027-06-14' };
const autumn = { id: 'autumn', start_date: '2027-08-01', end_date: '2027-10-31' };
const spring = { id: 'spring', start_date: '2026-03-01', end_date: '2026-07-25' };

test('planShiftImpact: a forward shift with room before the next plan is clear', () => {
	assert.deepEqual(planShiftImpact({ ...marathon, end_date: '2026-11-08' }, [ultra], 7), { kind: 'clear' });
});

test('planShiftImpact: a forward shift onto a queued plan offers to move every plan after it', () => {
	const r = planShiftImpact(marathon, [autumn, ultra, spring], 1);
	assert.equal(r.kind, 'following');
	assert.deepEqual(
		r.kind === 'following' ? r.following.map((p) => p.id) : [],
		['ultra', 'autumn'],
		'start order, including a later plan the new window does not reach'
	);
});

test('planShiftImpact: a backward shift onto the plan before it is blocked', () => {
	const r = planShiftImpact(marathon, [spring, ultra], -8);
	assert.equal(r.kind, 'blocked');
	assert.deepEqual(r.kind === 'blocked' ? r.blocking.map((p) => p.id) : [], ['spring']);
});

test('planShiftImpact: a backward shift that stops short of the plan before it is clear', () => {
	assert.deepEqual(planShiftImpact(marathon, [spring, ultra], -7), { kind: 'clear' });
});

test('planShiftImpact: a later plan never blocks a backward shift, an earlier one never a forward shift', () => {
	assert.deepEqual(planShiftImpact(marathon, [ultra], -30), { kind: 'clear' });
	assert.deepEqual(planShiftImpact(marathon, [spring], 30), { kind: 'clear' });
});

test('planShiftImpact: a paused plan, a zero shift and the plan itself never conflict', () => {
	assert.deepEqual(planShiftImpact({ ...marathon, status: 'paused' }, [ultra], 7), { kind: 'clear' });
	assert.deepEqual(planShiftImpact(marathon, [ultra], 0), { kind: 'clear' });
	assert.deepEqual(planShiftImpact(marathon, [marathon], 7), { kind: 'clear' });
});
