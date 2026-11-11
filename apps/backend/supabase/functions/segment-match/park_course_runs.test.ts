/// The segment-match scoring pass over the real Pocahontas courses (issue
/// #1342 step 5c). Every synthetic run in fixtures/park_course_runs.json goes
/// through `scoreRun` as the job worker's call would: the stored gzipped
/// track, the six courses as `global_segments_in_bbox` rows carrying their
/// lines, their checkpoints from `park_courses`. What reaches
/// `record_segment_match` must be exactly what the web matcher recorded for
/// that run, which is also what park_course_boards_test.sql writes and reads
/// back from the boards. A fake client, no stack.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/segment-match/park_course_runs.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { scoreRun } from './lib.ts';

const ROOT = new URL('../../../../../', import.meta.url);
const RUN = 'cb000000-0000-4000-8000-000000000001';
const OWNER = '00000000-0000-0000-0000-0000000cb0a1';
const TRACK_URL = `${OWNER}/${RUN}.json.gz`;

type Line = { lat: number; lng: number; bearing_deg: number; half_width_m: number };
type Fixture = {
  base_time: string;
  courses: {
    slug: string;
    geojson: string;
    distance_m: number;
    checkpoints: { lat: number; lng: number }[];
    start_gate: Line;
    end_gate: Line;
  }[];
  cases: {
    key: string;
    name: string;
    matched: Record<string, { time_seconds: number; started_offset_ms: number; matched_by: string }>;
    extent: { min_lat: number; min_lng: number; max_lat: number; max_lng: number };
    track: { first: [number, number]; d: number[]; gaps: [number, number][] };
  }[];
};

const fixture: Fixture = JSON.parse(await Deno.readTextFile(new URL('fixtures/park_course_runs.json', ROOT)));
const baseMs = Date.parse(fixture.base_time);
const segId = (i: number) => `cb5e0000-0000-4000-8000-00000000000${i + 1}`;

const candidates = await Promise.all(
  fixture.courses.map(async (c, i) => {
    const gj = JSON.parse(await Deno.readTextFile(new URL(c.geojson, ROOT)));
    const line = gj.features.find((f: { geometry?: { type?: string } }) => f.geometry?.type === 'LineString');
    return {
      id: segId(i),
      waypoints: line.geometry.coordinates.map((p: number[]) =>
        p[2] == null ? { lat: p[1], lng: p[0] } : { lat: p[1], lng: p[0], ele: p[2] }
      ),
      distance_m: String(c.distance_m),
      start_gate_lat: c.start_gate.lat,
      start_gate_lng: c.start_gate.lng,
      start_gate_bearing_deg: c.start_gate.bearing_deg,
      start_gate_half_width_m: c.start_gate.half_width_m,
      end_gate_lat: c.end_gate.lat,
      end_gate_lng: c.end_gate.lng,
      end_gate_bearing_deg: c.end_gate.bearing_deg,
      end_gate_half_width_m: c.end_gate.half_width_m,
    };
  }),
);
const checkpointRows = fixture.courses.map((c, i) => ({ global_segment_id: segId(i), checkpoints: c.checkpoints }));

/// The stored track as the phone's sync uploads it: points with an ISO ts.
function storedTrack(t: Fixture['cases'][number]['track']): { lat: number; lng: number; ts: string }[] {
  const gaps = new Map(t.gaps);
  let lat = t.first[0];
  let lng = t.first[1];
  let s = 0;
  const out = [{ lat: lat / 1e6, lng: lng / 1e6, ts: new Date(baseMs).toISOString() }];
  for (let i = 1; i <= t.d.length / 2; i++) {
    lat += t.d[2 * i - 2];
    lng += t.d[2 * i - 1];
    s += gaps.get(i) ?? 1;
    out.push({ lat: lat / 1e6, lng: lng / 1e6, ts: new Date(baseMs + s * 1000).toISOString() });
  }
  return out;
}

async function gzip(value: unknown): Promise<Blob> {
  const stream = new Blob([JSON.stringify(value)]).stream().pipeThrough(new CompressionStream('gzip'));
  return await new Response(stream).blob();
}

function fakeClient(track: Blob) {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const client = {
    rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      if (name === 'segment_match_run_source') {
        return Promise.resolve({
          data: [{ user_id: OWNER, track_url: TRACK_URL, track_version: 'v1', metadata: {} }],
          error: null,
        });
      }
      if (name === 'global_segments_in_bbox') return Promise.resolve({ data: candidates, error: null });
      if (name === 'record_segment_match') return Promise.resolve({ data: 'recorded', error: null });
      return Promise.resolve({ data: null, error: { code: 'unscripted' } });
    },
    storage: {
      from(_bucket: string) {
        return {
          download(path: string) {
            return Promise.resolve(
              path === TRACK_URL ? { data: track, error: null } : { data: null, error: { message: 'not found' } },
            );
          },
        };
      },
    },
    from(_table: string) {
      const builder = {
        select() {
          return builder;
        },
        in(_col: string, ids: string[]) {
          return Promise.resolve({ data: checkpointRows.filter((r) => ids.includes(r.global_segment_id)), error: null });
        },
      };
      return builder;
    },
  };
  return { calls, client: client as unknown as DbClient };
}

for (const c of fixture.cases) {
  Deno.test(`segment-match scores ${c.name} as the web matcher does`, async () => {
    const fake = fakeClient(await gzip(storedTrack(c.track)));
    const result = await scoreRun(fake.client, RUN);
    assertEquals(result, { outcome: 'recorded', matched: Object.keys(c.matched).length });

    const bbox = fake.calls.find((x) => x.name === 'global_segments_in_bbox')!.args;
    assertEquals(
      [bbox.p_min_lat, bbox.p_min_lng, bbox.p_max_lat, bbox.p_max_lng],
      [c.extent.min_lat, c.extent.min_lng, c.extent.max_lat, c.extent.max_lng],
    );

    const rec = fake.calls.find((x) => x.name === 'record_segment_match')!.args;
    assertEquals(rec.p_track_version, 'v1');
    assertEquals(rec.p_candidates, candidates.map((x) => x.id));
    const efforts = rec.p_efforts as { global_segment_id: string; time_seconds: number; started_at: string; matched_by: string }[];
    const want = fixture.courses.flatMap((course, i) => {
      const m = c.matched[course.slug];
      return m ? [{ id: segId(i), ...m }] : [];
    });
    assertEquals(efforts.map((e) => e.global_segment_id), want.map((w) => w.id));
    efforts.forEach((e, i) => {
      assert(Math.abs(e.time_seconds - want[i].time_seconds) < 0.001, `${e.time_seconds} vs ${want[i].time_seconds}`);
      assertEquals(Date.parse(e.started_at) - baseMs, want[i].started_offset_ms);
      assertEquals(e.matched_by, want[i].matched_by);
    });
  });
}

Deno.test('the net reaches the function with a timed run on every course', () => {
  for (const course of fixture.courses) {
    assert(fixture.cases.some((c) => c.matched[course.slug]), `${course.slug}: no run is timed on it`);
  }
});
