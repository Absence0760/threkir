import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  mergeSmoothedSidecar,
  needsSmoothedSidecar,
  sha256Hex,
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
};

type Point = { lat: number; lng: number; smoothedLat?: unknown; smoothedLng?: unknown };

Deno.test('the fixture is for sidecar version 1 and holds cases', () => {
  assertEquals(FIXTURE.version, 1);
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
