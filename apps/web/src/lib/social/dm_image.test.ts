import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
	DM_IMAGE_CONTENT_TYPE,
	DM_IMAGE_MAX_BYTES,
	DM_IMAGE_MAX_EDGE,
	DM_IMAGE_STATUSES,
	dmImageFit,
	parseDmImageStatus,
} from './dm_image.ts';

const dir = fileURLToPath(new URL('../../../../backend/supabase/migrations/', import.meta.url));
const file = readdirSync(dir).find((f) => f.endsWith('_dm_images.sql'));
const sql = file ? readFileSync(dir + file, 'utf8') : '';

test('the limits are the bucket and size CHECK the migration sets', () => {
	assert.ok(file, 'the dm_images migration is missing — re-anchor');
	const bucket = sql.match(/values \('dm-images', 'dm-images', false, (\d+), array\['([^']+)'\]\)/);
	assert.ok(bucket, 'the dm-images bucket insert was not found — re-anchor');
	assert.equal(DM_IMAGE_MAX_BYTES, Number(bucket[1]));
	assert.equal(DM_IMAGE_CONTENT_TYPE, bucket[2]);
	assert.match(sql, new RegExp(`width between 1 and ${DM_IMAGE_MAX_EDGE}\\b`));
	assert.match(sql, new RegExp(`height between 1 and ${DM_IMAGE_MAX_EDGE}\\b`));
});

test('the statuses are the ones the CHECK admits', () => {
	const m = sql.match(/check \(status in \(([^)]*)\)\)/);
	assert.ok(m, 'the status CHECK was not found — re-anchor');
	assert.deepEqual([...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]), [...DM_IMAGE_STATUSES]);
	assert.equal(parseDmImageStatus('ready'), 'ready');
	assert.equal(parseDmImageStatus('rejected'), 'rejected');
	assert.equal(parseDmImageStatus('weird'), 'pending');
});

test('a photo is scaled down to the long edge and never up', () => {
	assert.deepEqual(dmImageFit(4032, 3024), { width: 2048, height: 1536 });
	assert.deepEqual(dmImageFit(3024, 4032), { width: 1536, height: 2048 });
	assert.deepEqual(dmImageFit(800, 600), { width: 800, height: 600 });
	assert.deepEqual(dmImageFit(2048, 2048), { width: 2048, height: 2048 });
	assert.deepEqual(dmImageFit(100000, 10), { width: 2048, height: 1 });
	assert.deepEqual(dmImageFit(0, 10), { width: 0, height: 0 });
	assert.deepEqual(dmImageFit(Number.NaN, 10), { width: 0, height: 0 });
});
