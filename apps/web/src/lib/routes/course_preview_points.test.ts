import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { TrackPoint } from '../types';
import {
	CLIMB_MARKER_MAX_OFFSET_M,
	climbNamesFromMarkers,
	hasPreviewableCourse,
	routePathPoints,
	trackPreview,
} from './course_preview_points';

// 0.001 deg of latitude is ~111 m.
const LINE = [
	{ lat: 0, lng: 0, ele: 10 },
	{ lat: 0.01, lng: 0, ele: 60 },
	{ lat: 0.02, lng: 0, ele: 40 },
];

test('route waypoints keep their elevation, and a missing one reads as null', () => {
	assert.deepEqual(routePathPoints([{ lat: 1, lng: 2, ele: 30 }, { lat: 1.1, lng: 2 }]), [
		{ lat: 1, lng: 2, ele: 30 },
		{ lat: 1.1, lng: 2, ele: null },
	]);
});

test('a waypoint without a finite position is dropped, a non-finite elevation is null', () => {
	assert.deepEqual(
		routePathPoints([
			{ lat: Number.NaN, lng: 0, ele: 5 },
			{ lat: 1, lng: null, ele: 5 },
			{ lat: 1, lng: 2, ele: Number.POSITIVE_INFINITY },
			{ lat: '1', lng: 2, ele: 5 },
		]),
		[{ lat: 1, lng: 2, ele: null }],
	);
});

test('no waypoints is no path', () => {
	assert.deepEqual(routePathPoints(null), []);
	assert.deepEqual(routePathPoints(undefined), []);
	assert.deepEqual(routePathPoints([]), []);
});

test('a track flies its drawn line: the smoothed position where a fix carries one', () => {
	const track: TrackPoint[] = [
		{ lat: 0, lng: 0, ele: 10, smoothedLat: 0.0001, smoothedLng: 0.0002 },
		{ lat: 0.01, lng: 0, ele: 20 },
	] as TrackPoint[];
	assert.deepEqual(trackPreview(track, 'app').points, [
		{ lat: 0.0001, lng: 0.0002, ele: 10 },
		{ lat: 0.01, lng: 0, ele: 20 },
	]);
});

test('a track drops its off-track fixes, as the run map does', () => {
	const track = [
		{ lat: 0, lng: 0, ele: 10 },
		{ lat: 5, lng: 5, ele: 999, offTrack: true },
		{ lat: 0.01, lng: 0, ele: 20 },
	] as TrackPoint[];
	assert.deepEqual(
		trackPreview(track, 'app').points.map((p) => p.lat),
		[0, 0.01],
	);
});

test('a barometric track climbs the barometer series, and a fix without one has no elevation', () => {
	const track = [
		{ lat: 0, lng: 0, ele: 10, baroEle: 100 },
		{ lat: 0.01, lng: 0, ele: 20 },
	] as TrackPoint[];
	assert.deepEqual(
		trackPreview(track, 'app').points.map((p) => p.ele),
		[100, null],
	);
});

test('the noise band is the altitude series\' own: GPS on a phone, the route band for a barometer or an import', () => {
	const gps = [
		{ lat: 0, lng: 0, ele: 10 },
		{ lat: 0.01, lng: 0, ele: 20 },
	] as TrackPoint[];
	assert.equal(trackPreview(gps, 'app').noiseBandM, 10);
	assert.equal(trackPreview(gps, 'strava').noiseBandM, 3);
	const baro = gps.map((p) => ({ ...p, baroEle: p.ele })) as TrackPoint[];
	assert.equal(trackPreview(baro, 'app').noiseBandM, 3);
});

test('no track is no path', () => {
	assert.deepEqual(trackPreview(null), { points: [], noiseBandM: undefined });
	assert.deepEqual(trackPreview([]), { points: [], noiseBandM: undefined });
});

test('a climb marker is placed by projecting it onto the line, not by its stored position', () => {
	const names = climbNamesFromMarkers(
		[{ kind: 'climb', label: 'The Wall', lat: 0.01, lng: 0.0001 }],
		LINE,
	);
	assert.equal(names.length, 1);
	assert.equal(names[0].name, 'The Wall');
	assert.ok(Math.abs(names[0].dM - 1112) < 5, `dM ${names[0].dM}`);
});

test('only climb markers with a label name a climb, sorted along the course', () => {
	const names = climbNamesFromMarkers(
		[
			{ kind: 'climb', label: 'Second', lat: 0.015, lng: 0 },
			{ kind: 'aid_station', label: 'Aid', lat: 0.005, lng: 0 },
			{ kind: 'climb', label: '   ', lat: 0.004, lng: 0 },
			{ kind: 'climb', label: null, lat: 0.003, lng: 0 },
			{ kind: 'climb', label: ' First ', lat: 0.002, lng: 0 },
		],
		LINE,
	);
	assert.deepEqual(
		names.map((n) => n.name),
		['First', 'Second'],
	);
});

test('a climb marker off the flown line is left out', () => {
	const offset = (CLIMB_MARKER_MAX_OFFSET_M + 50) / 111_320;
	assert.deepEqual(
		climbNamesFromMarkers([{ kind: 'climb', label: 'Away', lat: 0.01, lng: offset }], LINE),
		[],
	);
});

test('a line too short to fly names no climbs', () => {
	assert.deepEqual(
		climbNamesFromMarkers([{ kind: 'climb', label: 'Hill', lat: 0, lng: 0 }], [LINE[0]]),
		[],
	);
});

test('a course is previewable only when it has length to fly', () => {
	assert.equal(hasPreviewableCourse(LINE), true);
	assert.equal(hasPreviewableCourse([]), false);
	assert.equal(hasPreviewableCourse([LINE[0]]), false);
	assert.equal(hasPreviewableCourse([LINE[0], { ...LINE[0] }]), false);
});
