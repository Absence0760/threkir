import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	buildFlyoverPath,
	cameraAt,
	MAX_DOT_OFFSET_PX,
	MAX_TURN_DEG_PER_S,
	maxDotOffsetM,
	pointAtDistance,
} from '#lib/routes/flyover_path.ts';
import { drawFlightFrame, flightCamera, flightPose, type FlightCamera } from './flight_frame.ts';

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

test('in an animation frame the canvas draws the camera the dot was placed for', () => {
	const map = fakeMap();
	let dot: [number, number] | null = null;
	for (const dM of [0, 120, 260, 900, 1400]) {
		map.startFrame();
		drawFlightFrame(map, { setLngLat: (at) => (dot = at) }, path, dM, VIEW, 250, true);
		const want = flightPose(path, dM, VIEW, 250);
		assert.deepEqual(map.drawn, want.camera, `frame at ${dM} m draws a stale camera`);
		assert.deepEqual(dot, want.dot);
	}
});

test('the dot is placed after the camera moves, on the course', () => {
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
	const here = pointAtDistance(path, 500);
	assert.deepEqual(dot, [here.lng, here.lat]);
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

test('the flight speed never zooms or tilts the camera, nor moves the dot', () => {
	for (const dM of [0, 900, 12_345, switchbacks.totalM]) {
		const at250 = flightPose(switchbacks, dM, VIEW, 250);
		for (const speedMps of [100, 1000, 2500]) {
			const { camera, dot } = flightPose(switchbacks, dM, VIEW, speedMps);
			assert.deepEqual([camera.pitch, camera.zoom], [at250.camera.pitch, at250.camera.zoom]);
			assert.deepEqual(dot, at250.dot);
		}
	}
	// At the start and the finish the camera is on the dot, as before the centre smoothing.
	for (const dM of [0, switchbacks.totalM]) {
		const { camera, dot } = flightPose(switchbacks, dM, VIEW, 2500);
		assert.deepEqual(camera.center, dot);
	}
});

const M_PER_DEG = 111320;

/** Ground metres from the frame centre to the dot. */
function dotOffsetM(camera: FlightCamera, dot: [number, number]): number {
	const cosLat = Math.cos((dot[1] * Math.PI) / 180);
	return Math.hypot((camera.center[0] - dot[0]) * cosLat * M_PER_DEG, (camera.center[1] - dot[1]) * M_PER_DEG);
}

test('the dot stays inside the middle of the frame at every export speed', () => {
	// 72 CSS px at zoom 14: never more than 20% of a 360 px wide view off centre.
	assert.equal(MAX_DOT_OFFSET_PX, 72);
	for (const speedMps of [250, 1054, 2500]) {
		let worst = 0;
		for (let d = 0; d <= switchbacks.totalM; d += speedMps / 30) {
			const { camera, dot } = flightPose(switchbacks, d, VIEW, speedMps);
			const bound = maxDotOffsetM(VIEW.zoom, dot[1]);
			const off = dotOffsetM(camera, dot);
			assert.ok(off < bound, `at ${d.toFixed(0)} m, ${speedMps} m/s the dot is ${off.toFixed(0)} m off centre, bound ${bound.toFixed(0)}`);
			worst = Math.max(worst, off);
		}
		assert.ok(worst > 0, 'the centre is smoothed at all');
	}
});

/** A northbound line with a pseudo-random sideways wiggle of up to ±12 m every 30 m: a traced trail. */
const wiggly = (() => {
	const pts = [];
	let seed = 7;
	for (let m = 0; m <= 50_000; m += 30) {
		seed = (seed * 16807) % 2147483647;
		const side = ((seed / 2147483647) * 2 - 1) * 12;
		pts.push({ lat: 37.4 + m / M_PER_DEG, lng: -77.6 + side / (M_PER_DEG * Math.cos((37.4 * Math.PI) / 180)), ele: null });
	}
	return buildFlyoverPath(pts);
})();

/** Worst |second difference| of the frame centre, metres per frame, over the flight. */
function centreJitterM(speedMps: number, centreOf: (d: number) => [number, number]): number {
	const fps = 30;
	const cosLat = Math.cos((37.4 * Math.PI) / 180);
	const xy = (d: number) => {
		const [lng, lat] = centreOf(d);
		return [lng * cosLat * M_PER_DEG, lat * M_PER_DEG];
	};
	let worst = 0;
	const step = speedMps / fps;
	for (let d = 2 * step + 3000; d <= wiggly.totalM - 3000; d += step) {
		const [a, b, c] = [xy(d - 2 * step), xy(d - step), xy(d)];
		worst = Math.max(worst, Math.hypot(c[0] - 2 * b[0] + a[0], c[1] - 2 * b[1] + a[1]));
	}
	return worst;
}

test('a wiggly trace no longer jolts the frame centre at a 50K export speed', () => {
	const raw = centreJitterM(2500, (d) => {
		const p = pointAtDistance(wiggly, d);
		return [p.lng, p.lat];
	});
	const smoothed = centreJitterM(2500, (d) => flightCamera(wiggly, d, VIEW, 2500).center);
	assert.ok(raw > 10, `the fixture jolts the dot ${raw.toFixed(1)} m a frame`);
	assert.ok(smoothed < 0.5, `the frame centre still jolts ${smoothed.toFixed(2)} m a frame (dot: ${raw.toFixed(1)})`);
});

test('at 250 m/s the dot moves no more than the trace wiggles, a few px at zoom 14', () => {
	let worst = 0;
	for (let d = 0; d <= 5000; d += 250 / 30) {
		const { camera, dot } = flightPose(wiggly, d, VIEW, 250);
		worst = Math.max(worst, dotOffsetM(camera, dot));
	}
	// The ±12 m wiggle is all the dot moves in the frame: 20 m is ~5 CSS px here.
	assert.ok(worst < 20, `the frame centre sits ${worst.toFixed(1)} m off the dot`);
});
