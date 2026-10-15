import { test } from 'node:test';
import assert from 'node:assert/strict';
import { editorZone, startFieldsFor, startIsoFor } from './event_start_fields';

// 21:30 EDT on Wednesday 21 Oct 2026.
const NY_WED = '2026-10-22T01:30:00.000Z';

test('startFieldsFor reads the start on the event clock, whatever the editor clock is', () => {
	assert.deepEqual(startFieldsFor(NY_WED, 'America/New_York'), {
		date: '2026-10-21',
		time: '21:30'
	});
	assert.deepEqual(startFieldsFor(NY_WED, 'Europe/Berlin'), { date: '2026-10-22', time: '03:30' });
});

test('an unchanged re-save in the event zone keeps the exact instant', () => {
	const zone = 'America/New_York';
	assert.equal(startIsoFor(startFieldsFor(NY_WED, zone), zone), NY_WED);
});

test('moving the time by an hour moves the instant by an hour in the event zone', () => {
	assert.equal(
		startIsoFor({ date: '2026-10-21', time: '20:30' }, 'America/New_York'),
		'2026-10-22T00:30:00.000Z'
	);
});

test('a saved reading inside a DST gap moves forward, a repeated one takes the earlier instant', () => {
	assert.equal(
		startIsoFor({ date: '2027-03-14', time: '02:30' }, 'America/New_York'),
		'2027-03-14T07:30:00.000Z'
	);
	assert.equal(
		startIsoFor({ date: '2026-11-01', time: '01:30' }, 'America/New_York'),
		'2026-11-01T05:30:00.000Z'
	);
});

test('editorZone takes a known stored zone and falls back to the editor clock otherwise', () => {
	assert.equal(editorZone('America/New_York'), 'America/New_York');
	assert.equal(editorZone(null), null);
	assert.equal(editorZone(undefined), null);
	assert.equal(editorZone('Not/AZone'), null);
});

test('with no zone the fields round-trip on the local clock', () => {
	const fields = startFieldsFor(NY_WED, null);
	assert.equal(startIsoFor(fields, null), NY_WED);
});
