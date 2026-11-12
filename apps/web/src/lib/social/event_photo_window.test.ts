import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hasEventPhotoWindowOpened, isRunInEventPhotoWindow } from './event_photo_window';

const OCC = '2026-06-20T08:00:00Z';

test('a run that starts at the occurrence is inside the window', () => {
	assert.equal(isRunInEventPhotoWindow('2026-06-20T08:00:00Z', OCC), true);
});

test('the window opens exactly two hours before the occurrence', () => {
	assert.equal(isRunInEventPhotoWindow('2026-06-20T06:00:00Z', OCC), true);
	assert.equal(isRunInEventPhotoWindow('2026-06-20T05:59:59Z', OCC), false);
});

test('the window closes 24 hours after the occurrence, exclusive', () => {
	assert.equal(isRunInEventPhotoWindow('2026-06-21T07:59:59Z', OCC), true);
	assert.equal(isRunInEventPhotoWindow('2026-06-21T08:00:00Z', OCC), false);
});

test('a run from the previous month is outside the window', () => {
	assert.equal(isRunInEventPhotoWindow('2026-05-20T08:00:00Z', OCC), false);
});

test('the same instant in two renderings compares as one', () => {
	assert.equal(isRunInEventPhotoWindow('2026-06-20T09:00:00.000+01:00', OCC), true);
});

test('missing or unparseable input is outside the window', () => {
	assert.equal(isRunInEventPhotoWindow(null, OCC), false);
	assert.equal(isRunInEventPhotoWindow('2026-06-20T08:00:00Z', undefined), false);
	assert.equal(isRunInEventPhotoWindow('not a date', OCC), false);
});

test('a steward may post from two hours before the occurrence', () => {
	const occ = Date.parse(OCC);
	assert.equal(hasEventPhotoWindowOpened(OCC, occ - 2 * 3600 * 1000), true);
	assert.equal(hasEventPhotoWindowOpened(OCC, occ - 2 * 3600 * 1000 - 1), false);
	assert.equal(hasEventPhotoWindowOpened(OCC, occ + 7 * 24 * 3600 * 1000), true);
});

test('a steward window with no parseable occurrence stays shut', () => {
	assert.equal(hasEventPhotoWindowOpened(null, Date.now()), false);
	assert.equal(hasEventPhotoWindowOpened('nope', Date.now()), false);
});
