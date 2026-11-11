import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { parseGlb, type GlbChannel } from './glb.ts';
import { cycleTime, fromTrs, identity, invert, jointMatrices, multiply, sampleChannel, skinVertex } from './skeleton.ts';

const GLB = fileURLToPath(new URL('../../../../../static/brand/grisnir/grisnir-trot.glb', import.meta.url));
const b = readFileSync(GLB);
const model = parseGlb(b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength));

function close(a: ArrayLike<number>, e: ArrayLike<number>, tol = 1e-5) {
	assert.equal(a.length, e.length);
	for (let i = 0; i < a.length; i++) assert.ok(Math.abs(a[i] - e[i]) <= tol, `[${i}] ${a[i]} vs ${e[i]}`);
}

function bounds(t: number | null) {
	const J = jointMatrices(model, t);
	const lo = [Infinity, Infinity, Infinity];
	const hi = [-Infinity, -Infinity, -Infinity];
	for (let v = 0; v < model.vertexCount; v++) {
		const p = skinVertex(model, J, v);
		for (let c = 0; c < 3; c++) {
			lo[c] = Math.min(lo[c], p[c]);
			hi[c] = Math.max(hi[c], p[c]);
		}
	}
	return { lo, hi };
}

test('a TRS matrix times its inverse is the identity', () => {
	const q = [0.2, -0.3, 0.1, 0.927];
	const n = Math.hypot(...q);
	const m = fromTrs([1, 2, 3], q.map((x) => x / n), [2, 2, 2]);
	close(multiply(m, invert(m)), identity());
});

test('a quarter turn about Y carries +X to -Z', () => {
	const s = Math.SQRT1_2;
	const m = fromTrs([0, 0, 0], [0, s, 0, s], [1, 1, 1]);
	close([m[0], m[1], m[2]], [0, 0, -1]);
});

test('a linear channel interpolates and holds at its ends; a step channel holds the earlier key', () => {
	const ch: GlbChannel = {
		node: 0,
		path: 'translation',
		interpolation: 'LINEAR',
		times: Float32Array.from([0, 1]),
		values: Float32Array.from([0, 0, 0, 2, 4, 6]),
		width: 3,
	};
	const out = new Float32Array(3);
	sampleChannel(ch, 0.5, out);
	close(out, [1, 2, 3]);
	sampleChannel(ch, -1, out);
	close(out, [0, 0, 0]);
	sampleChannel(ch, 9, out);
	close(out, [2, 4, 6]);
	sampleChannel({ ...ch, interpolation: 'STEP' }, 0.99, out);
	close(out, [0, 0, 0]);
});

test('a rotation channel takes the short way round', () => {
	const s = Math.SQRT1_2;
	// +90 deg and -270 deg about Y are one orientation with opposite signs.
	const ch: GlbChannel = {
		node: 0,
		path: 'rotation',
		interpolation: 'LINEAR',
		times: Float32Array.from([0, 1]),
		values: Float32Array.from([0, 0, 0, 1, 0, -s, 0, -s]),
		width: 4,
	};
	const out = new Float32Array(4);
	sampleChannel(ch, 0.5, out);
	const half = Math.sin(Math.PI / 8);
	close(out, [0, half, 0, Math.cos(Math.PI / 8)], 1e-4);
});

test('the cycle time wraps any phase onto one loop', () => {
	assert.equal(cycleTime(0, 0.5), 0);
	assert.equal(cycleTime(0.5, 0.5), 0.25);
	assert.equal(cycleTime(1.25, 0.5), 0.125);
	assert.equal(cycleTime(-0.25, 0.5), 0.375);
	assert.equal(cycleTime(Number.NaN, 0.5), 0);
});

test('the rest pose stands on the ground at the origin, a goat in size', () => {
	const { lo, hi } = bounds(null);
	assert.ok(Math.abs(lo[1]) < 0.02, `lowest point ${lo[1]}`);
	assert.ok(hi[1] > 1 && hi[1] < 1.6, `height ${hi[1]}`);
	// He faces -Z: the head (and the box's longer reach) is on that side.
	assert.ok(-lo[2] > hi[2], `front ${lo[2]} back ${hi[2]}`);
	assert.ok(Math.abs(lo[0] + hi[0]) < 0.05, 'left-right symmetric');
});

test('the trot moves his legs and loops: the last key is the first', () => {
	const J0 = jointMatrices(model, 0);
	const Jh = jointMatrices(model, 0.25);
	const Jend = jointMatrices(model, 0.5);
	close(Jend, J0, 1e-3);
	let moved = 0;
	for (let v = 0; v < model.vertexCount; v++) {
		const a = skinVertex(model, J0, v);
		const c = skinVertex(model, Jh, v);
		moved = Math.max(moved, Math.hypot(a[0] - c[0], a[1] - c[1], a[2] - c[2]));
	}
	assert.ok(moved > 0.1, `largest move half a cycle apart ${moved}`);
	for (const t of [0, 0.1, 0.25, 0.4]) {
		const { lo } = bounds(t);
		assert.ok(lo[1] > -0.05, `t=${t} sinks to ${lo[1]}`);
	}
});
