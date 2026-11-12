// Mirrors apps/mobile_android/test/share_placement_test.dart case for case.

import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import {
	DEFAULT_SHARE_PLACEMENT,
	SHARE_PLACEMENT_MAX_SCALE,
	SHARE_PLACEMENT_MIN_SCALE,
	minSharePlacementScale,
	moveSharePlacement,
	placeShareBlock,
	resizeSharePlacement,
	sharePlacementFrame,
	sharePlacementFromJson,
	sharePlacementToJson,
} from './share_placement';

const story = sharePlacementFrame(360, 640, true);
const post = sharePlacementFrame(360, 450, false);
const near = (a: number, b: number) => assert.ok(Math.abs(a - b) < 1e-9, `${a} != ${b}`);

describe('sharePlacementFrame', () => {
	test('keeps a story clear of the bottom 13% the reply bar covers', () => {
		assert.equal(story.left, 20);
		assert.equal(story.top, 20);
		assert.equal(story.width, 320);
		near(story.top + story.height, 640 * 0.87);
	});

	test('keeps a post 22 px off its bottom edge', () => {
		assert.equal(post.width, 320);
		assert.equal(post.top + post.height, 450 - 22);
	});
});

describe('minSharePlacementScale', () => {
	test('lets 12 px labels shrink to the 6 px floor, and no further than half', () => {
		assert.equal(minSharePlacementScale(12), 0.5);
		assert.equal(minSharePlacementScale(48), SHARE_PLACEMENT_MIN_SCALE);
	});

	test('a strip already near the floor barely shrinks; one at it cannot', () => {
		near(minSharePlacementScale(12 * (320 / 560)), 6 / (12 * (320 / 560)));
		assert.equal(minSharePlacementScale(5), SHARE_PLACEMENT_MAX_SCALE);
		assert.equal(minSharePlacementScale(0), SHARE_PLACEMENT_MAX_SCALE);
	});
});

describe('placeShareBlock', () => {
	test('the default sits centred on the bottom edge of the frame', () => {
		const placed = placeShareBlock(DEFAULT_SHARE_PLACEMENT, 320, 200, 360, 640, story, 0.5);
		assert.equal(placed.left, 20);
		near(placed.top + placed.height, 640 * 0.87);
		assert.equal(placed.scale, 1);
		near(placed.placement.y, (640 * 0.87 - 100) / 640);
	});

	test('a centre inside the frame is kept as it is', () => {
		const placed = placeShareBlock({ x: 0.5, y: 0.4, scale: 0.5 }, 320, 200, 360, 640, story, 0.5);
		assert.equal(placed.left, 180 - 80);
		assert.equal(placed.top, 256 - 50);
		assert.deepEqual(placed.placement, { x: 0.5, y: 0.4, scale: 0.5 });
	});

	test('a block dragged off any edge is moved back wholly inside the frame', () => {
		for (const [x, y] of [
			[-1, 0.5],
			[2, 0.5],
			[0.5, -1],
			[0.5, 2],
		]) {
			const placed = placeShareBlock({ x, y, scale: 0.5 }, 320, 200, 360, 640, story, 0.5);
			assert.ok(placed.left >= story.left - 1e-9);
			assert.ok(placed.top >= story.top - 1e-9);
			assert.ok(placed.left + placed.width <= story.left + story.width + 1e-9);
			assert.ok(placed.top + placed.height <= story.top + story.height + 1e-9, `bottom at ${placed.top + placed.height}`);
		}
	});

	test('clamps the scale to the minimum and to what fits', () => {
		assert.equal(placeShareBlock({ x: 0.5, y: 0.5, scale: 0.1 }, 320, 200, 360, 640, story, 0.7).scale, 0.7);
		assert.equal(placeShareBlock({ x: 0.5, y: 0.5, scale: 3 }, 320, 200, 360, 640, story, 0.5).scale, 1);
		// A block taller than the frame is shrunk to fit it, under the minimum.
		near(placeShareBlock({ x: 0.5, y: 0.5, scale: 1 }, 320, 816, 360, 640, story, 0.7).scale, story.height / 816);
	});

	test('a non-finite value takes its default', () => {
		const placed = placeShareBlock({ x: NaN, y: Infinity, scale: NaN }, 160, 100, 360, 640, story, 0.5);
		assert.equal(placed.scale, 1);
		near(placed.left + placed.width / 2, 180);
		near(placed.top + placed.height, 640 * 0.87);
	});

	test('move and resize are fractions of the canvas, so they survive rasterising', () => {
		const moved = moveSharePlacement({ x: 0.5, y: 0.5, scale: 1 }, 36, -64, 360, 640);
		near(moved.x, 0.6);
		near(moved.y, 0.4);
		assert.equal(resizeSharePlacement(moved, 0.5).scale, 0.5);
		// The same fractions on the 1080 px export land three times as far.
		const logical = placeShareBlock(moved, 160, 100, 360, 640, story, 0.5);
		const exported = placeShareBlock(
			moved,
			480,
			300,
			1080,
			1920,
			{ left: story.left * 3, top: story.top * 3, width: story.width * 3, height: story.height * 3 },
			0.5,
		);
		near(exported.left, logical.left * 3);
		near(exported.top, logical.top * 3);
	});
});

describe('sharePlacementFromJson', () => {
	test('round-trips a stored placement', () => {
		const p = { x: 0.25, y: 0.75, scale: 0.6 };
		assert.deepEqual(sharePlacementFromJson(JSON.parse(JSON.stringify(sharePlacementToJson(p)))), p);
	});

	test('an unknown or out-of-range value fails closed to the default', () => {
		for (const bad of [
			null,
			'centre',
			[0.5, 0.5, 1],
			{ x: 0.5, y: 0.5 },
			{ x: '0.5', y: 0.5, scale: 1 },
			{ x: 1.5, y: 0.5, scale: 1 },
			{ x: 0.5, y: -0.1, scale: 1 },
			{ x: 0.5, y: 0.5, scale: 0.4 },
			{ x: 0.5, y: 0.5, scale: 1.2 },
		]) {
			assert.deepEqual(sharePlacementFromJson(bad), DEFAULT_SHARE_PLACEMENT, JSON.stringify(bad));
		}
	});
});
