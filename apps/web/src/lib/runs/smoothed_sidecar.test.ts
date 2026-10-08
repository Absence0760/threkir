import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
	mergeSmoothedSidecar,
	needsSmoothedSidecar,
	sha256Hex,
	sidecarNamedFor,
	smoothedSidecarPath,
} from './smoothed_sidecar';

// Replays fixtures/smoothed_sidecar_vectors.json, shared with the Deno
// (`_shared/smoothed_sidecar.test.ts`) and Dart
// (`packages/api_client/test/smoothed_sidecar_test.dart`) readers and the Go
// writer (`apps/job_worker/internal/smoothed_sidecar_test.go`).

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE = JSON.parse(
	readFileSync(join(__dirname, '..', '..', '..', '..', '..', 'fixtures', 'smoothed_sidecar_vectors.json'), 'utf-8'),
) as {
	version: number;
	trackJson: string;
	sha256: string;
	cases: { name: string; sidecar: unknown; expected: ([number, number] | null)[] }[];
};

type Point = { lat: number; lng: number; smoothedLat?: number | null; smoothedLng?: number | null };

test('the fixture is for sidecar version 1 and holds cases', () => {
	assert.equal(FIXTURE.version, 1);
	assert.ok(FIXTURE.cases.length > 0);
});

test('the track fingerprint is the SHA-256 of the decompressed bytes, lower-case hex', async () => {
	assert.equal(await sha256Hex(new TextEncoder().encode(FIXTURE.trackJson)), FIXTURE.sha256);
});

for (const c of FIXTURE.cases) {
	test(`merge: ${c.name}`, () => {
		const points = JSON.parse(FIXTURE.trackJson) as Point[];
		const raw = points.map((p) => [p.lat, p.lng]);
		const merged = mergeSmoothedSidecar(points, c.sidecar, { points: points.length, sha256: FIXTURE.sha256 });
		assert.equal(merged.length, c.expected.length);
		merged.forEach((p, i) => {
			assert.deepEqual([p.lat, p.lng], raw[i], `waypoint ${i}: raw lat/lng must never change`);
			const got =
				typeof p.smoothedLat === 'number' && typeof p.smoothedLng === 'number'
					? [p.smoothedLat, p.smoothedLng]
					: null;
			assert.deepEqual(got, c.expected[i], `waypoint ${i}`);
		});
	});
}

test('a track fingerprint for a different point count than the array is ignored', () => {
	const points = JSON.parse(FIXTURE.trackJson) as Point[];
	const sidecar = FIXTURE.cases[0].sidecar;
	const merged = mergeSmoothedSidecar(points.slice(0, 3), sidecar, { points: 4, sha256: FIXTURE.sha256 });
	assert.equal(merged.filter((p) => p.smoothedLat != null && p.smoothedLng != null).length, 1);
});

test('only a track with no pair anywhere needs a sidecar', () => {
	assert.equal(needsSmoothedSidecar([]), false);
	assert.equal(needsSmoothedSidecar([{ lat: 1, lng: 2 }, { lat: 1, lng: 2, smoothedLat: 1 }]), true);
	assert.equal(needsSmoothedSidecar([{ lat: 1, lng: 2 }, { lat: 1, lng: 2, smoothedLat: 1, smoothedLng: 2 }]), false);
});

test('the sidecar sits beside the track in the owner folder', () => {
	assert.equal(smoothedSidecarPath('u-1', 'r-1'), 'u-1/r-1.smoothed.json.gz');
});

test('only metadata naming this exact track names a sidecar to fetch', () => {
	const sha = FIXTURE.sha256;
	assert.equal(sidecarNamedFor({ smoothed_sidecar_sha256: sha }, sha), true);
	assert.equal(sidecarNamedFor({ smoothed_sidecar_sha256: sha, title: 'Tempo' }, sha), true);
	assert.equal(sidecarNamedFor({}, sha), false, 'a run with no recorded sidecar has nothing to fetch');
	assert.equal(sidecarNamedFor(null, sha), false);
	assert.equal(sidecarNamedFor(undefined, sha), false);
	assert.equal(sidecarNamedFor([sha], sha), false);
	assert.equal(
		sidecarNamedFor({ smoothed_sidecar_sha256: '0'.repeat(64) }, sha),
		false,
		'a hash carried forward from a track since re-uploaded names another track',
	);
	assert.equal(sidecarNamedFor({ smoothed_sidecar_sha256: sha.toUpperCase() }, sha), false);
	assert.equal(sidecarNamedFor({ smoothed_sidecar_sha256: true }, sha), false);
});

test('the run-detail track asks for the sidecar only when the run names this track', () => {
	const src = readFileSync(join(__dirname, '..', 'core', 'data.ts'), 'utf-8');
	const start = src.indexOf('async function fetchOwnerTrack(');
	assert.ok(start !== -1, 'fetchOwnerTrack is gone');
	const body = src.slice(start, src.indexOf('\n}\n', start));
	const gate = body.indexOf('sidecarNamedFor(metadata, sha256)');
	const download = body.indexOf('.download(smoothedSidecarPath(');
	assert.ok(gate !== -1, 'fetchOwnerTrack must check metadata.smoothed_sidecar_sha256 against the track bytes');
	assert.ok(download !== -1, 'fetchOwnerTrack no longer downloads the sidecar');
	assert.ok(gate < download, 'the metadata check must come before the sidecar request, or every run without one 404s');
	assert.match(
		src,
		/fetchOwnerTrack\(data\.track_url, data\.user_id, data\.id, data\.metadata\)/,
		'fetchRunById must pass the row metadata it read',
	);
});
