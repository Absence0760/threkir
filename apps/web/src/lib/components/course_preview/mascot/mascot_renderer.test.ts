import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { mascotViewMatrix, mascotYawMatrix } from './mascot_renderer.ts';

function apply(m: Float32Array, v: [number, number, number, number]): number[] {
	return [0, 1, 2, 3].map((r) => m[r] * v[0] + m[4 + r] * v[1] + m[8 + r] * v[2] + m[12 + r] * v[3]);
}

const near = (a: number[], e: number[]) => a.forEach((x, i) => assert.ok(Math.abs(x - e[i]) < 1e-5, `${a} vs ${e}`));

test('looking straight down, his facing (-Z) is screen-up and +X is screen-right', () => {
	const view = mascotViewMatrix(0);
	near(apply(view, [0, 0, -1, 0]).slice(0, 2), [0, 1]);
	near(apply(view, [1, 0, 0, 0]).slice(0, 2), [1, 0]);
	// The ground point under his hooves is the view's centre.
	near(apply(view, [0, 0, 0, 1]).slice(0, 2), [0, 0]);
});

test('at the flyover pitch his height shows, shortened by the tilt', () => {
	const view = mascotViewMatrix(60);
	near(apply(view, [0, 1, 0, 0]).slice(0, 2), [0, Math.sin(Math.PI / 3)]);
	near(apply(view, [0, 0, -1, 0]).slice(0, 2), [0, 0.5]);
});

test('a yaw of 90 turns him to face screen-right, 180 toward the viewer', () => {
	near(apply(mascotYawMatrix(90), [0, 0, -1, 0]).slice(0, 3), [1, 0, 0]);
	near(apply(mascotYawMatrix(180), [0, 0, -1, 0]).slice(0, 3), [0, 0, 1]);
	near(apply(mascotYawMatrix(0), [0, 1, 0, 0]).slice(0, 3), [0, 1, 0]);
});
