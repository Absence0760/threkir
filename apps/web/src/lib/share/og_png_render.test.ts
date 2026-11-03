import { test } from 'node:test';
import assert from 'node:assert/strict';

import { OG_FALLBACK_PNG, renderOgPng } from './og_png_render';

const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47]);

test('a card that builds renders as a real PNG and logs nothing', (t) => {
	const error = t.mock.method(console, 'error', () => {});
	const png = renderOgPng('test', () => '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>');
	assert.ok(png.subarray(0, 4).equals(PNG_MAGIC));
	assert.notEqual(png, OG_FALLBACK_PNG);
	assert.equal(error.mock.callCount(), 0);
});

test('a card that fails answers with the fallback PNG and logs only the message', (t) => {
	const error = t.mock.method(console, 'error', () => {});
	const png = renderOgPng('challenge', () => {
		throw new Error('boom');
	});
	assert.equal(png, OG_FALLBACK_PNG);
	assert.deepEqual(error.mock.calls.map((c) => c.arguments), [['[og-challenge] render failed', 'boom']]);
});

test('an SVG resvg cannot parse also falls back and is logged', (t) => {
	const error = t.mock.method(console, 'error', () => {});
	assert.equal(renderOgPng('run', () => 'not svg'), OG_FALLBACK_PNG);
	assert.equal(error.mock.callCount(), 1);
	assert.equal(error.mock.calls[0].arguments[0], '[og-run] render failed');
});
