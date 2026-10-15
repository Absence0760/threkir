import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isOffTrack, onTrackPoints } from './track_points';

// Mirrors apps/mobile_android/test/track_points_test.dart.

test('only offTrack true marks an off-track fix', () => {
	assert.equal(isOffTrack({ lat: 1, lng: 2, offTrack: true }), true);
	assert.equal(isOffTrack({ lat: 1, lng: 2, offTrack: false }), false);
	assert.equal(isOffTrack({ lat: 1, lng: 2 }), false);
	assert.equal(isOffTrack({ lat: 1, lng: 2, offTrack: 'true' }), false);
	assert.equal(isOffTrack(null), false);
});

test('onTrackPoints drops off-track fixes and keeps the order', () => {
	const track = [
		{ lat: 1, lng: 1, distM: 0 },
		{ lat: 2, lng: 2, distM: 40, offTrack: true },
		{ lat: 3, lng: 3, distM: 80, offTrack: false },
		{ lat: 4, lng: 4, distM: 120, offTrack: true },
		{ lat: 5, lng: 5, distM: 160 },
	];
	assert.deepEqual(
		onTrackPoints(track).map((p) => p.lat),
		[1, 3, 5],
	);
});

test('a track with no off-track fix is returned as it is', () => {
	const track = [{ lat: 1, lng: 1 }, { lat: 2, lng: 2 }];
	assert.equal(onTrackPoints(track), track);
	assert.deepEqual(onTrackPoints([]), []);
});

test('an all-off-track track has no line', () => {
	assert.deepEqual(onTrackPoints([{ lat: 1, lng: 1, offTrack: true }]), []);
});

// The owner's run-detail read keeps every stored point, because splits,
// moving time and heart rate read the off-track fixes too; each surface that
// draws or matches the line filters at its own call. These are the line
// readers that take the stored track straight from Storage.
test('every owner line reader goes through onTrackPoints', async () => {
	const { readFileSync } = await import('node:fs');
	const { fileURLToPath } = await import('node:url');
	const read = (rel: string) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');
	const body = (src: string, fn: string) => {
		const start = src.indexOf(`export async function ${fn}(`);
		assert.ok(start >= 0, `${fn} is gone`);
		return src.slice(start, src.indexOf('\n}\n', start));
	};
	const data = read('../core/data.ts');
	assert.match(body(data, 'fetchTrackByPath'), /onTrackPoints\(/);
	assert.match(body(data, 'fetchRoutesIntersectingTrack'), /onTrackPoints\(/);
	assert.match(read('./run_altitude.ts'), /const track = onTrackPoints\(stored\)/);
	const page = read('../../routes/runs/[id]/+page.svelte');
	assert.match(page, /: onTrackPoints\(run\?\.track \?\? \[\]\)/, 'the map line');
	assert.match(page, /onTrackPoints\(run\.track\)\.map\(/, 'the GPX download');
	assert.match(page, /track=\{onTrackPoints\(run\.track \?\? \[\]\)\}/, 'the segment efforts');
	assert.match(page, /gradePhases\(run\?\.track \? onTrackPoints\(run\.track\)/, 'the race phases');
});
