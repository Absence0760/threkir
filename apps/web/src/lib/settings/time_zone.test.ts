import { test } from 'node:test';
import assert from 'node:assert/strict';

import { timeZoneToWrite } from './time_zone.ts';

test('timeZoneToWrite writes a zone the bag does not hold yet', () => {
	assert.equal(timeZoneToWrite(undefined, 'Europe/Berlin'), 'Europe/Berlin');
	assert.equal(timeZoneToWrite(null, 'Europe/Berlin'), 'Europe/Berlin');
	assert.equal(timeZoneToWrite('Australia/Sydney', 'Europe/Berlin'), 'Europe/Berlin');
});

test('timeZoneToWrite writes nothing when the zone is unchanged or unknown', () => {
	assert.equal(timeZoneToWrite('Europe/Berlin', 'Europe/Berlin'), null);
	assert.equal(timeZoneToWrite('Europe/Berlin', null), null);
	assert.equal(timeZoneToWrite(undefined, null), null);
});

test('timeZoneToWrite treats a blank device zone as unknown', () => {
	assert.equal(timeZoneToWrite(undefined, ''), null);
	assert.equal(timeZoneToWrite('Europe/Berlin', '  '), null);
	assert.equal(timeZoneToWrite(undefined, ' Asia/Tokyo '), 'Asia/Tokyo');
});
