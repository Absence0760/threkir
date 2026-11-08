/// The `segment-match` processor (issue #1313 Phase 1, decisions § 2392):
/// score one run's stored track against the catalogue segments near it, or
/// one batch of a launch backfill, and write the efforts as the service role.
///
/// The timing rule is the canonical web matcher, bundled into
/// `_shared/segment_matcher.generated.js` (scripts/gen_edge_segment_matcher.mjs),
/// so the server, the web and the phone apply one rule. This file holds the
/// gate, the payload grammar and the scoring pass behind an injected client;
/// handler.ts maps outcomes to responses and index.ts wires the real client.

import type { DbClient } from '../_shared/database.ts';
import { timingSafeEqual } from '../_shared/webhook_security.ts';
import { gunzipCapped } from '../_shared/gunzip_capped.ts';
import {
  mergeSmoothedSidecar,
  needsSmoothedSidecar,
  sha256Hex,
  sidecarNamedFor,
  smoothedSidecarPath,
} from '../_shared/smoothed_sidecar.ts';
import {
  computeGlobalSegmentEfforts,
  parseCourseCheckpoints,
  trackExtent,
} from '../_shared/segment_matcher.generated.js';

/// Runs one backfill batch scores. Each costs a track download and a matcher
/// pass, so 20 keeps a batch well inside the request clock; the next batch is
/// a job of its own.
export const BACKFILL_BATCH = 20;

/// The pad, in metres, around the track's extent when asking for candidates.
/// Above the matcher's 35 m tolerance, so no segment it could time is missed.
export const CANDIDATE_PAD_M = 50;

/// Candidate cap per run. A track meets a handful of segments; the cap is only
/// a bound on a pathological catalogue, and the RPC orders by id so a capped
/// read is the same set every time.
export const CANDIDATE_LIMIT = 1000;

/// The same compressed-size bound clip-public-track holds a track to.
export const MAX_TRACK_GZ_BYTES = 5 * 1024 * 1024;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// ─────────────────────────── the caller gate ───────────────────────────

/// Every server key this project accepts, from the function's own env: each
/// value of SUPABASE_SECRET_KEYS (a JSON object keyed by key name) plus the
/// legacy SUPABASE_SERVICE_ROLE_KEY. The job worker presents one of them,
/// whichever it was deployed with, so the gate needs no secret of its own.
export function serviceKeys(getEnv: (name: string) => string | undefined): string[] {
  const keys: string[] = [];
  const raw = getEnv('SUPABASE_SECRET_KEYS');
  if (raw) {
    try {
      const parsed: unknown = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        for (const v of Object.values(parsed as Record<string, unknown>)) {
          if (typeof v === 'string' && v.length > 0) keys.push(v);
        }
      }
    } catch {
      // An unreadable variable contributes nothing; the legacy key may still.
    }
  }
  const legacy = getEnv('SUPABASE_SERVICE_ROLE_KEY');
  if (legacy) keys.push(legacy);
  return keys;
}

export type ServiceGate = 'not_configured' | 'no_key' | 'mismatch' | 'ok';

/// The key the caller presented: `apikey` (where both key generations travel,
/// internal/supakey) or else an `Authorization: Bearer`. Compared in constant
/// time against every accepted key, and never logged.
export function serviceGate(
  keys: readonly string[],
  apikey: string | null,
  authorization: string | null,
): ServiceGate {
  if (keys.length === 0) return 'not_configured';
  const auth = authorization ?? '';
  const presented = apikey || (auth.startsWith('Bearer ') ? auth.slice(7) : '');
  if (!presented) return 'no_key';
  let ok = false;
  for (const k of keys) {
    if (timingSafeEqual(presented, k)) ok = true;
  }
  return ok ? 'ok' : 'mismatch';
}

// ─────────────────────────── the payload ───────────────────────────

export type SegmentMatchPayload =
  | { kind: 'run'; runId: string }
  | { kind: 'backfill'; segmentId: string; afterRunId: string | null };

/// The two shapes the queue carries (migration 20271117002392): `{run_id}` or
/// `{segment_id, after_run_id?}`. Anything else is null, a permanent refusal.
export function parsePayload(body: unknown): SegmentMatchPayload | null {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
  const b = body as Record<string, unknown>;
  const isId = (v: unknown): v is string => typeof v === 'string' && UUID.test(v);
  if ('run_id' in b) {
    if (!isId(b.run_id) || 'segment_id' in b) return null;
    return { kind: 'run', runId: b.run_id };
  }
  if ('segment_id' in b) {
    if (!isId(b.segment_id)) return null;
    const after = b.after_run_id;
    if (after !== undefined && after !== null && !isId(after)) return null;
    return { kind: 'backfill', segmentId: b.segment_id, afterRunId: isId(after) ? after : null };
  }
  return null;
}

// ─────────────────────────── the track ───────────────────────────

type StoredPoint = { lat: number; lng: number; [k: string]: unknown };

function finite(v: unknown): v is number {
  return typeof v === 'number' && Number.isFinite(v);
}

/// The stored track as the matcher reads it, or null when any element is not
/// a point with finite lat and lng. The web scorer would throw on such an
/// element and score nothing; null keeps that outcome without the throw.
export function readPoints(raw: unknown): StoredPoint[] | null {
  if (!Array.isArray(raw)) return null;
  for (const p of raw) {
    if (!p || typeof p !== 'object' || !finite((p as StoredPoint).lat) || !finite((p as StoredPoint).lng)) {
      return null;
    }
  }
  return raw as StoredPoint[];
}

// ─────────────────────────── the catalogue ───────────────────────────

export interface CandidateRow {
  id: string;
  waypoints: unknown;
  distance_m: number | string;
}

export interface CheckpointRow {
  global_segment_id: string;
  checkpoints: unknown;
}

export interface Geometry {
  points: { lat: number; lng: number }[];
  distance_m: number;
  checkpoints?: { lat: number; lng: number }[];
}

/// The candidates the matcher may score, each with its geometry in the shape
/// the web scorer builds (`computeGlobalSegmentEffortsForRun`: `Number()` on
/// each coordinate and on the length). A park course's checkpoints are part of
/// its rule, so a course whose list `parseCourseCheckpoints` cannot read is
/// left out — scored by neither side, and so not a candidate whose effort the
/// write may remove.
export function scorableGeometries(
  candidates: readonly CandidateRow[],
  checkpointRows: readonly CheckpointRow[],
): { ids: string[]; geometries: Geometry[] } {
  const checkpoints = new Map<string, { lat: number; lng: number }[] | null>();
  for (const row of checkpointRows) {
    checkpoints.set(row.global_segment_id, parseCourseCheckpoints(row.checkpoints));
  }
  const ids: string[] = [];
  const geometries: Geometry[] = [];
  for (const seg of candidates) {
    const cps = checkpoints.get(seg.id);
    if (cps === null) continue;
    const waypoints = Array.isArray(seg.waypoints) ? seg.waypoints : [];
    ids.push(seg.id);
    geometries.push({
      points: waypoints.map((w: { lat?: unknown; lng?: unknown }) => ({
        lat: Number(w?.lat),
        lng: Number(w?.lng),
      })),
      distance_m: Number(seg.distance_m),
      checkpoints: cps ?? undefined,
    });
  }
  return { ids, geometries };
}

// ─────────────────────────── one run ───────────────────────────

export type RunOutcome =
  /// Efforts written for the stored bytes.
  | 'recorded'
  /// The run is gone, or has no track: nothing to score, nothing to retry.
  | 'missing'
  | 'no_track'
  /// The stored object is not a readable track (too large, not gzip, not a
  /// point array). Retrying reads the same bytes, so this is final.
  | 'unreadable'
  /// The row names a track whose bytes are not uploaded yet. Final: the
  /// upload's own trigger on storage.objects queues the run again.
  | 'track_not_uploaded'
  /// The bytes changed under the pass and the write was refused. Transient:
  /// the rewrite queued a fresh job too, and retrying this one costs a pass.
  | 'stale';

export interface RunResult {
  outcome: RunOutcome;
  matched: number;
}

/// Score one run. Throws on a failed database or Storage read, which the
/// handler reports as a transient failure (the job is retried); every other
/// outcome is returned.
export async function scoreRun(client: DbClient, runId: string): Promise<RunResult> {
  const none = (outcome: RunOutcome): RunResult => ({ outcome, matched: 0 });

  const { data: sources, error: srcErr } = await client.rpc('segment_match_run_source', {
    p_run_id: runId,
  });
  if (srcErr) throw new Error(`run source read failed (${srcErr.code ?? 'unknown'})`);
  const src = Array.isArray(sources) ? sources[0] : undefined;
  if (!src) return none('missing');
  if (!src.track_url) return none('no_track');
  if (!src.track_version) return none('track_not_uploaded');

  const { data: blob, error: dlErr } = await client.storage.from('runs').download(src.track_url);
  if (dlErr || !blob) {
    // The object row exists (it has a version), so a failed download is the
    // Storage API, not a missing upload: transient.
    throw new Error('track download failed');
  }
  const gz = new Uint8Array(await blob.arrayBuffer());
  if (gz.byteLength > MAX_TRACK_GZ_BYTES) return none('unreadable');

  let trackBytes: Uint8Array<ArrayBuffer>;
  let parsed: unknown;
  try {
    trackBytes = await gunzipCapped(gz);
    parsed = JSON.parse(new TextDecoder().decode(trackBytes));
  } catch {
    // Not gzip, past the inflated-size cap (InflateLimitError), or not JSON.
    return none('unreadable');
  }
  let points = readPoints(parsed);
  if (!points) return none('unreadable');

  // The owner's run-detail line merges the job worker's smoothed sidecar when
  // the run names it for these exact bytes (data.ts fetchOwnerTrack), so the
  // server scores that same line. Any failure to read it leaves the raw line.
  if (needsSmoothedSidecar(points)) {
    try {
      const sha256 = await sha256Hex(trackBytes);
      if (sidecarNamedFor(src.metadata, sha256)) {
        const { data: sc, error: scErr } = await client.storage
          .from('runs')
          .download(smoothedSidecarPath(src.user_id, runId));
        if (!scErr && sc) {
          const scGz = new Uint8Array(await sc.arrayBuffer());
          if (scGz.byteLength <= MAX_TRACK_GZ_BYTES) {
            const sidecar = JSON.parse(new TextDecoder().decode(await gunzipCapped(scGz)));
            points = mergeSmoothedSidecar(points, sidecar, { points: points.length, sha256 });
          }
        }
      }
    } catch {
      // auxiliary: the raw line stands
    }
  }

  // The same extent the web fallback asks with (segments/track_extent.ts).
  const extent = trackExtent(points);
  if (!extent) return none('unreadable');

  const { data: candidates, error: candErr } = await client.rpc('global_segments_in_bbox', {
    p_min_lat: extent.minLat,
    p_min_lng: extent.minLng,
    p_max_lat: extent.maxLat,
    p_max_lng: extent.maxLng,
    p_pad_m: CANDIDATE_PAD_M,
    p_limit: CANDIDATE_LIMIT,
  });
  if (candErr) throw new Error(`candidate read failed (${candErr.code ?? 'unknown'})`);
  const rows = (candidates ?? []) as CandidateRow[];

  let checkpointRows: CheckpointRow[] = [];
  if (rows.length > 0) {
    const { data: cps, error: cpErr } = await client
      .from('park_courses')
      .select('global_segment_id, checkpoints')
      .in('global_segment_id', rows.map((r) => r.id));
    // Fail closed, as the web scorer does: without the checkpoints a course
    // would time a run that cut it.
    if (cpErr) throw new Error(`checkpoint read failed (${cpErr.code ?? 'unknown'})`);
    checkpointRows = (cps ?? []) as CheckpointRow[];
  }

  const { ids, geometries } = scorableGeometries(rows, checkpointRows);
  const results = computeGlobalSegmentEfforts(points, geometries);
  const efforts: { global_segment_id: string; time_seconds: number; started_at: string }[] = [];
  for (let i = 0; i < ids.length; i++) {
    const eff = results[i];
    if (eff) efforts.push({ global_segment_id: ids[i], time_seconds: eff.time_seconds, started_at: eff.started_at });
  }

  const { data: status, error: recErr } = await client.rpc('record_segment_match', {
    p_run_id: runId,
    p_track_version: src.track_version,
    p_min_lat: extent.minLat,
    p_min_lng: extent.minLng,
    p_max_lat: extent.maxLat,
    p_max_lng: extent.maxLng,
    p_candidates: ids,
    p_efforts: efforts,
  });
  if (recErr) throw new Error(`effort write failed (${recErr.code ?? 'unknown'})`);
  if (status === 'stale') return none('stale');
  if (status === 'missing') return none('missing');
  return { outcome: 'recorded', matched: efforts.length };
}
