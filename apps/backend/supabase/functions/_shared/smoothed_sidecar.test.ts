import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  mergeSmoothedSidecar,
  needsSmoothedSidecar,
  sha256Hex,
  sidecarNamedFor,
  SMOOTHED_SIDECAR_VERSION,
  smoothedSidecarPath,
} from './smoothed_sidecar.ts';

// Replays fixtures/smoothed_sidecar_vectors.json, the vectors the web
// (`apps/web/src/lib/runs/smoothed_sidecar.test.ts`) and Dart readers and the
// Go writer share.
//
// Run with `cd apps/backend && deno test --no-check --allow-read
// supabase/functions/_shared/smoothed_sidecar.test.ts`.

const FIXTURE = JSON.parse(
  await Deno.readTextFile(
    new URL('../../../../../fixtures/smoothed_sidecar_vectors.json', import.meta.url),
  ),
) as {
  version: number;
  trackJson: string;
  sha256: string;
  cases: { name: string; sidecar: unknown; expected: ([number, number] | null)[] }[];
  nonObjectTrack: {
    trackJson: string;
    sha256: string;
    sidecar: unknown;
    expected: ([number, number] | null)[];
  };
};

type Point = { lat: number; lng: number; smoothedLat?: unknown; smoothedLng?: unknown };

Deno.test('the fixture is for the sidecar version this reader accepts, and holds cases', () => {
  assertEquals(SMOOTHED_SIDECAR_VERSION, 1);
  assertEquals(FIXTURE.version, SMOOTHED_SIDECAR_VERSION);
  assert(FIXTURE.cases.length > 0);
});

Deno.test('the track fingerprint is the SHA-256 of the decompressed bytes, lower-case hex', async () => {
  assertEquals(await sha256Hex(new TextEncoder().encode(FIXTURE.trackJson)), FIXTURE.sha256);
});

for (const c of FIXTURE.cases) {
  Deno.test(`merge: ${c.name}`, () => {
    const points = JSON.parse(FIXTURE.trackJson) as Point[];
    const raw = points.map((p) => [p.lat, p.lng]);
    const merged = mergeSmoothedSidecar(points, c.sidecar, {
      points: points.length,
      sha256: FIXTURE.sha256,
    }) as Point[];
    assertEquals(merged.length, c.expected.length);
    merged.forEach((p, i) => {
      assertEquals([p.lat, p.lng], raw[i], `waypoint ${i}: raw lat/lng must never change`);
      const got = typeof p.smoothedLat === 'number' && typeof p.smoothedLng === 'number'
        ? [p.smoothedLat, p.smoothedLng]
        : null;
      assertEquals(got, c.expected[i], `waypoint ${i}`);
    });
  });
}

Deno.test('a non-object waypoint passes through untouched', () => {
  const sidecar = FIXTURE.cases[0].sidecar as { track: { sha256: string } };
  const merged = mergeSmoothedSidecar([null, 'x', 3, []], sidecar, { points: 4, sha256: sidecar.track.sha256 });
  assertEquals(merged, [null, 'x', 3, []]);
});

Deno.test('the fixture track with a non-object entry keeps it and merges the rest', async () => {
  const v = FIXTURE.nonObjectTrack;
  assertEquals(await sha256Hex(new TextEncoder().encode(v.trackJson)), v.sha256);
  const points = JSON.parse(v.trackJson) as (Point | null)[];
  assertEquals(needsSmoothedSidecar(points), true);
  const merged = mergeSmoothedSidecar(points, v.sidecar, { points: points.length, sha256: v.sha256 });
  assertEquals(merged.length, v.expected.length);
  merged.forEach((p, i) => {
    if (p === null) {
      assertEquals(v.expected[i], null, `waypoint ${i}`);
      return;
    }
    const got = typeof p.smoothedLat === 'number' && typeof p.smoothedLng === 'number'
      ? [p.smoothedLat, p.smoothedLng]
      : null;
    assertEquals(got, v.expected[i], `waypoint ${i}`);
  });
});

Deno.test('only a track with no pair anywhere needs a sidecar', () => {
  assertEquals(needsSmoothedSidecar([]), false);
  assertEquals(needsSmoothedSidecar([{ lat: 1, lng: 2 }, { lat: 1, lng: 2, smoothedLat: 1 }]), true);
  assertEquals(
    needsSmoothedSidecar([{ lat: 1, lng: 2 }, { lat: 1, lng: 2, smoothedLat: 1, smoothedLng: 2 }]),
    false,
  );
});

Deno.test('the sidecar sits beside the track in the owner folder', () => {
  assertEquals(smoothedSidecarPath('u-1', 'r-1'), 'u-1/r-1.smoothed.json.gz');
});

Deno.test('only metadata naming this exact track names a sidecar to fetch', () => {
  const sha = FIXTURE.sha256;
  assertEquals(sidecarNamedFor({ smoothed_sidecar_sha256: sha }, sha), true);
  assertEquals(sidecarNamedFor({}, sha), false);
  assertEquals(sidecarNamedFor(null, sha), false);
  assertEquals(sidecarNamedFor([sha], sha), false);
  assertEquals(sidecarNamedFor({ smoothed_sidecar_sha256: '0'.repeat(64) }, sha), false);
  assertEquals(sidecarNamedFor({ smoothed_sidecar_sha256: sha.toUpperCase() }, sha), false);
});
