import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { buildFlyoverPath } from '#lib/routes/flyover_path.ts';
import {
	advanceTrot,
	headingWindowM,
	MAX_TROT_CYCLES_PER_S,
	MIN_HEADING_WINDOW_M,
	mascotHeadingDeg,
	mascotPhase,
	mascotWanted,
	screenYawDeg,
	TROT_CYCLES_PER_S,
	trotCyclesPerSecond,
	videoTrotPhase,
} from './mascot_motion.ts';

const near = (a: number, e: number, tol = 1e-6) => assert.ok(Math.abs(a - e) <= tol, `${a} vs ${e}`);

// About 1.1 km north, then about 0.85 km east, at 40 N.
const ELL = buildFlyoverPath([
	{ lat: 40, lng: -105, ele: null },
	{ lat: 40.01, lng: -105, ele: null },
	{ lat: 40.01, lng: -104.99, ele: null },
]);

test('the default speed trots at the model\'s own two cycles a second', () => {
	assert.equal(trotCyclesPerSecond(250), TROT_CYCLES_PER_S);
});

test('the trot quickens with the square root of the speed and stays in range', () => {
	near(trotCyclesPerSecond(500), 2 * Math.SQRT2);
	near(trotCyclesPerSecond(100), 2 * Math.sqrt(0.4));
	assert.equal(trotCyclesPerSecond(1000), MAX_TROT_CYCLES_PER_S);
	assert.equal(trotCyclesPerSecond(2500), MAX_TROT_CYCLES_PER_S);
	assert.equal(trotCyclesPerSecond(0), TROT_CYCLES_PER_S);
	assert.equal(trotCyclesPerSecond(Number.NaN), TROT_CYCLES_PER_S);
	for (const s of [1, 10, 50]) assert.ok(trotCyclesPerSecond(s) >= 1.25);
});

test('the phase accumulates with playback and wraps onto one cycle', () => {
	near(advanceTrot(0, 250, 250), 0.5);
	near(advanceTrot(0.75, 250, 250), 0.25);
	assert.equal(advanceTrot(0.3, 0, 250), 0.3);
	assert.equal(advanceTrot(0.3, -50, 250), 0.3);
	assert.equal(advanceTrot(Number.NaN, 250, 250), 0.5);
});

test('a speed change mid-flight changes the pace without jumping the legs', () => {
	const before = advanceTrot(0.1, 100, 250);
	const after = advanceTrot(before, 0, 1000);
	assert.equal(after, before);
});

test('the export phase is a function of the frame index alone', () => {
	near(videoTrotPhase(15, 30, 250), 0);
	near(videoTrotPhase(4, 30, 250), (4 / 30) * 2);
	assert.equal(videoTrotPhase(7, 30, 2500), videoTrotPhase(7, 30, 2500));
	assert.equal(videoTrotPhase(-3, 30, 250), 0);
	assert.equal(videoTrotPhase(3, 0, 250), 0);
});

test('the heading window grows with the speed and never drops under its floor', () => {
	assert.equal(headingWindowM(250), 50);
	assert.equal(headingWindowM(100), MIN_HEADING_WINDOW_M);
	assert.equal(headingWindowM(2500), 500);
	assert.equal(headingWindowM(0), 50);
});

test('he faces along the course: north on the first leg, east on the second', () => {
	near(mascotHeadingDeg(ELL, 300, 50), 0, 0.01);
	near(mascotHeadingDeg(ELL, ELL.totalM - 300, 50), 90, 0.05);
});

test('at the corner he faces between the two legs, and at the ends the chord shortens', () => {
	const corner = ELL.cumM[1];
	const h = mascotHeadingDeg(ELL, corner, 50);
	assert.ok(h > 30 && h < 60, `${h}`);
	near(mascotHeadingDeg(ELL, 0, 50), 0, 0.01);
	near(mascotHeadingDeg(ELL, ELL.totalM, 50), 90, 0.05);
});

test('a westward course reads 270, not -90', () => {
	const west = buildFlyoverPath([
		{ lat: 0, lng: 1, ele: null },
		{ lat: 0, lng: 0.99, ele: null },
	]);
	near(mascotHeadingDeg(west, 500, 50), 270, 0.01);
});

test('a course across the antimeridian keeps its heading', () => {
	const east = buildFlyoverPath([
		{ lat: 0, lng: 179.995, ele: null },
		{ lat: 0, lng: -179.995, ele: null },
	]);
	near(mascotHeadingDeg(east, east.totalM / 2, 50), 90, 0.01);
});

test('on screen his heading is taken against the map bearing', () => {
	assert.equal(screenYawDeg(90, 90), 0);
	assert.equal(screenYawDeg(0, 90), 270);
	assert.equal(screenYawDeg(350, 10), 340);
	assert.equal(screenYawDeg(10, 350), 20);
});

test('he replaces the dot only in 3D with the setting on', () => {
	assert.equal(mascotWanted(true, 'flight'), true);
	assert.equal(mascotWanted(true, 'static3d'), true);
	assert.equal(mascotWanted(true, 'flat2d'), false);
	assert.equal(mascotWanted(false, 'flight'), false);
});

test('he trots only while the flight plays, and stands under reduced motion', () => {
	assert.equal(mascotPhase('flight', true, 0.4), 0.4);
	assert.equal(mascotPhase('flight', false, 0.4), null);
	assert.equal(mascotPhase('static3d', true, 0.4), null);
});
