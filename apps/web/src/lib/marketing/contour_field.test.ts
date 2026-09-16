import { test } from 'node:test';
import assert from 'node:assert/strict';
import { contourPaths, heightAt } from './contour_field';

// The brand canvas renders these paths straight into the DOM, so a malformed
// `d` is a visible marketing defect rather than a caught exception — and
// because the whole claim of the module is "this is real topography, not
// concentric ovals", the topology is what the tests are about.

const BOX = { width: 760, height: 900 };

test('the field is deterministic and finite everywhere in the unit square', () => {
	// No RNG, no time, no locale: a committed component can only be honest
	// about its own output if the generator returns the same thing forever.
	for (let i = 0; i <= 20; i++) {
		for (let j = 0; j <= 20; j++) {
			const h = heightAt(i / 20, j / 20);
			assert.ok(Number.isFinite(h), `heightAt(${i / 20}, ${j / 20}) = ${h}`);
			assert.equal(h, heightAt(i / 20, j / 20), 'the same point must give the same height');
		}
	}
});

test('every emitted path is well-formed SVG path data', () => {
	for (const d of contourPaths(BOX)) {
		assert.match(d, /^M[\d.]+ [\d.]+(L[\d.]+ [\d.]+)+Z?/, `malformed: ${d.slice(0, 60)}…`);
		assert.doesNotMatch(d, /NaN|Infinity|undefined/, 'a non-finite coordinate reached the path');
	}
});

test('no coordinate escapes the box it was traced in', () => {
	// Marching squares can only emit points on cell edges, so an out-of-box
	// coordinate means the interpolation is wrong — which shows up as a line
	// shooting off the canvas rather than as an error.
	for (const d of contourPaths(BOX)) {
		for (const [, xs, ys] of d.matchAll(/([\d.]+) ([\d.]+)/g)) {
			const x = Number(xs);
			const y = Number(ys);
			assert.ok(x >= 0 && x <= BOX.width, `x ${x} outside 0..${BOX.width}`);
			assert.ok(y >= 0 && y <= BOX.height, `y ${y} outside 0..${BOX.height}`);
		}
	}
});

test('the contours are terrain, not concentric rings', () => {
	// The property that separates a traced height field from a hand-drawn set
	// of ovals: some level must enclose BOTH summits as one loop while a
	// higher level separates them into two. That is a saddle, and it is the
	// only reason this module exists rather than a `for` loop over ellipses.
	const subpaths = contourPaths(BOX).map((d) => (d.match(/M/g) ?? []).length);
	assert.ok(subpaths.length >= 6, `too few levels traced: ${subpaths.length}`);
	assert.ok(
		subpaths.some((n) => n === 1),
		'no level encloses the whole massif as one loop',
	);
	assert.ok(
		subpaths.some((n) => n >= 2),
		'no level splits into separate summits — this is a pile of rings, not a landscape',
	);
	// And the split has to happen ABOVE the single loop, not below it: water
	// runs downhill, so the coarse levels are the big ones.
	const firstSplit = subpaths.findIndex((n) => n >= 2);
	assert.ok(
		subpaths.slice(0, firstSplit).every((n) => n === 1),
		'a level below the saddle should still be one loop',
	);
});

test('a level above the highest ground is dropped rather than emitted empty', () => {
	// The peak is ~1.21, so nothing crosses 3. An empty `d` would render as a
	// stray <path> element and break `paths.length` as "contours that exist".
	assert.deepEqual(contourPaths({ ...BOX, levels: [3] }), []);
	assert.equal(contourPaths({ ...BOX, levels: [0.5] }).length, 1);
});

test('the traced box is the box asked for, at any aspect', () => {
	// The pane passes a portrait box and the band a wide one, so the same
	// terrain is cropped two ways. A generator that ignored the aspect would
	// show the band a squashed copy of the pane.
	const wide = contourPaths({ width: 760, height: 230 });
	assert.ok(wide.length >= 6, 'the wide crop traced almost nothing');
	const ys = [...wide.join('').matchAll(/[\d.]+ ([\d.]+)/g)].map((m) => Number(m[1]));
	assert.ok(Math.max(...ys) <= 230, 'the wide crop emitted a portrait coordinate');
	assert.ok(Math.max(...ys) > 115, 'the wide crop only used its top half');
});
