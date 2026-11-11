import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { TrackPoint } from '../types';
import {
	RACE_RESULT_WRITE_WINDOW_MS,
	computeRetime,
	raceOccurrenceForRun,
	retimeApproval,
	retimeFixes,
	type RetimeCourse,
	type RetimeCurrent,
	type RetimeInput,
	type RetimeOutcome,
	type RetimeSession,
} from './race_retime';

// Re-time from the stored track (#1307 M11). The first block replays every
// case of fixtures/race_finish_cases.json's `lines` section through the whole
// re-time path (track -> fixes -> detector -> timing), so the web re-time and
// the Dart and Kotlin live detectors give the same answer for the same fixes.

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..', '..');
type Obj = Record<string, unknown>;
const fixture = JSON.parse(readFileSync(join(REPO, 'fixtures', 'race_finish_cases.json'), 'utf-8')) as Obj;
const t0 = fixture.t0EpochMs as number;
const origin = fixture.origin as Obj;
const finishLat = origin.finishLat as number;
const finishLng = origin.finishLng as number;
const gateK = (((fixture.constants as Obj).GATE_EARTH_RADIUS_M as number) * Math.PI) / 180;

function plane(northM: number, eastM = 0): { lat: number; lng: number } {
	return {
		lat: finishLat + northM / gateK,
		lng: finishLng + eastM / (gateK * Math.cos((finishLat * Math.PI) / 180)),
	};
}

function isoAt(ms: number): string {
	return new Date(ms).toISOString();
}

function gateCols(prefix: 'start' | 'finish', g: Obj | null): Partial<RetimeCourse> {
	if (g === null) {
		return {
			[`${prefix}_gate_lat`]: null,
			[`${prefix}_gate_lng`]: null,
			[`${prefix}_gate_bearing_deg`]: null,
			[`${prefix}_gate_half_width_m`]: null,
		};
	}
	const p = plane(g.northM as number, g.eastM as number);
	return {
		[`${prefix}_gate_lat`]: p.lat,
		[`${prefix}_gate_lng`]: p.lng,
		[`${prefix}_gate_bearing_deg`]: g.bearingDeg as number,
		[`${prefix}_gate_half_width_m`]: g.halfWidthM as number,
	};
}

function num(v: unknown): number {
	if (v === 'NaN') return NaN;
	if (v === 'Infinity') return Infinity;
	if (v === '-Infinity') return -Infinity;
	return v as number;
}

for (const c of fixture.lines as Obj[]) {
	test(`cross-port: ${String(c.name)}`, () => {
		const selfTimed = c.mode === 'selfTimed';
		const goS = c.goS as number | null;
		const pressS = c.pressS as number | null;
		const distance = num(c.courseDistanceM);
		const startGate = c.startGate as Obj | null;
		const finishGate = c.finishGate as Obj | null;
		const usable = (g: Obj | null) => g !== null && (g.halfWidthM as number) > 0;
		const course = {
			course_id: 'c',
			distance_m: distance,
			finish_lat: finishLat,
			finish_lng: finishLng,
			finish_line_self_cross: false,
			...gateCols('start', startGate),
			...gateCols('finish', finishGate),
		} as RetimeCourse;
		const track: TrackPoint[] = (c.fixes as Obj[]).map((f) => ({
			...plane(f.northM as number, f.eastM as number),
			ts: isoAt(t0 + (f.atS as number) * 1000),
			distM: f.coveredM as number,
		}));
		const out = computeRetime({
			track,
			runStartedAt: isoAt(t0 + (pressS ?? 0) * 1000),
			session: {
				status: 'running',
				start_mode: selfTimed ? 'self_timed' : 'host_go',
				started_at: goS === null ? null : isoAt(t0 + goS * 1000),
				finished_at: null,
				is_auto_approve: true,
			},
			course,
			current: null,
			nowMs: t0,
		});
		const e = c.expect as Obj;
		const settle = e.settle as Obj | null;
		if (selfTimed ? !usable(startGate) : !usable(startGate) && !usable(finishGate)) {
			assert.deepEqual(out, { kind: 'unavailable', reason: 'no_line' });
			return;
		}
		if (!Number.isFinite(distance)) {
			assert.deepEqual(out, { kind: 'unavailable', reason: 'no_distance' });
			return;
		}
		if (!selfTimed && goS === null) {
			assert.deepEqual(out, { kind: 'unavailable', reason: 'no_go' });
			return;
		}
		if (settle === null) {
			assert.deepEqual(out, { kind: 'no_crossing' });
			return;
		}
		assert.equal(out.kind, 'ready');
		if (out.kind !== 'ready') return;
		const cand = out.candidate;
		assert.equal(cand.finishAt, isoAt(t0 + (settle.atMs as number)));
		assert.equal(cand.finishDetection, settle.detection);
		const start = settle.start as Obj | null;
		assert.equal(cand.startAt, isoAt(t0 + (start === null ? (pressS ?? 0) * 1000 : (start.atMs as number))));
		assert.equal(cand.startDetection, start === null ? 'device' : 'gate');
		const timing = e.timing as Obj;
		assert.equal(cand.gunTimeS, timing.gunTimeS);
		assert.equal(cand.chipTimeS, timing.chipTimeS);
		assert.equal(cand.durationS, timing.durationS);
		assert.equal(cand.clockBasis, 'device');
	});
}

// A straight course due north: start line 0 m, finish line 1000 m, both
// facing north. A run from -20 m to 1020 m at 4 m/s.
const START_N = 0;
const FINISH_N = 1000;
const course: RetimeCourse = {
	course_id: 'c1',
	distance_m: 1000,
	...plane(FINISH_N),
	finish_lat: plane(FINISH_N).lat,
	finish_lng: plane(FINISH_N).lng,
	finish_line_self_cross: false,
	start_gate_lat: plane(START_N).lat,
	start_gate_lng: plane(START_N).lng,
	start_gate_bearing_deg: 0,
	start_gate_half_width_m: 15,
	finish_gate_lat: plane(FINISH_N).lat,
	finish_gate_lng: plane(FINISH_N).lng,
	finish_gate_bearing_deg: 0,
	finish_gate_half_width_m: 15,
} as RetimeCourse;

/** One fix every 5 s from -20 m north, 20 m apart; the start crossing at t0 + 5 s, the finish at t0 + 255 s. */
function straightTrack(): TrackPoint[] {
	const out: TrackPoint[] = [];
	for (let i = 0; i <= 52; i++) {
		const n = -20 + i * 20;
		out.push({ ...plane(n), ts: isoAt(t0 + i * 5000), distM: i * 20 });
	}
	return out;
}

const GO_MS = t0 - 30_000;

function session(over: Partial<RetimeSession> = {}): RetimeSession {
	return {
		status: 'running',
		start_mode: 'host_go',
		started_at: isoAt(GO_MS),
		finished_at: null,
		window_opens_at: null,
		window_closes_at: null,
		is_auto_approve: false,
		...over,
	};
}

function selfTimedSession(over: Partial<RetimeSession> = {}): RetimeSession {
	return session({
		start_mode: 'self_timed',
		started_at: isoAt(t0 - 3600_000),
		window_opens_at: isoAt(t0 - 3600_000),
		window_closes_at: isoAt(t0 + 3600_000),
		...over,
	});
}

function current(over: Partial<RetimeCurrent> = {}): RetimeCurrent {
	return {
		finisher_status: 'finished',
		finish_method: 'manual',
		start_detection: null,
		finish_detection: null,
		needs_review: false,
		duration_s: 300,
		gun_time_s: null,
		chip_time_s: 300,
		clock_offset_ms: null,
		...over,
	};
}

function run(over: Partial<RetimeInput> = {}): RetimeOutcome {
	return computeRetime({
		track: straightTrack(),
		runStartedAt: isoAt(t0),
		session: session(),
		course,
		current: null,
		nowMs: t0 + 600_000,
		...over,
	});
}

function ready(o: RetimeOutcome) {
	assert.equal(o.kind, 'ready', JSON.stringify(o));
	if (o.kind !== 'ready') throw new Error('not ready');
	return o;
}

test('a gun race is timed from GO to the finish crossing, chip from the start crossing', () => {
	const c = ready(run()).candidate;
	assert.equal(c.startAt, isoAt(t0 + 5000));
	assert.equal(c.finishAt, isoAt(t0 + 255_000));
	assert.equal(c.startDetection, 'gate');
	assert.equal(c.finishDetection, 'gate');
	assert.equal(c.gunTimeS, 285);
	assert.equal(c.chipTimeS, 250);
	assert.equal(c.durationS, 285);
});

test('clock basis: the result’s persisted offset moves every fix onto the server clock', () => {
	const c = ready(run({ current: current({ clock_offset_ms: 7000 }) })).candidate;
	assert.equal(c.clockBasis, 'result');
	assert.equal(c.clockOffsetMs, 7000);
	assert.equal(c.finishAt, isoAt(t0 + 262_000));
	assert.equal(c.startAt, isoAt(t0 + 12_000));
	assert.equal(c.gunTimeS, 292, 'GO is the server clock and does not move');
	assert.equal(c.chipTimeS, 250, 'the span between two crossings does not move');
});

test('clock basis: without a persisted offset the recording’s own clock is used, and said', () => {
	const c = ready(run({ current: current({ clock_offset_ms: null }) })).candidate;
	assert.equal(c.clockBasis, 'device');
	assert.equal(c.clockOffsetMs, null);
	assert.equal(c.gunTimeS, 285);
});

test('clock basis: a Start-press start is the run’s start moved by the same offset', () => {
	const noStart = { ...course, start_gate_lat: null, start_gate_lng: null } as RetimeCourse;
	const c = ready(run({ course: noStart, current: current({ clock_offset_ms: -2000 }) })).candidate;
	assert.equal(c.startDetection, 'device');
	assert.equal(c.startAt, isoAt(t0 - 2000));
	assert.equal(c.finishAt, isoAt(t0 + 253_000));
	assert.equal(c.chipTimeS, 255);
	assert.equal(c.gunTimeS, 283);
});

test('window: open until 24 h after the race finished, closed after', () => {
	const fin = t0 + 1000_000;
	const s = session({ status: 'finished', finished_at: isoAt(fin) });
	assert.equal(run({ session: s, nowMs: fin + RACE_RESULT_WRITE_WINDOW_MS - 1 }).kind, 'ready');
	assert.equal(run({ session: s, nowMs: fin + RACE_RESULT_WRITE_WINDOW_MS }).kind, 'ready', 'the server keeps the boundary');
	assert.deepEqual(run({ session: s, nowMs: fin + RACE_RESULT_WRITE_WINDOW_MS + 1 }), { kind: 'closed' });
});

test('lock rule: a DNF, a pending manual and a row waiting on review are replaced', () => {
	assert.equal(run({ current: current({ finisher_status: 'dnf', finish_method: 'host', duration_s: 10 }) }).kind, 'ready');
	assert.equal(run({ current: current() }).kind, 'ready');
	const review = current({ finish_method: 'auto', start_detection: 'gate', finish_detection: 'gate', needs_review: true });
	assert.equal(run({ current: review }).kind, 'ready');
});

test('lock rule: a finish the organiser set is never replaced', () => {
	const o = run({ current: current({ finish_method: 'host' }) });
	assert.equal(o.kind, 'locked');
	assert.equal(o.kind === 'locked' && o.reason, 'host');
});

test('lock rule: a clean gate-to-gate gun result is protected', () => {
	const prot = current({ finish_method: 'auto', start_detection: 'gate', finish_detection: 'gate', duration_s: 400 });
	const o = run({ current: prot });
	assert.equal(o.kind, 'locked');
	assert.equal(o.kind === 'locked' && o.reason, 'protected');
});

test('lock rule: self-timed, only a faster gate-to-gate finish replaces a protected one', () => {
	const prot = (d: number) =>
		current({ finish_method: 'auto', start_detection: 'gate', finish_detection: 'gate', duration_s: d, chip_time_s: d });
	assert.equal(run({ session: selfTimedSession(), current: prot(251) }).kind, 'ready');
	assert.equal(run({ session: selfTimedSession(), current: prot(250) }).kind, 'unchanged');
	assert.equal(run({ session: selfTimedSession(), current: prot(200) }).kind, 'locked');
});

test('self-timed: chip time only, and a start outside the window is flagged', () => {
	const c = ready(run({ session: selfTimedSession() })).candidate;
	assert.equal(c.gunTimeS, null);
	assert.equal(c.chipTimeS, 250);
	assert.equal(c.durationS, 250);
	assert.equal(c.outsideWindow, false);
	const late = ready(run({ session: selfTimedSession({ window_closes_at: isoAt(t0) }) })).candidate;
	assert.equal(late.outsideWindow, true);
});

test('approval: a timing change goes back to the organiser unless the race auto-approves', () => {
	assert.equal(retimeApproval(false, false), 'pending');
	assert.equal(retimeApproval(false, true), 'pending');
	assert.equal(retimeApproval(true, false), 'approved');
	assert.equal(retimeApproval(true, true), 'unknown', 'self-timed approval rests on the plausibility check');
	assert.equal(retimeApproval(null, false), 'unknown', 'masked from a runner who is not a club admin');
	const o = ready(run({ current: current(), session: session({ is_auto_approve: false }) }));
	assert.equal(o.approval, 'pending');
});

test('an identical result is reported unchanged rather than rewritten', () => {
	const c = ready(run()).candidate;
	const same = current({
		finish_method: 'auto',
		start_detection: c.startDetection,
		finish_detection: c.finishDetection,
		gun_time_s: c.gunTimeS,
		chip_time_s: c.chipTimeS,
		duration_s: c.durationS,
		needs_review: false,
	});
	assert.equal(run({ current: same }).kind, 'unchanged');
});

test('off-track fixes are not offered, and their credit still counts toward coverage', () => {
	const track = straightTrack();
	// A canopy fix far past the finish, between two fixes before it.
	track.splice(10, 0, { ...plane(1100), ts: isoAt(t0 + 47_000), distM: 180, offTrack: true });
	const fixes = retimeFixes(track, 0);
	assert.equal(fixes.length, 53);
	assert.ok(fixes.every((f) => f.lat < plane(1050).lat));
	assert.equal(ready(run({ track })).candidate.finishAt, isoAt(t0 + 255_000));
});

test('smoothed positions are the line positions the crossings are read from', () => {
	// Raw fixes 40 m east of the course, outside the 15 m half-width; the
	// smoother put them on it.
	const track = straightTrack().map((p, i) => ({
		...p,
		...plane(-20 + i * 20, 40),
		smoothedLat: p.lat,
		smoothedLng: p.lng,
	}));
	assert.equal(ready(run({ track })).candidate.finishDetection, 'gate');
	const raw = straightTrack().map((p, i) => ({ ...p, ...plane(-20 + i * 20, 40) }));
	assert.notEqual(run({ track: raw }).kind, 'ready');
});

test('a track without distM is covered by the hop-sum along the line', () => {
	const track = straightTrack().map(({ distM: _d, ...p }) => p);
	assert.equal(ready(run({ track })).candidate.gunTimeS, 285);
});

test('the states a re-time cannot run in', () => {
	assert.deepEqual(run({ session: null }), { kind: 'unavailable', reason: 'no_session' });
	assert.deepEqual(run({ course: null }), { kind: 'unavailable', reason: 'no_course' });
	assert.deepEqual(run({ course: { ...course, finish_line_self_cross: true } }), {
		kind: 'unavailable',
		reason: 'self_cross',
	});
	const noLines = {
		...course,
		start_gate_lat: null,
		finish_gate_lat: null,
	} as RetimeCourse;
	assert.deepEqual(run({ course: noLines }), { kind: 'unavailable', reason: 'no_line' });
	assert.deepEqual(run({ course: { ...course, distance_m: null } }), { kind: 'unavailable', reason: 'no_distance' });
	assert.deepEqual(run({ session: session({ started_at: null }) }), { kind: 'unavailable', reason: 'no_go' });
	assert.deepEqual(run({ track: straightTrack().slice(0, 1) }), { kind: 'unavailable', reason: 'no_track' });
	assert.deepEqual(run({ track: straightTrack().slice(0, 30) }), { kind: 'no_crossing' });
});

test('a run with no linked result belongs to the occurrence whose window or instant it falls in', () => {
	const day = 24 * 3600_000;
	const sessions = [
		{ instance_start: isoAt(t0 - 7 * day), window_opens_at: null, window_closes_at: null },
		{ instance_start: isoAt(t0 - 3 * day), window_opens_at: isoAt(t0 - 3 * day), window_closes_at: isoAt(t0 + day) },
		{ instance_start: isoAt(t0 + 2 * 3600_000), window_opens_at: null, window_closes_at: null },
	];
	assert.equal(raceOccurrenceForRun(sessions, isoAt(t0)), isoAt(t0 - 3 * day), 'the window holds it');
	assert.equal(raceOccurrenceForRun(sessions.slice(2), isoAt(t0)), isoAt(t0 + 2 * 3600_000));
	assert.equal(raceOccurrenceForRun(sessions.slice(0, 1), isoAt(t0)), null, 'a week away is another race');
	assert.equal(raceOccurrenceForRun([], isoAt(t0)), null);
});
