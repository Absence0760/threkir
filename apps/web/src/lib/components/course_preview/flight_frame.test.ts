import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { buildFlyoverPath } from '#lib/routes/flyover_path.ts';
import { drawFlightFrame, type FlightCamera } from './flight_frame.ts';

const VIEW = { pitch: 60, zoom: 14 };
const path = buildFlyoverPath([
	{ lat: 39.95, lng: -75.18, ele: null },
	{ lat: 39.96, lng: -75.17, ele: null },
	{ lat: 39.96, lng: -75.15, ele: null },
]);

/// MapLibre's timing, as measured in Chromium: a camera move requests a
/// render on the next requestAnimationFrame, so one made inside an animation
/// frame is drawn a frame later; `redraw` draws on the spot.
function fakeMap() {
	let camera: FlightCamera | null = null;
	let drawn: FlightCamera | null = null;
	let pending = false;
	const calls: string[] = [];
	return {
		calls,
		jumpTo(c: FlightCamera) {
			calls.push('jumpTo');
			camera = c;
			pending = true;
		},
		redraw() {
			calls.push('redraw');
			drawn = camera;
			pending = false;
		},
		startFrame() {
			if (pending) {
				drawn = camera;
				pending = false;
			}
		},
		get drawn() {
			return drawn;
		},
	};
}

test('in an animation frame the canvas draws the camera the dot was placed on', () => {
	const map = fakeMap();
	let dot: [number, number] | null = null;
	for (const dM of [0, 120, 260, 900, 1400]) {
		map.startFrame();
		drawFlightFrame(map, { setLngLat: (at) => (dot = at) }, path, dM, VIEW, true);
		assert.deepEqual(map.drawn?.center, dot, `frame at ${dM} m paints the dot off its spot`);
	}
});

test('the dot is placed after the camera moves, on the camera centre', () => {
	const map = fakeMap();
	let dot: [number, number] | null = null;
	const marker = {
		setLngLat: (at: [number, number]) => {
			map.calls.push('setLngLat');
			dot = at;
		},
	};
	drawFlightFrame(map, marker, path, 500, VIEW, true);
	assert.deepEqual(map.calls, ['jumpTo', 'setLngLat', 'redraw']);
	assert.deepEqual(dot, map.drawn?.center);
});

test('outside an animation frame no extra render is forced', () => {
	const map = fakeMap();
	drawFlightFrame(map, { setLngLat: () => {} }, path, 500, VIEW, false);
	assert.deepEqual(map.calls, ['jumpTo']);
});
