import { test } from 'node:test';
import assert from 'node:assert/strict';

import { assignBlockers, assignCollision, firstStartAfter } from './plan_assign.ts';

const current = { name: 'Spring half', start_date: '2027-03-01', end_date: '2027-04-25' };
const queued = { name: 'Autumn full', start_date: '2027-06-01', end_date: '2027-09-26' };
const ended = { name: 'Winter base', start_date: '2027-01-01', end_date: '2027-02-28' };
const third = { name: 'Winter ultra', start_date: '2027-10-10', end_date: '2027-12-12' };

test('assignBlockers keeps every plan still ahead of today, in start order', () => {
	assert.deepEqual(assignBlockers([queued, current], '2027-03-10'), [current, queued]);
	assert.deepEqual(assignBlockers([ended, queued], '2027-03-10'), [queued]);
	assert.deepEqual(assignBlockers([current], '2027-04-25'), [current]);
	assert.deepEqual(assignBlockers([], '2027-03-10'), []);
	assert.deepEqual(assignBlockers([third, ended, queued, current], '2027-03-10'), [current, queued, third]);
});

test('firstStartAfter is the day after the last blocker, or today with none ahead', () => {
	assert.equal(firstStartAfter([current, queued], '2027-03-10'), '2027-09-27');
	assert.equal(firstStartAfter([current], '2027-03-10'), '2027-04-26');
	assert.equal(firstStartAfter([], '2027-03-10'), '2027-03-10');
	assert.equal(firstStartAfter([current, queued, third], '2027-03-10'), '2027-12-13');
});

test('assignCollision names the blocker the assigned window runs into, latest-ending first', () => {
	const fourWeeks = { start_date: '2020-01-01', end_date: '2020-01-28' };
	assert.equal(assignCollision([current, queued], fourWeeks, '2027-04-26'), null);
	assert.equal(assignCollision([current, queued], fourWeeks, '2027-04-20'), current);
	assert.equal(assignCollision([current, queued], fourWeeks, '2027-05-10'), queued);
	assert.equal(assignCollision([current, queued], { start_date: '2020-01-01', end_date: '2020-12-31' }, '2027-04-01'), queued);
	assert.equal(assignCollision([current, queued], fourWeeks, '2027-05-04'), null);
	assert.equal(assignCollision([current, queued, third], fourWeeks, '2027-12-13'), null);
	assert.equal(assignCollision([current, queued, third], fourWeeks, '2027-09-27'), third);
});
