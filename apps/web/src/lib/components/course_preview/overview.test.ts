import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildFlyoverPath, shortestTurn } from '#lib/routes/flyover_path.ts';
import {
	finaleCamera,
	finaleDurationMs,
	finalePlan,
	ORBIT_DEG,
	OVERVIEW_PITCH,
	overviewPose,
	pathBounds,
	type CameraPose,
} from './overview.ts';

const FINISH: CameraPose = { center: [-75.18, 39.96], bearing: 120, pitch: 60, zoom: 14 };
const OVERVIEW = overviewPose({ center: [-75.17, 39.98], zoom: 11.2 });

test('the overview is north up at the lower pitch, at the fitted centre and zoom', () => {
	assert.deepEqual(OVERVIEW, { center: [-75.17, 39.98], zoom: 11.2, bearing: 0, pitch: OVERVIEW_PITCH });
	assert.ok(OVERVIEW_PITCH < 60);
});

test('the bounds the overview fits are the course corners', () => {
	const path = buildFlyoverPath([
		{ lat: 39.95, lng: -75.2, ele: null },
		{ lat: 40.01, lng: -75.15, ele: null },
		{ lat: 39.97, lng: -75.22, ele: null },
	]);
	assert.deepEqual(pathBounds(path), [
		[-75.22, 39.95],
		[-75.15, 40.01],
	]);
});

test('the ending settles within five seconds, the bound for motion that starts on its own', () => {
	assert.ok(finaleDurationMs(finalePlan(false)) <= 5000);
});

test('the ending starts on the finish pose and arrives on the overview before orbiting', () => {
	const plan = finalePlan(false);
	assert.deepEqual(finaleCamera(FINISH, OVERVIEW, 0, plan), FINISH);
	assert.deepEqual(finaleCamera(FINISH, OVERVIEW, plan.easeMs, plan), OVERVIEW);
});

test('the ease turns the short way round to north', () => {
	const plan = finalePlan(false);
	const mid = finaleCamera({ ...FINISH, bearing: 300 }, OVERVIEW, plan.easeMs / 2, plan);
	assert.equal(mid.bearing, 330);
	assert.equal(shortestTurn(300, 0), 60);
	assert.equal(shortestTurn(10, 350), -20);
	assert.equal(shortestTurn(0, 180), 180);
});

test('the orbit is bounded and holds its last pose once done', () => {
	const plan = finalePlan(false);
	const end = finaleDurationMs(plan);
	const last = finaleCamera(FINISH, OVERVIEW, end, plan);
	assert.equal(last.bearing, ORBIT_DEG);
	assert.deepEqual(last.center, OVERVIEW.center);
	assert.equal(last.pitch, OVERVIEW_PITCH);
	assert.deepEqual(finaleCamera(FINISH, OVERVIEW, end * 10, plan), last);
	for (let t = 0; t <= end; t += 50) {
		const b = finaleCamera(FINISH, OVERVIEW, t, plan).bearing;
		if (t >= plan.easeMs) assert.ok(b >= 0 && b <= ORBIT_DEG, `${t}: ${b}`);
	}
});

test('reduced motion is a direct cut to the overview with no orbit', () => {
	const plan = finalePlan(true);
	assert.equal(finaleDurationMs(plan), 0);
	assert.deepEqual(finaleCamera(FINISH, OVERVIEW, 0, plan), OVERVIEW);
});

test('a bad clock reading lands on the last pose rather than a broken camera', () => {
	const plan = finalePlan(false);
	const last = finaleCamera(FINISH, OVERVIEW, finaleDurationMs(plan), plan);
	assert.deepEqual(finaleCamera(FINISH, OVERVIEW, Number.NaN, plan), last);
	assert.deepEqual(finaleCamera(FINISH, OVERVIEW, -100, plan), FINISH);
});
