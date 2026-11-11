// Re-time a race result from the run's stored track (issue #1307 M11,
// decisions § 2462). Pure: the track, the race's frozen course, its session
// and the runner's current row go in; what a re-time would write, or why it
// cannot, comes out. The writing is data.ts's `retimeEventResult`; the server's
// race guard derives the gun and chip time again from the crossings written.
//
// The track is read as the segment matcher reads it: on-track fixes only
// (`trackLine`), at their smoothed line positions (`lineLat` / `lineLng`), with
// coverage on the recorder's credited distance (`distM`) when every fix carries
// it and the hop-sum otherwise. Every fix is put on the server clock at its
// `ts` plus the result's persisted `clock_offset_ms`, the offset the device
// filed beside its own crossings. That is the live clock basis but not the
// live instants: the stored `ts` is each fix's own time and the device timed
// the race at each fix's arrival, so a re-time runs ahead of the live result by
// the fix delivery latency (a few hundred ms) and can differ by a second.
// There is no run-level offset anywhere (the runs row and its metadata keep
// none), so a result without one is timed on the recording's own clock and
// says so (`clockBasis: 'device'`).

import type { TrackPoint } from '../types';
import type { Gate } from '../geo/gate_crossing';
import { hasRecordedDistances, trackCumulativeMetres } from '../runs/run_stats';
import { isOffTrack, lineLat, lineLng } from '../runs/track_line';
import { courseGate, type CourseGateColumns, type SessionStartMode } from './course_gates';
import {
	RaceFinishDetector,
	raceLineUsable,
	raceResultTiming,
	type RaceFinish,
	type RaceFix,
} from './race_finish';

/** A runner's own result may be written until this long after the race finished (§ 1849). */
export const RACE_RESULT_WRITE_WINDOW_MS = 24 * 3600 * 1000;

/** The race's frozen copy of one course (`race_session_courses`). */
export interface RetimeCourse extends CourseGateColumns {
	course_id: string;
	distance_m: number | null;
	finish_lat: number | null;
	finish_lng: number | null;
	finish_line_self_cross: boolean;
	/** The lap minimum the race froze (decisions § 2472); null for none. */
	finish_min_coverage_m: number | null;
}

/** The session columns a re-time reads (`race_sessions_redacted`). */
export interface RetimeSession {
	status: string;
	start_mode?: SessionStartMode | null;
	started_at: string | null;
	finished_at: string | null;
	window_opens_at?: string | null;
	window_closes_at?: string | null;
	/** Masked to null for a runner who is not a club admin. */
	is_auto_approve: boolean | null;
}

/** The runner's current row as `event_results_redacted` shows it to them. */
export interface RetimeCurrent {
	finisher_status: string | null;
	finish_method: string | null;
	start_detection: string | null;
	finish_detection: string | null;
	needs_review: boolean | null;
	duration_s: number | null;
	gun_time_s: number | null;
	chip_time_s: number | null;
	clock_offset_ms: number | null;
	/** The run the row was filed with, when it was. */
	run_id?: string | null;
}

export type RetimeStartDetection = 'gate' | 'device';
export type RetimeFinishDetection = 'gate' | 'zone';

/** Where the fixes' clock came from: the result's persisted offset, or none. */
export type RetimeClockBasis = 'result' | 'device';

/**
 * Whether the row goes back to the organiser. `unknown` when the runner
 * cannot see the session's auto-approve flag (it is masked to club admins)
 * or when a self-timed result's approval rests on the server's plausibility
 * check.
 */
export type RetimeApproval = 'pending' | 'approved' | 'unknown';

export interface RetimeCandidate {
	startAt: string;
	finishAt: string;
	startDetection: RetimeStartDetection;
	finishDetection: RetimeFinishDetection;
	gunTimeS: number | null;
	chipTimeS: number | null;
	durationS: number;
	/** The offset the fixes were timed under; null on the recording's own clock. */
	clockOffsetMs: number | null;
	clockBasis: RetimeClockBasis;
	/** A crossing across a gap in the fixes; the server's review flag is the guard. */
	gapped: boolean;
	/** A self-timed start outside the window, which the server sends to review (M6). */
	outsideWindow: boolean;
}

export type RetimeUnavailableReason =
	| 'no_session'
	| 'no_course'
	| 'self_cross'
	| 'no_line'
	| 'no_distance'
	| 'no_go'
	| 'no_track';

export type RetimeLockReason = 'protected' | 'host';

export type RetimeOutcome =
	| { kind: 'unavailable'; reason: RetimeUnavailableReason }
	| { kind: 'closed' }
	| { kind: 'no_crossing' }
	| { kind: 'undone' }
	| { kind: 'locked'; reason: RetimeLockReason; candidate: RetimeCandidate }
	| { kind: 'unchanged'; candidate: RetimeCandidate }
	| { kind: 'ready'; candidate: RetimeCandidate; approval: RetimeApproval };

export interface RetimeInput {
	track: readonly TrackPoint[];
	/** The run's `started_at`: its Start press, on the device clock. */
	runStartedAt: string;
	session: RetimeSession | null;
	course: RetimeCourse | null;
	current: RetimeCurrent | null;
	/** This run's id: a protected row filed with it is the same attempt. */
	runId?: string | null;
	/**
	 * `runs.metadata.race_undone_finish_at`: the line finish the runner undid
	 * with "Not finished? Resume", on the server clock. A finish the track
	 * gives at or before it is that same finish, not a new one.
	 */
	undoneFinishAt?: string | null;
	nowMs: number;
}

/** How far after the undone instant a finish still reads as the undone one: the stored track's fix times run ahead of the live arrival times, and smoothing moves a crossing by a fraction of a second. */
export const RETIME_UNDONE_TOLERANCE_MS = 2000;

function ms(iso: string | null | undefined): number | null {
	if (!iso) return null;
	const t = Date.parse(iso);
	return Number.isFinite(t) ? t : null;
}

/**
 * [ms] keeping a timestamptz's microseconds as a fraction: GO is stamped by
 * `now()`, and the server's gun time floors the difference at microsecond
 * precision, so truncating GO to the millisecond can put the client a second
 * off the server on 1 race in 1000.
 */
export function msExact(iso: string | null | undefined): number | null {
	const t = ms(iso);
	if (t === null || !iso) return t;
	const frac = /\.(\d+)/.exec(iso)?.[1] ?? '';
	return frac.length > 3 ? t + Number(`0.${frac.slice(3)}`) : t;
}

/** The Start press on the server clock; the first fix when the run has no parseable start. */
function pressServerMs(runStartedAt: string, fixes: readonly RaceFix[], offsetMs: number): number {
	const press = ms(runStartedAt);
	return press === null ? fixes[0].atMs : press + offsetMs;
}

function iso(atMs: number): string {
	return new Date(atMs).toISOString();
}

/** Whether a runner's own write would be refused as past the 24 h window (§ 1849). */
export function retimeWindowClosed(session: RetimeSession, nowMs: number): boolean {
	if (session.status !== 'finished') return false;
	const fin = ms(session.finished_at);
	return fin !== null && fin < nowMs - RACE_RESULT_WRITE_WINDOW_MS;
}

/** How far a run's start may sit from a race's instant and still be that race, when no window holds it. */
export const RACE_OCCURRENCE_MATCH_MS = 24 * 3600 * 1000;

/**
 * Which occurrence of the run's event a run with no linked result belongs to:
 * the one whose self-timed window holds the run's start, else the one whose
 * instant is nearest it within RACE_OCCURRENCE_MATCH_MS. Null for none.
 */
export function raceOccurrenceForRun(
	sessions: readonly {
		instance_start: string | null;
		window_opens_at?: string | null;
		window_closes_at?: string | null;
	}[],
	runStartedAt: string,
): string | null {
	const run = ms(runStartedAt);
	if (run === null) return null;
	for (const s of sessions) {
		const opens = ms(s.window_opens_at);
		const closes = ms(s.window_closes_at);
		if (s.instance_start !== null && opens !== null && closes !== null && run >= opens && run < closes) {
			return s.instance_start;
		}
	}
	let best: string | null = null;
	let bestGap = Infinity;
	const byInstant = [...sessions].sort((a, b) => (ms(a.instance_start) ?? 0) - (ms(b.instance_start) ?? 0));
	for (const s of byInstant) {
		const at = ms(s.instance_start);
		if (at === null || s.instance_start === null) continue;
		const gap = Math.abs(run - at);
		if (gap <= RACE_OCCURRENCE_MATCH_MS && gap < bestGap) {
			best = s.instance_start;
			bestGap = gap;
		}
	}
	return best;
}

/**
 * The fixes a re-time offers the detector: on-track only, at their line
 * positions, timed at `ts` + offsetMs, covered on the full track's axis (the
 * recorder's `distM` when every fix carries it, so an off-track fix's credit
 * still counts toward the ones after it; else the hop-sum along the line).
 * A fix with no parseable `ts` is skipped.
 */
export function retimeFixes(track: readonly TrackPoint[], offsetMs: number): RaceFix[] {
	const recorded = hasRecordedDistances(track);
	const source = recorded ? track : track.filter((p) => !isOffTrack(p));
	const covered = trackCumulativeMetres(source);
	const out: RaceFix[] = [];
	source.forEach((p, i) => {
		if (recorded && isOffTrack(p)) return;
		const at = ms(p.ts);
		if (at === null) return;
		out.push({ lat: lineLat(p), lng: lineLng(p), atMs: at + offsetMs, coveredM: covered[i] });
	});
	return out;
}

/**
 * A row only a better line-timed attempt may replace (#1306 M5): finished,
 * started and finished by the lines, and not waiting on review.
 */
export function retimeProtected(current: RetimeCurrent): boolean {
	return (
		current.finisher_status === 'finished' &&
		current.start_detection === 'gate' &&
		current.finish_detection === 'gate' &&
		current.needs_review !== true
	);
}

/**
 * Whether the re-time may replace the current row. Always over no row, a DNF
 * (the host's close-time fill included), a pending manual or typed time, a
 * zone finish and a row waiting on review. Never over a finish the organiser
 * set. A protected row: in a self-timed race only by a faster gate-to-gate
 * finish (decision 4b, the server's lock rule), from another run (the same
 * attempt re-timed on its fix times would beat itself by the fix latency) and
 * with its start inside the window (outside it the server sends it to review
 * and its lock keeps the old row); in a gun race not at all, because the
 * device already timed that one attempt by the same lines.
 */
export function retimeLock(
	current: RetimeCurrent | null,
	candidate: RetimeCandidate,
	selfTimed: boolean,
	runId: string | null = null,
): RetimeLockReason | null {
	if (current === null || current.finisher_status !== 'finished') return null;
	if (current.finish_method === 'host') return 'host';
	if (!retimeProtected(current)) return null;
	if (
		selfTimed &&
		!(runId !== null && current.run_id === runId) &&
		!candidate.outsideWindow &&
		candidate.startDetection === 'gate' &&
		candidate.finishDetection === 'gate' &&
		current.duration_s !== null &&
		candidate.durationS < current.duration_s
	) {
		return null;
	}
	return 'protected';
}

/**
 * Whether the row will need the organiser again: the server resets approval on
 * any timing change of a race that is not auto-approved (#1306 M7), and a
 * self-timed result is approved only when its crossings pass the server's
 * plausibility check, which the client cannot run.
 */
export function retimeApproval(autoApprove: boolean | null, selfTimed: boolean): RetimeApproval {
	if (autoApprove === false) return 'pending';
	if (autoApprove === null || selfTimed) return 'unknown';
	return 'approved';
}

function sameTiming(current: RetimeCurrent, c: RetimeCandidate): boolean {
	return (
		current.finisher_status === 'finished' &&
		current.finish_method === 'auto' &&
		current.start_detection === c.startDetection &&
		current.finish_detection === c.finishDetection &&
		current.gun_time_s === c.gunTimeS &&
		current.chip_time_s === c.chipTimeS &&
		current.duration_s === c.durationS
	);
}

function candidateOf(
	finish: RaceFinish,
	goMs: number | null,
	pressMs: number,
	offsetMs: number | null,
	session: RetimeSession,
	selfTimed: boolean,
): RetimeCandidate {
	const startMs = finish.start?.atMs ?? pressMs;
	const timing = raceResultTiming({
		outcome: { finisherStatus: 'finished', method: 'auto', finishAtMs: finish.atMs },
		gunAtMs: selfTimed ? null : goMs,
		recordingStartedAtMs: pressMs,
		startAtMs: finish.start?.atMs ?? null,
		elapsedS: 0,
	});
	const opens = ms(session.window_opens_at);
	const closes = ms(session.window_closes_at);
	return {
		startAt: iso(startMs),
		finishAt: iso(finish.atMs),
		startDetection: finish.start !== null ? 'gate' : 'device',
		finishDetection: finish.detection,
		gunTimeS: timing.gunTimeS,
		chipTimeS: timing.chipTimeS,
		durationS: timing.durationS,
		clockOffsetMs: offsetMs,
		clockBasis: offsetMs === null ? 'device' : 'result',
		gapped: finish.gapped || finish.start?.gapped === true,
		outsideWindow:
			selfTimed && opens !== null && closes !== null && (startMs < opens || startMs >= closes),
	};
}

export function computeRetime(i: RetimeInput): RetimeOutcome {
	const session = i.session;
	if (session === null) return { kind: 'unavailable', reason: 'no_session' };
	if (retimeWindowClosed(session, i.nowMs)) return { kind: 'closed' };
	const course = i.course;
	if (course === null) return { kind: 'unavailable', reason: 'no_course' };
	// A finish line the route crosses before its end finishes by hand only,
	// as on the phone (decisions § 2450).
	if (course.finish_line_self_cross) return { kind: 'unavailable', reason: 'self_cross' };

	const selfTimed = session.start_mode === 'self_timed';
	const startGate: Gate | null = courseGate(course, 'start');
	const finishGate: Gate | null = courseGate(course, 'finish');
	const hasStart = raceLineUsable(startGate);
	const hasFinish = raceLineUsable(finishGate);
	if (selfTimed ? !hasStart : !hasStart && !hasFinish) return { kind: 'unavailable', reason: 'no_line' };

	const distance = course.distance_m;
	if (distance === null || !Number.isFinite(distance) || distance <= 0) {
		return { kind: 'unavailable', reason: 'no_distance' };
	}
	const finishLat = course.finish_lat ?? finishGate?.lat ?? null;
	const finishLng = course.finish_lng ?? finishGate?.lng ?? null;
	if (finishLat === null || finishLng === null) return { kind: 'unavailable', reason: 'no_line' };

	const goMs = selfTimed ? null : msExact(session.started_at);
	if (!selfTimed && goMs === null) return { kind: 'unavailable', reason: 'no_go' };

	const offsetMs = i.current?.clock_offset_ms ?? null;
	const fixes = retimeFixes(i.track, offsetMs ?? 0);
	if (fixes.length < 2) return { kind: 'unavailable', reason: 'no_track' };
	const pressMs = pressServerMs(i.runStartedAt, fixes, offsetMs ?? 0);

	const detector = new RaceFinishDetector({
		finishLat,
		finishLng,
		courseDistanceM: distance,
		startGate,
		finishGate,
		mode: selfTimed ? 'selfTimed' : 'gun',
		goAtMs: goMs,
		minCoverageM: course.finish_min_coverage_m,
	});
	let finish: RaceFinish | null = null;
	for (const f of fixes) {
		finish = detector.offer(f);
		if (finish !== null) break;
	}
	finish ??= detector.settle();
	if (finish === null) return { kind: 'no_crossing' };
	const undone = ms(i.undoneFinishAt);
	if (undone !== null && finish.atMs <= undone + RETIME_UNDONE_TOLERANCE_MS) return { kind: 'undone' };

	const candidate = candidateOf(finish, goMs, pressMs, offsetMs, session, selfTimed);
	if (i.current !== null && sameTiming(i.current, candidate)) return { kind: 'unchanged', candidate };
	const lock = retimeLock(i.current, candidate, selfTimed, i.runId ?? null);
	if (lock !== null) return { kind: 'locked', reason: lock, candidate };
	return { kind: 'ready', candidate, approval: retimeApproval(session.is_auto_approve, selfTimed) };
}
