/// `withholdFromNonOwner` removes the per-point keys that measure a run from
/// its start, so a privacy-zone clip cannot be undone by reading them, and
/// every off-track fix, which is distance input and never line.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/clip-public-track/non_owner_points.test.ts`.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

import { isOffTrackPoint, NON_OWNER_WITHHELD_POINT_KEYS, withholdFromNonOwner } from './non_owner_points.ts';

const TS = '2026-10-15T07:00:00Z';

Deno.test('a start-zone clip serves no distM on the first visible point', () => {
  // The clip dropped the in-zone head; the first survivor was credited 420 m
  // inside the zone, which is the figure that must not reach the viewer.
  const clipped = [
    { lat: 47.37, lng: 8.555, ts: TS, distM: 420, bpm: 140 },
    { lat: 47.37, lng: 8.56, ts: TS, distM: 800, bpm: 150 },
  ];
  assertEquals(withholdFromNonOwner(clipped), [
    { lat: 47.37, lng: 8.555, ts: TS, bpm: 140 },
    { lat: 47.37, lng: 8.56, ts: TS, bpm: 150 },
  ]);
});

Deno.test('a mid-run zone pass serves no distM on either side of it', () => {
  const served = withholdFromNonOwner([
    { lat: 47.37, lng: 8.56, distM: 0 },
    { lat: 47.37, lng: 8.54, distM: 1510 },
    { lat: 47.37, lng: 8.52, distM: 3020 },
  ]);
  assertEquals(served.some((p) => 'distM' in (p as object)), false);
});

Deno.test('every other recorded field is served unchanged', () => {
  const point = {
    lat: 47.37,
    lng: 8.555,
    ele: 410,
    ts: TS,
    bpm: 140,
    accuracyMetres: 4,
    speedMps: 3.1,
    speedAccuracyMps: 0.4,
    bearingDeg: 90,
    smoothedLat: 47.37001,
    smoothedLng: 8.55501,
    baroEle: 409.5,
  };
  assertEquals(withholdFromNonOwner([{ ...point, distM: 420 }]), [point]);
});

Deno.test('the input is not mutated, so an owner path sharing it keeps distM', () => {
  const owner = [{ lat: 47.37, lng: 8.555, distM: 420 }];
  const served = withholdFromNonOwner(owner);
  assertEquals(served, [{ lat: 47.37, lng: 8.555 }]);
  assertEquals(owner, [{ lat: 47.37, lng: 8.555, distM: 420 }]);
});

Deno.test('a non-object element passes through as stored', () => {
  assertEquals(withholdFromNonOwner([null, 3, 'x', [1, 2]]), [null, 3, 'x', [1, 2]]);
});

Deno.test('distM is on the withheld list', () => {
  assertEquals([...NON_OWNER_WITHHELD_POINT_KEYS], ['distM']);
});

Deno.test('an off-track fix is never served, whether or not the clip dropped it', () => {
  // clip_track_for_user drops them first; this layer drops them again, so a
  // regression in one alone does not hand a viewer a canopy fix.
  assertEquals(
    withholdFromNonOwner([
      { lat: 47.37, lng: 8.555, distM: 420 },
      { lat: 47.37, lng: 8.556, distM: 470, offTrack: true },
      { lat: 47.37, lng: 8.557, distM: 520, offTrack: false },
      null,
    ]),
    [{ lat: 47.37, lng: 8.555 }, { lat: 47.37, lng: 8.557, offTrack: false }, null],
  );
});

Deno.test('only offTrack true on an object marks an off-track fix', () => {
  assertEquals(isOffTrackPoint({ lat: 1, lng: 2, offTrack: true }), true);
  assertEquals(isOffTrackPoint({ lat: 1, lng: 2, offTrack: false }), false);
  assertEquals(isOffTrackPoint({ lat: 1, lng: 2, offTrack: 'true' }), false);
  assertEquals(isOffTrackPoint({ lat: 1, lng: 2 }), false);
  assertEquals(isOffTrackPoint(null), false);
  assertEquals(isOffTrackPoint([true]), false);
});
