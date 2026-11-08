/// Pure parts of the segment-match processor (decisions § 2392): the server-key
/// gate, the payload grammar, the track reader, and the geometry the matcher is
/// handed. The extent is the web module's (segments/track_extent.test.ts).
///
/// Run with `cd apps/backend && deno test --allow-read supabase/functions/segment-match/lib.test.ts`.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { parsePayload, readPoints, scorableGeometries, serviceGate, serviceKeys } from './lib.ts';

const RUN = '5b000000-0000-4000-8000-000000000001';
const SEG = '5a5a0000-0000-4000-8000-0000000000d1';

Deno.test('serviceKeys reads every new-format secret key and the legacy one', () => {
  const env: Record<string, string> = {
    SUPABASE_SECRET_KEYS: JSON.stringify({ default: 'sb_secret_a', worker: 'sb_secret_b', bad: 7 }),
    SUPABASE_SERVICE_ROLE_KEY: 'legacy.jwt.key',
  };
  assertEquals(serviceKeys((n) => env[n]), ['sb_secret_a', 'sb_secret_b', 'legacy.jwt.key']);
  assertEquals(serviceKeys((n) => (n === 'SUPABASE_SECRET_KEYS' ? '{not json' : undefined)), []);
});

Deno.test('serviceGate admits any accepted key on apikey or bearer, and nothing else', () => {
  const keys = ['sb_secret_a', 'legacy.jwt.key'];
  assertEquals(serviceGate([], 'sb_secret_a', null), 'not_configured');
  assertEquals(serviceGate(keys, null, null), 'no_key');
  assertEquals(serviceGate(keys, 'sb_secret_a', null), 'ok');
  assertEquals(serviceGate(keys, null, 'Bearer legacy.jwt.key'), 'ok');
  assertEquals(serviceGate(keys, 'sb_publishable_x', 'Bearer legacy.jwt.key'), 'mismatch');
  assertEquals(serviceGate(keys, 'sb_secret_', null), 'mismatch');
  assertEquals(serviceGate(keys, null, 'legacy.jwt.key'), 'no_key');
});

Deno.test('parsePayload accepts the two queue shapes and refuses everything else', () => {
  assertEquals(parsePayload({ run_id: RUN }), { kind: 'run', runId: RUN });
  assertEquals(parsePayload({ segment_id: SEG }), { kind: 'backfill', segmentId: SEG, afterRunId: null });
  assertEquals(parsePayload({ segment_id: SEG, after_run_id: RUN }), {
    kind: 'backfill',
    segmentId: SEG,
    afterRunId: RUN,
  });
  for (const bad of [
    null,
    [],
    'x',
    {},
    { run_id: 'not-a-uuid' },
    { run_id: RUN, segment_id: SEG },
    { segment_id: SEG, after_run_id: 'nope' },
    { run_id: RUN.toUpperCase() },
  ]) {
    assertEquals(parsePayload(bad), null, JSON.stringify(bad));
  }
});

Deno.test('readPoints keeps a point array and refuses one bad element', () => {
  const ok = [{ lat: 1, lng: 2, ts: 'x' }, { lat: 1.5, lng: 2.5 }];
  assertEquals(readPoints(ok), ok);
  assertEquals(readPoints([{ lat: 1, lng: 2 }, null]), null);
  assertEquals(readPoints([{ lat: 1, lng: 'east' }]), null);
  assertEquals(readPoints({ points: ok }), null);
});

Deno.test('scorableGeometries builds the web scorer\'s geometry and drops an unreadable course', () => {
  const candidates = [
    { id: 'plain', waypoints: [{ lat: '37.5', lng: -77.5 }, { lat: 37.6, lng: -77.5 }], distance_m: '445' },
    { id: 'course', waypoints: [{ lat: 1, lng: 2 }, { lat: 1.1, lng: 2 }], distance_m: 1000 },
    { id: 'broken-course', waypoints: [{ lat: 1, lng: 2 }], distance_m: 1000 },
  ];
  const checkpoints = [
    { global_segment_id: 'course', checkpoints: [{ lat: 1.05, lng: 2 }] },
    { global_segment_id: 'broken-course', checkpoints: [{ lat: 'north', lng: 2 }] },
  ];
  assertEquals(scorableGeometries(candidates, checkpoints), {
    ids: ['plain', 'course'],
    geometries: [
      { points: [{ lat: 37.5, lng: -77.5 }, { lat: 37.6, lng: -77.5 }], distance_m: 445, checkpoints: undefined },
      { points: [{ lat: 1, lng: 2 }, { lat: 1.1, lng: 2 }], distance_m: 1000, checkpoints: [{ lat: 1.05, lng: 2 }] },
    ],
  });
});
