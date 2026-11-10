import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { Resvg } from '@resvg/resvg-js';

import { GRISNIR_BADGE_HEIGHT, GRISNIR_BADGE_PNG_BASE64, GRISNIR_BADGE_WIDTH } from './grisnir_badge_data';
import { OG_GRISNIR_HEIGHT, grisnirBadgeSvg, grisnirBadgeWidth } from './grisnir_badge';

const PNG = fileURLToPath(new URL('../../../static/brand/grisnir/grisnir-badge-256.png', import.meta.url));

test('the inlined badge is byte for byte the rendered PNG', () => {
	const png = readFileSync(PNG);
	assert.equal(GRISNIR_BADGE_PNG_BASE64, png.toString('base64'));
	assert.equal(GRISNIR_BADGE_WIDTH, png.readUInt32BE(16));
	assert.equal(GRISNIR_BADGE_HEIGHT, png.readUInt32BE(20));
});

test('the badge stays small enough to inline into every unfurl', () => {
	assert.ok(GRISNIR_BADGE_PNG_BASE64.length < 64 * 1024, `${GRISNIR_BADGE_PNG_BASE64.length} base64 chars`);
});

test('the badge keeps the render aspect at any height', () => {
	assert.equal(grisnirBadgeWidth(GRISNIR_BADGE_HEIGHT), GRISNIR_BADGE_WIDTH);
	assert.equal(grisnirBadgeWidth(OG_GRISNIR_HEIGHT), Math.round((150 * 166) / 248));
});

test('the badge renders through resvg where the image says it sits', () => {
	const w = grisnirBadgeWidth(100);
	const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">${grisnirBadgeSvg(50, 50, 100)}</svg>`;
	const img = new Resvg(svg).render();
	const px = img.pixels;
	const alpha = (x: number, y: number) => px[(y * img.width + x) * 4 + 3];
	let inside = 0;
	for (let y = 50; y < 150; y++) for (let x = 50; x < 50 + w; x++) if (alpha(x, y) > 0) inside++;
	assert.ok(inside > 0, 'the goat painted nothing');
	for (const [x, y] of [[10, 10], [190, 190], [49, 100], [50 + w + 1, 100]]) {
		assert.equal(alpha(x, y), 0, `painted outside its box at ${x},${y}`);
	}
});
