import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hasSmoothedPosition, isOffTrack, lineLat, lineLng, lineLngLat, toLinePoint, trackLine } from './track_line';

// The line position of a stored fix (docs/features/gps_distance.md § Waypoint
// fields). Mirrors packages/core_models/test/waypoint_smoothed_position_test.dart.

test('the line reads the smoothed pair when both halves are present', () => {
	const p = { lat: 1, lng: 2, smoothedLat: 1.00001, smoothedLng: 2.00002 };
	assert.equal(hasSmoothedPosition(p), true);
	assert.equal(lineLat(p), 1.00001);
	assert.equal(lineLng(p), 2.00002);
	assert.deepEqual(lineLngLat(p), [2.00002, 1.00001]);
	assert.deepEqual(toLinePoint(p), { lat: 1.00001, lng: 2.00002, smoothedLat: 1.00001, smoothedLng: 2.00002 });
	assert.equal(p.lat, 1, 'the raw fix is not altered');
});

test('a missing, half or non-finite pair falls back to the raw fix', () => {
	for (const p of [
		{ lat: 1, lng: 2 },
		{ lat: 1, lng: 2, smoothedLat: 1.00001 },
		{ lat: 1, lng: 2, smoothedLng: 2.00002 },
		{ lat: 1, lng: 2, smoothedLat: Number.NaN, smoothedLng: 2.00002 },
		{ lat: 1, lng: 2, smoothedLat: null, smoothedLng: null },
	]) {
		assert.equal(hasSmoothedPosition(p), false, JSON.stringify(p));
		assert.deepEqual(lineLngLat(p), [2, 1]);
		assert.equal(toLinePoint(p), p);
	}
});

// Off-track fixes (docs/features/gps_distance.md § Waypoint fields). Mirrors
// packages/core_models/test/waypoint_off_track_test.dart.

test('only offTrack true marks an off-track fix', () => {
	assert.equal(isOffTrack({ lat: 1, lng: 2, offTrack: true }), true);
	assert.equal(isOffTrack({ lat: 1, lng: 2, offTrack: false }), false);
	assert.equal(isOffTrack({ lat: 1, lng: 2 }), false);
	assert.equal(isOffTrack({ lat: 1, lng: 2, offTrack: 'true' }), false);
	assert.equal(isOffTrack(null), false);
});

test('trackLine drops off-track fixes and keeps the order', () => {
	const track = [
		{ lat: 1, lng: 1, distM: 0 },
		{ lat: 2, lng: 2, distM: 40, offTrack: true },
		{ lat: 3, lng: 3, distM: 80, offTrack: false },
		{ lat: 4, lng: 4, distM: 120, offTrack: true },
		{ lat: 5, lng: 5, distM: 160 },
	];
	assert.deepEqual(
		trackLine(track).map((p) => p.lat),
		[1, 3, 5],
	);
});

test('a track with no off-track fix is returned as it is', () => {
	const track = [{ lat: 1, lng: 1 }, { lat: 2, lng: 2 }];
	assert.equal(trackLine(track), track);
	assert.deepEqual(trackLine([]), []);
});

test('an all-off-track track has no line', () => {
	assert.deepEqual(trackLine([{ lat: 1, lng: 1, offTrack: true }]), []);
});

// The owner's run-detail read keeps every stored point, because splits,
// moving time and heart rate read the off-track fixes too; each surface that
// draws or matches the line filters at its own call. These are the line
// readers that take the stored track straight from Storage.
test('every owner line reader goes through trackLine', async () => {
	const { readFileSync } = await import('node:fs');
	const { fileURLToPath } = await import('node:url');
	const read = (rel: string) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');
	const body = (src: string, fn: string) => {
		const start = src.indexOf(`export async function ${fn}(`);
		assert.ok(start >= 0, `${fn} is gone`);
		return src.slice(start, src.indexOf('\n}\n', start));
	};
	const data = read('../core/data.ts');
	assert.match(body(data, 'fetchTrackByPath'), /trackLine\(/);
	assert.match(body(data, 'fetchRoutesIntersectingTrack'), /trackLine\(/);
	assert.match(read('./run_altitude.ts'), /const track = trackLine\(stored\)/);
	const page = read('../../routes/runs/[id]/+page.svelte');
	assert.match(page, /: trackLine\(run\?\.track \?\? \[\]\)/, 'the map line');
	assert.match(page, /trackLine\(run\.track\)\.map\(/, 'the GPX download');
	assert.match(page, /track=\{trackLine\(run\.track \?\? \[\]\)\}/, 'the segment efforts');
	assert.match(page, /gradePhases\(run\?\.track \? trackLine\(run\.track\)/, 'the race phases');
});
