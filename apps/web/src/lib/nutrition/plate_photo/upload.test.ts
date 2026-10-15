import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PLATE_UPLOAD_LONG_EDGE_PX, platePhotoErrorKind, uploadScale } from './upload';

test('platePhotoErrorKind maps each refusal to the state the page shows', () => {
	assert.equal(platePhotoErrorKind(401, null), 'not_authenticated');
	assert.equal(platePhotoErrorKind(403, { code: 'ai_disclosure_required' }), 'consent');
	assert.equal(platePhotoErrorKind(403, { upgrade: true }), 'pro_required');
	assert.equal(platePhotoErrorKind(403, null), 'unavailable');
	assert.equal(platePhotoErrorKind(429, null), 'rate_limited');
	assert.equal(platePhotoErrorKind(400, null), 'invalid');
	assert.equal(platePhotoErrorKind(413, null), 'invalid');
	assert.equal(platePhotoErrorKind(422, null), 'not_understood');
	assert.equal(platePhotoErrorKind(503, null), 'unavailable');
});

test('uploadScale fits the long edge and never enlarges', () => {
	assert.equal(uploadScale(4032, 3024), PLATE_UPLOAD_LONG_EDGE_PX / 4032);
	assert.equal(uploadScale(3024, 4032), PLATE_UPLOAD_LONG_EDGE_PX / 4032);
	assert.equal(uploadScale(800, 600), 1);
	assert.equal(uploadScale(0, 0), 1);
	assert.equal(uploadScale(Number.NaN, 10), 1);
});
