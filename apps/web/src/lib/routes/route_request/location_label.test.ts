// Run with `npx tsx --test src/lib/routes/route_request/location_label.test.ts` from apps/web.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { isCoordinateLabel, promptLocationLabel } from './location_label';

test('the labels the route builder writes for a picked or typed point are coordinates', () => {
	for (const label of ['51.5074, -0.1278', '-33.9249,18.4241', '40.7128 , -74.0060', '0, 0', '12;34']) {
		assert.equal(isCoordinateLabel(label), true, label);
	}
});

test('a place label passes, trimmed', () => {
	assert.equal(promptLocationLabel('  Hackney, London '), 'Hackney, London');
	assert.equal(promptLocationLabel('My location'), 'My location');
	assert.equal(promptLocationLabel('Route 66'), 'Route 66');
});

test('an empty or coordinate label is withheld', () => {
	for (const label of [null, undefined, '', '   ', '51.5074, -0.1278', 'start at 51.5,-0.12']) {
		assert.equal(promptLocationLabel(label), null, String(label));
	}
});
