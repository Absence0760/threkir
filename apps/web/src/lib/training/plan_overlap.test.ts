import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { PlanOverlapError } from '../core/supabase_error';
import { attemptPlanCreate, canTrimOverlap, clonedPlanEndIso, overlapTrimDate } from './plan_overlap';

const before = { id: 'a', name: 'Spring', start_date: '2031-03-02', end_date: '2031-04-26' };
const after = { id: 'b', name: 'Autumn', start_date: '2031-04-20', end_date: '2031-06-01' };

test('overlapTrimDate is the day before the new start', () => {
	assert.equal(overlapTrimDate('2031-03-01'), '2031-02-28');
});

test('clonedPlanEndIso keeps the template span, across a DST change and a month end', () => {
	const template = { start_date: '2030-01-05', end_date: '2030-01-18' };
	assert.equal(clonedPlanEndIso(template, '2031-03-23'), '2031-04-05');
	assert.equal(clonedPlanEndIso(template, '2031-02-20'), '2031-03-05');
});

test('canTrimOverlap: only when every overlapped plan starts before the new one', () => {
	assert.equal(canTrimOverlap([before], '2031-04-12'), true);
	assert.equal(canTrimOverlap([before, after], '2031-04-12'), false);
	assert.equal(canTrimOverlap([before], '2031-03-02'), false);
	assert.equal(canTrimOverlap([], '2031-04-12'), false);
});

test('attemptPlanCreate returns the created value', async () => {
	let lookups = 0;
	const r = await attemptPlanCreate(async () => 'plan-1', async () => {
		lookups++;
		return [];
	});
	assert.deepEqual(r, { kind: 'created', value: 'plan-1' });
	assert.equal(lookups, 0);
});

test('attemptPlanCreate turns an overlap refusal into fresh overlaps, sorted by start', async () => {
	const r = await attemptPlanCreate(
		async () => {
			throw new PlanOverlapError();
		},
		async () => [after, before]
	);
	assert.deepEqual(r, { kind: 'overlap', overlapping: [before, after] });
});

test('attemptPlanCreate rethrows an overlap refusal with nothing left to name', async () => {
	const err = new PlanOverlapError();
	await assert.rejects(
		attemptPlanCreate(async () => {
			throw err;
		}, async () => []),
		(e) => e === err
	);
});

test('attemptPlanCreate rethrows any other failure without a lookup', async () => {
	let lookups = 0;
	await assert.rejects(
		attemptPlanCreate(
			async () => {
				throw new Error('network');
			},
			async () => {
				lookups++;
				return [before];
			}
		),
		/network/
	);
	assert.equal(lookups, 0);
});
