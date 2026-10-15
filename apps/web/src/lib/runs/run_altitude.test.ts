import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { TrackPoint } from '../types';
import {
	computeRunElevationGain,
	ELEVATION_GAIN_GPS_MIN_DELTA_M,
	hasBarometricAltitude,
	runAltitude,
} from './run_altitude';
import { ELEVATION_GAIN_MIN_DELTA_M } from '../routes/route_simplify';

// Twin of apps/mobile_android/test/run_altitude_test.dart; keep the cases in
// lockstep.

const pt = (i: number, ele?: number, baroEle?: number): TrackPoint => ({
	lat: 47.37,
	lng: 8.54 + i * 0.0001,
	...(ele != null ? { ele } : {}),
	...(baroEle != null ? { baroEle } : {}),
});

/** GPS altitude wandering 8 m up and back down, three times: no real climb. */
const gpsWander = [400, 408, 400, 408, 400, 408, 400].map((e, i) => pt(i, e));

test('runAltitude — a phone run without a barometer is gated at the GPS band', () => {
	assert.equal(ELEVATION_GAIN_GPS_MIN_DELTA_M, 10);
	assert.equal(runAltitude(gpsWander, 'app').minDeltaM, ELEVATION_GAIN_GPS_MIN_DELTA_M);
	assert.equal(computeRunElevationGain(gpsWander, 'app'), 0);
	const climb = [400, 411, 422, 433].map((e, i) => pt(i, e));
	assert.equal(computeRunElevationGain(climb, 'app'), 33);
});

test('runAltitude — an import keeps the route band', () => {
	for (const source of ['strava', 'garmin', 'watch', null, undefined]) {
		assert.equal(runAltitude(gpsWander, source).minDeltaM, ELEVATION_GAIN_MIN_DELTA_M);
		assert.equal(computeRunElevationGain(gpsWander, source), 24);
	}
});

test('runAltitude — a barometric series wins over GPS at the route band', () => {
	const track = [
		pt(0, 400, 300),
		pt(1, 430, 303),
		pt(2, 380, 306),
		pt(3, 425, 309),
	];
	const alt = runAltitude(track, 'app');
	assert.equal(alt.barometric, true);
	assert.equal(alt.minDeltaM, ELEVATION_GAIN_MIN_DELTA_M);
	assert.deepEqual(
		alt.track.map((p) => p.ele),
		[300, 303, 306, 309],
	);
	assert.equal(computeRunElevationGain(track, 'app'), 9);
});

test('runAltitude — a realistic barometric hill reads its climb where GPS altitude overstates it', () => {
	// Up 40 m, down 20, up 20 over 81 fixes: 60 m of real climb. The barometer
	// jitters 0.4 m; GPS altitude sits 100 m off it and wanders 16 m over
	// twenty-fix stretches.
	const hill = (i: number) => (i <= 40 ? i : i <= 60 ? 80 - i : i - 40);
	const track: TrackPoint[] = [];
	const gpsOnly: TrackPoint[] = [];
	for (let i = 0; i <= 80; i++) {
		const baro = 300 + hill(i) + ((i % 3) - 1) * 0.4;
		const gps = baro + 100 + (i % 20 < 10 ? 8 : -8);
		track.push(pt(i, gps, baro));
		gpsOnly.push(pt(i, gps));
	}
	assert.equal(runAltitude(track, 'app').barometric, true);
	assert.ok(Math.abs(computeRunElevationGain(track, 'app') - 57) < 1e-9);
	assert.ok(Math.abs(computeRunElevationGain(gpsOnly, 'app') - 77.8) < 1e-9);
});

test('runAltitude — a point without a barometric reading is a dropout, not a GPS splice', () => {
	const track = [pt(0, 400, 300), pt(1, 480), pt(2, 490), pt(3, 400, 305)];
	const alt = runAltitude(track, 'app');
	assert.equal(alt.track[1].ele, undefined);
	assert.equal(alt.track[2].ele, undefined);
	assert.equal(computeRunElevationGain(track, 'app'), 5);
});

test('runAltitude — without a barometer the track is the input, untouched', () => {
	const alt = runAltitude(gpsWander, 'app');
	assert.equal(alt.track, gpsWander);
	assert.equal(alt.barometric, false);
	const baro = runAltitude([pt(0, 400, 300)], 'app').track[0];
	assert.equal(baro.lat, 47.37);
	assert.equal(baro.lng, 8.54);
	assert.equal(baro.baroEle, 300);
});

test('hasBarometricAltitude — a non-finite reading is no reading', () => {
	assert.equal(hasBarometricAltitude([]), false);
	assert.equal(hasBarometricAltitude(gpsWander), false);
	assert.equal(hasBarometricAltitude([pt(0, 400, Number.NaN)]), false);
	assert.equal(hasBarometricAltitude([pt(0, 400), pt(1, undefined, 0)]), true);
});
