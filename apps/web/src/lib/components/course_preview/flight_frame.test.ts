import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { buildFlyoverPath, cameraAt, MAX_TURN_DEG_PER_S } from '#lib/routes/flyover_path.ts';
import { drawFlightFrame, flightCamera, type FlightCamera } from './flight_frame.ts';

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
		drawFlightFrame(map, { setLngLat: (at) => (dot = at) }, path, dM, VIEW, 250, true);
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
	drawFlightFrame(map, marker, path, 500, VIEW, 250, true);
	assert.deepEqual(map.calls, ['jumpTo', 'setLngLat', 'redraw']);
	assert.deepEqual(dot, map.drawn?.center);
});

test('outside an animation frame no extra render is forced', () => {
	const map = fakeMap();
	drawFlightFrame(map, { setLngLat: () => {} }, path, 500, VIEW, 250, false);
	assert.deepEqual(map.calls, ['jumpTo']);
});

const M_PER_DEG_LAT = 111320;

/// 50 km of 200 m legs zigzagging 60 degrees either side of north: a trail
/// ultra's switchbacks.
const switchbacks = (() => {
	const pts = [{ lat: 0, lng: 0, ele: null }];
	let north = 0;
	let east = 0;
	for (let i = 0; i < 250; i++) {
		const rad = ((i % 2 === 0 ? 60 : -60) * Math.PI) / 180;
		for (let m = 10; m <= 200; m += 10) {
			north += 10 * Math.cos(rad);
			east += 10 * Math.sin(rad);
			pts.push({ lat: north / M_PER_DEG_LAT, lng: east / M_PER_DEG_LAT, ele: null });
		}
	}
	return buildFlyoverPath(pts);
})();

function worstDegPerS(speedMps: number, fps: number): number {
	let prev = flightCamera(switchbacks, 0, VIEW, speedMps).bearing;
	let worst = 0;
	for (let d = speedMps / fps; d <= switchbacks.totalM; d += speedMps / fps) {
		const b = flightCamera(switchbacks, d, VIEW, speedMps).bearing;
		const turn = Math.abs((((b - prev) % 360) + 540) % 360 - 180);
		worst = Math.max(worst, turn * fps);
		prev = b;
	}
	return worst;
}

test('the flight camera turns at most the per-second cap at a 50K export speed', () => {
	const worst = worstDegPerS(2500, 30);
	assert.ok(worst <= MAX_TURN_DEG_PER_S + 0.5, `turned ${worst.toFixed(1)} deg/s at 2500 m/s`);
});

test('the flight camera at 250 m/s is the camera cameraAt gives for 250 m/s', () => {
	for (const dM of [0, 900, 12_345, switchbacks.totalM]) {
		const pose = cameraAt(switchbacks, dM, { speedMps: 250 });
		const cam = flightCamera(switchbacks, dM, VIEW, 250);
		assert.deepEqual([cam.center, cam.bearing], [pose.center, pose.bearing]);
		assert.deepEqual([cam.pitch, cam.zoom], [VIEW.pitch, VIEW.zoom]);
	}
});

test('the flight speed turns the camera but never moves or zooms it', () => {
	for (const dM of [0, 900, 12_345, switchbacks.totalM]) {
		const at250 = flightCamera(switchbacks, dM, VIEW, 250);
		for (const speedMps of [100, 1000, 2500]) {
			const cam = flightCamera(switchbacks, dM, VIEW, speedMps);
			assert.deepEqual([cam.center, cam.pitch, cam.zoom], [at250.center, at250.pitch, at250.zoom]);
			const pose = cameraAt(switchbacks, dM, { speedMps });
			assert.deepEqual([pose.center, pose.lookAt], [cameraAt(switchbacks, dM).center, cameraAt(switchbacks, dM).lookAt]);
		}
	}
});
