// Invocation:
//   npx tsx --test src/lib/routes/flyover_capability.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { detectFlyoverCapability, flyoverMode, isLowEnd } from './flyover_capability';

test('a capable device flies', () => {
	assert.equal(flyoverMode({ webgl2: true, reducedMotion: false, lowEnd: false }), 'flight');
});

test('reduced motion keeps 3D but never flies', () => {
	assert.equal(flyoverMode({ webgl2: true, reducedMotion: true, lowEnd: false }), 'static3d');
});

test('no WebGL2 drops to the 2D map whatever else is true', () => {
	assert.equal(flyoverMode({ webgl2: false, reducedMotion: false, lowEnd: false }), 'flat2d');
	assert.equal(flyoverMode({ webgl2: false, reducedMotion: true, lowEnd: false }), 'flat2d');
});

test('a low-end device drops to the 2D map even with reduced motion', () => {
	assert.equal(flyoverMode({ webgl2: true, reducedMotion: false, lowEnd: true }), 'flat2d');
	assert.equal(flyoverMode({ webgl2: true, reducedMotion: true, lowEnd: true }), 'flat2d');
});

test('two cores or two gigabytes is low-end; more is not', () => {
	assert.equal(isLowEnd({ hardwareConcurrency: 2, deviceMemory: 8 }), true);
	assert.equal(isLowEnd({ hardwareConcurrency: 1 }), true);
	assert.equal(isLowEnd({ hardwareConcurrency: 8, deviceMemory: 2 }), true);
	assert.equal(isLowEnd({ hardwareConcurrency: 8, deviceMemory: 0.5 }), true);
	assert.equal(isLowEnd({ hardwareConcurrency: 4, deviceMemory: 4 }), false);
	assert.equal(isLowEnd({ hardwareConcurrency: 3 }), false);
});

test('a missing or zero reading is not evidence of a slow device', () => {
	assert.equal(isLowEnd({}), false);
	assert.equal(isLowEnd({ hardwareConcurrency: 0, deviceMemory: 0 }), false);
});

function fakeWindow(opts: {
	gl?: 'ok' | 'null' | 'throws';
	reduced?: boolean | 'throws';
	nav?: { hardwareConcurrency?: number; deviceMemory?: number };
	onLose?: () => void;
}): Window {
	const ctx = {
		getExtension: (name: string) =>
			name === 'WEBGL_lose_context' ? { loseContext: () => opts.onLose?.() } : null,
	};
	return {
		document: {
			createElement: () => ({
				getContext: (kind: string) => {
					assert.equal(kind, 'webgl2');
					if (opts.gl === 'throws') throw new Error('blocked');
					return opts.gl === 'null' ? null : ctx;
				},
			}),
		},
		matchMedia: (q: string) => {
			assert.equal(q, '(prefers-reduced-motion: reduce)');
			if (opts.reduced === 'throws') throw new Error('no matchMedia');
			return { matches: opts.reduced === true };
		},
		navigator: opts.nav ?? { hardwareConcurrency: 8 },
	} as unknown as Window;
}

test('detection reads WebGL2, reduced motion and the device class', () => {
	assert.deepEqual(detectFlyoverCapability(fakeWindow({ gl: 'ok', reduced: true })), {
		webgl2: true,
		reducedMotion: true,
		lowEnd: false,
	});
	assert.deepEqual(
		detectFlyoverCapability(fakeWindow({ gl: 'null', nav: { hardwareConcurrency: 2 } })),
		{ webgl2: false, reducedMotion: false, lowEnd: true },
	);
});

test('the WebGL2 probe context is released so it cannot evict the map', () => {
	let lost = 0;
	detectFlyoverCapability(fakeWindow({ gl: 'ok', onLose: () => lost++ }));
	assert.equal(lost, 1);
});

test('a throwing probe reads as unsupported rather than crashing the page', () => {
	assert.deepEqual(detectFlyoverCapability(fakeWindow({ gl: 'throws', reduced: 'throws' })), {
		webgl2: false,
		reducedMotion: false,
		lowEnd: false,
	});
});
