import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	SKETCH_MAX_ASPECT,
	SKETCH_MIN_ASPECT,
	sketchAspect,
	startMeetsFinish,
	trackBoundsAspect,
} from './course_sketch.js';
import type { TrackPoint } from '../types.js';

const pt = (lat: number, lng: number) => ({ lat, lng }) as TrackPoint;

test('an equal-distance square at 60 degrees north reads as square', () => {
	// At 60 N a degree of longitude is half a degree of latitude.
	const a = trackBoundsAspect([pt(60, 0), pt(60.01, 0.02)]);
	assert.ok(a != null && Math.abs(a - 1) < 0.01, `got ${a}`);
});

test('an east-west course is wider than tall', () => {
	const a = trackBoundsAspect([pt(0, 0), pt(0.01, 0.03)]);
	assert.ok(a != null && Math.abs(a - 3) < 0.01, `got ${a}`);
});

test('fewer than two points or a single repeated fix has no aspect', () => {
	assert.equal(trackBoundsAspect([]), null);
	assert.equal(trackBoundsAspect([pt(1, 1)]), null);
	assert.equal(trackBoundsAspect([pt(1, 1), pt(1, 1)]), null);
});

test('a course across the antimeridian spans its own width, not the globe', () => {
	const a = trackBoundsAspect([pt(0, 179.99), pt(0.01, -179.99)]);
	assert.ok(a != null && Math.abs(a - 2) < 0.01, `got ${a}`);
});

test('the sketch box clamps the route aspect to the band', () => {
	assert.equal(sketchAspect([pt(0, 0), pt(0.01, 0.05)]), SKETCH_MAX_ASPECT);
	assert.equal(sketchAspect([pt(0, 0), pt(0.05, 0.01)]), SKETCH_MIN_ASPECT);
	const mid = sketchAspect([pt(0, 0), pt(0.01, 0.015)]);
	assert.ok(Math.abs(mid - 1.5) < 0.01, `got ${mid}`);
});

test('a due-east line with no height takes the widest box', () => {
	assert.equal(sketchAspect([pt(0, 0), pt(0, 0.01)]), SKETCH_MAX_ASPECT);
	assert.equal(sketchAspect([]), SKETCH_MAX_ASPECT);
});

test('a loop shares one marker; a point-to-point course gets two', () => {
	assert.equal(startMeetsFinish([{ x: 10, y: 10 }, { x: 50, y: 50 }, { x: 12, y: 11 }], 4), true);
	assert.equal(startMeetsFinish([{ x: 10, y: 10 }, { x: 50, y: 50 }], 4), false);
});
