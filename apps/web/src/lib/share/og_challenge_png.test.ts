// An unfurl image must never 404: a challenge that can't be loaded, or no
// Supabase config at all, still renders the generic branded card as a PNG.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { renderChallengeOgPng } from './og_challenge_png';

const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47]);

test('renderChallengeOgPng with no config renders the generic card as a real PNG', async () => {
	const png = await renderChallengeOgPng('does-not-exist', null);
	assert.ok(Buffer.isBuffer(png));
	assert.ok(png.subarray(0, 4).equals(PNG_MAGIC));
	assert.ok(png.length > 1000, 'a rendered card, not the 1x1 last-ditch fallback');
});
