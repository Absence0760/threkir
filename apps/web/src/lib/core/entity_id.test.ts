import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isEntityId } from './entity_id';

test('accepts a uuid in either case', () => {
	assert.equal(isEntityId('9f1c3a52-0000-4000-8000-000000000001'), true);
	assert.equal(isEntityId('9F1C3A52-0000-4000-8000-000000000001'), true);
});

test('rejects a club slug so an id lookup is never issued for one', () => {
	assert.equal(isEntityId('road-runners'), false);
	assert.equal(isEntityId('9f1c3a52'), false);
	assert.equal(isEntityId('9f1c3a52-0000-4000-8000-000000000001-extra'), false);
});

test('rejects empty and nullish input', () => {
	assert.equal(isEntityId(''), false);
	assert.equal(isEntityId(null), false);
	assert.equal(isEntityId(undefined), false);
});

const ID = '9f1c3a52-0000-4000-8000-000000000001';

test('rejects a uuid with anything around it, including a trailing newline', () => {
	// A URL segment can carry whitespace or a decoded %0A; Postgres refuses
	// each of these with 22P02, which is the error this guard exists to stop.
	for (const v of [` ${ID}`, `${ID} `, `${ID}\n`, `\n${ID}`, `x${ID}`, `${ID}/`]) {
		assert.equal(isEntityId(v), false, JSON.stringify(v));
	}
});

test('rejects a uuid-shaped string with a non-hex digit or a missing hyphen', () => {
	assert.equal(isEntityId('9f1c3a52-0000-4000-8000-00000000000g'), false);
	assert.equal(isEntityId('9f1c3a5200004000-8000-000000000001'), false);
	assert.equal(isEntityId('9f1c3a52_0000_4000_8000_000000000001'), false);
	assert.equal(isEntityId('{9f1c3a52-0000-4000-8000-000000000001}'), false, 'braced form is not a row id here');
});

test('accepts the nil uuid shape, which Postgres casts without error', () => {
	// The guard is about the cast, not about whether the row exists: a
	// well-formed id that matches nothing is a clean not-found.
	assert.equal(isEntityId('00000000-0000-0000-0000-000000000000'), true);
});
