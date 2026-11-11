// Finish-line detection and race timing, spec `race_finish v3` (issue #1304,
// decisions § 2378, § 2472). Pure: no clock, no I/O. Every instant is epoch
// milliseconds handed in, so the same fixes always produce the same finish,
// which is what re-timing a race from a saved track (#1307) relies on.
//
// Parity pair with apps/mobile_android/lib/race_finish.dart, which is itself
// paired with Wear OS's RaceFinish.kt. All three read
// fixtures/race_finish_cases.json, so a rule changes there or nowhere.

import { haversineMetres } from '../runs/run_stats';
import {
	GateCrossingDetector,
	gateProjection,
	gateUsable,
	type Gate,
	type GateCrossing,
} from '../geo/gate_crossing';

/** A fix within this distance of the course's last point can be the finish. */
export const RACE_FINISH_ZONE_M = 30;

/**
 * Share of the course distance a runner must have covered before a pass
 * through the finish zone, or a line finish with no committed start, counts.
 */
export const RACE_FINISH_MIN_COVERAGE = 0.9;

/**
 * Share of the course distance a LINE finish needs when coverage is measured
 * from a committed start. Provisional until the #1304 calibration session:
 * #1303 gives 50-60 %, and this takes the cautious end.
 */
export const RACE_FINISH_MIN_COVERAGE_WITH_START = 0.6;

/**
 * Covered distance a forward start-line crossing after GO must be followed
 * by, with no backward crossing, before it is the runner's start.
 * Provisional until the #1304 calibration session.
 */
export const RACE_START_COMMIT_M = 50;

/**
 * Share of one lap a lap course's last lap must show when its count is one
 * pass short (a crossing dropped by a wide pass or a fix gap), and the share
 * of a lap a gun runner must cover after GO before their first start crossing
 * is taken for a missed one. Between the honest pass a lap early, a whole lap
 * short, and the finish, with three quarters of a lap of GPS margin.
 */
export const RACE_LAP_SHORT_SHARE = 0.75;

/** A recording that starts more than this long after GO is a late start. */
export const RACE_LATE_START_AFTER_MS = 300_000;

/** A first fix more than this far from the course start is a late start. */
export const RACE_LATE_START_FAR_M = 200;

/** Great-circle distance in metres (R = 6371000). */
export function raceDistanceM(lat1: number, lng1: number, lat2: number, lng2: number): number {
	return haversineMetres(lat1, lng1, lat2, lng2);
}

/** One fix: where, when (device clock, epoch ms), and how far the recording had covered. */
export interface RaceFix {
	lat: number;
	lng: number;
	atMs: number;
	coveredM: number;
}

/**
 * Host GO and Scheduled GO are both `gun`: the server's GO exists. A
 * `selfTimed` race has none; each runner's start-line crossing starts their
 * clock.
 */
export type RaceStartMode = 'gun' | 'selfTimed';

/**
 * A forward start-line crossing, or GO itself for a runner already past the
 * line at GO. Both are `start_detection = 'gate'`; no start at all is
 * `'device'` (the runner's own Start press).
 */
export type RaceStartKind = 'line' | 'go';

export interface RaceStart {
	atMs: number;
	coveredM: number;
	kind: RaceStartKind;
	gapped: boolean;
}

export type RaceFinishDetection = 'zone' | 'gate';

/**
 * The closest-approach fix in the zone, or the interpolated finish-line
 * crossing. For a line finish distanceToFinishM is the crossing's lateral
 * offset from the line's centre. start is null when coverage ran from the
 * Start press.
 */
export interface RaceFinish {
	atMs: number;
	distanceToFinishM: number;
	coveredM: number;
	detection: RaceFinishDetection;
	start: RaceStart | null;
	gapped: boolean;
}

/** Inclusive at RACE_FINISH_ZONE_M; a non-finite distance is outside. */
export function raceInFinishZone(distanceM: number): boolean {
	return distanceM <= RACE_FINISH_ZONE_M;
}

/**
 * Whether coveredM clears the 90 % gate. An unknown course distance cannot
 * gate, so it passes: a runner is never marked DNF for data the course never
 * carried.
 */
export function raceCoverageMet(coveredM: number, courseDistanceM: number | null): boolean {
	const d = courseDistanceM;
	if (d === null || !Number.isFinite(d) || d <= 0) return true;
	return coveredM >= d * RACE_FINISH_MIN_COVERAGE;
}

/** A line a race can be timed by: usable by gate_crossing, with a positive half-width. */
export function raceLineUsable(gate: Gate | null | undefined): gate is Gate {
	return gate != null && gateUsable(gate) && gate.halfWidthM > 0;
}

export interface RaceFinishDetectorOptions {
	finishLat: number;
	finishLng: number;
	courseDistanceM: number;
	startGate?: Gate | null;
	finishGate?: Gate | null;
	mode?: RaceStartMode;
	/** GO on the device clock the fixes are timed on. */
	goAtMs?: number | null;
	/**
	 * The course's lap count (`race_session_courses.finish_lap_count`): the
	 * line finish is this many forward finish passes from the committed start.
	 * Null when the race froze none, and the detector then scales by the
	 * runner's own measured lap (decisions § 2472).
	 */
	lapCount?: number | null;
}

type StartState = 'preGo' | 'seeking' | 'pending' | 'committed';

interface Sampled {
	fix: RaceFix;
	s: number;
}

interface CoverageBase {
	fromM: number;
	start: RaceStart | null;
}

function lineStart(x: GateCrossing): RaceStart {
	return { atMs: Math.round(x.tMs), coveredM: x.coveredM, kind: 'line', gapped: x.gapped };
}

/**
 * Finish detection over a stream of fixes. The rules are the Dart twin's
 * (race_finish.dart's class comment carries them in full) and decisions
 * § 2378's: without any line in a gun mode it is v1's closest approach; with
 * lines the start is a committed start-line crossing (or GO for a runner
 * already past the line), coverage runs from it, the finish is the first
 * forward finish-line crossing that clears coverage, and with a finish line
 * the zone decides only on settle().
 */
export class RaceFinishDetector {
	readonly finishLat: number;
	readonly finishLng: number;
	readonly courseDistanceM: number;
	readonly startGate: Gate | null;
	readonly finishGate: Gate | null;
	readonly mode: RaceStartMode;
	readonly lapCount: number | null;

	/** Metres between the two lines' centres; 0 without both. */
	private readonly sepM: number;
	private readonly startLine: GateCrossingDetector | null;
	private readonly finishLine: GateCrossingDetector | null;

	private best: RaceFix | null = null;
	private bestD = Infinity;
	private bestStart: RaceStart | null = null;
	private finish: RaceFinish | null = null;

	private goMs: number | null = null;
	private held: RaceFix[] = [];
	private closed = false;
	private prev: Sampled | null = null;
	private state: StartState = 'preGo';
	private pending: GateCrossing | null = null;
	private committed: RaceStart | null = null;
	private goCoveredM = 0;
	private passes = 0;
	private lastPassM: number | null = null;
	private lapM: number | null = null;
	private finishSeen = false;

	constructor(o: RaceFinishDetectorOptions) {
		this.finishLat = o.finishLat;
		this.finishLng = o.finishLng;
		this.courseDistanceM = o.courseDistanceM;
		this.startGate = raceLineUsable(o.startGate) ? o.startGate : null;
		this.finishGate = raceLineUsable(o.finishGate) ? o.finishGate : null;
		this.mode = o.mode ?? 'gun';
		const k = o.lapCount;
		this.lapCount =
			this.finishGate !== null && k != null && Number.isInteger(k) && k >= 2 ? k : null;
		if (this.mode === 'selfTimed') this.state = 'seeking';
		const sg = this.startGate;
		const fg = this.finishGate;
		this.sepM = sg !== null && fg !== null ? raceDistanceM(sg.lat, sg.lng, fg.lat, fg.lng) : 0;
		this.startLine = this.startGate ? new GateCrossingDetector(this.startGate) : null;
		this.finishLine = this.finishGate ? new GateCrossingDetector(this.finishGate) : null;
		if (o.goAtMs != null) this.setGo(o.goAtMs);
	}

	private get v1(): boolean {
		return this.mode === 'gun' && this.startGate === null && this.finishGate === null;
	}

	private get awaitingGo(): boolean {
		return this.mode === 'gun' && this.startGate !== null && this.goMs === null;
	}

	/** The finalised finish, once there is one. */
	get result(): RaceFinish | null {
		return this.finish;
	}

	/** The best in-zone fix so far, while the approach is still open. */
	get candidate(): RaceFinish | null {
		const best = this.best;
		if (this.finish !== null || this.closed || best === null) return null;
		return this.zoneFinish(best);
	}

	/**
	 * The start a finish would be measured from right now: the committed start.
	 * A self-timed start a backward crossing has re-armed stays it until a new
	 * forward crossing commits. Null for the Start press, and while the first
	 * crossing is still committing.
	 */
	get start(): RaceStart | null {
		return this.committed;
	}

	/** Returns the finish on the call that finalises it, and null on every other call. */
	offer(fix: RaceFix): RaceFinish | null {
		if (this.v1) return this.offerV1(fix);
		if (this.finish !== null || this.closed) return null;
		if (this.awaitingGo) {
			this.held.push(fix);
			return null;
		}
		return this.process(fix);
	}

	/**
	 * GO, on the device clock. Fixed once set. With a start line in a gun mode
	 * the fixes held until now are replayed; returns the finish when that
	 * replay finalises one.
	 */
	setGo(atMs: number): RaceFinish | null {
		if (this.goMs !== null) return null;
		this.goMs = atMs;
		if (this.held.length === 0) return null;
		const held = this.held;
		this.held = [];
		if (this.finish !== null || this.closed) return null;
		for (const fix of held) {
			const r = this.process(fix);
			if (r !== null) return r;
		}
		return null;
	}

	/**
	 * The recording stopped: finalise an open zone approach. With lines the
	 * stream is closed either way; a gun race whose GO never arrived finishes
	 * nothing automatically.
	 */
	settle(): RaceFinish | null {
		if (this.finish !== null) return this.finish;
		if (!this.v1) {
			this.closed = true;
			this.held = [];
		}
		const best = this.best;
		return best === null ? null : (this.finish = this.zoneFinish(best));
	}

	private offerV1(fix: RaceFix): RaceFinish | null {
		if (this.finish !== null) return null;
		if (
			!Number.isFinite(fix.lat) ||
			!Number.isFinite(fix.lng) ||
			!Number.isFinite(fix.coveredM) ||
			!Number.isFinite(fix.atMs)
		) {
			return null;
		}
		const d = raceDistanceM(fix.lat, fix.lng, this.finishLat, this.finishLng);
		const qualifies = raceInFinishZone(d) && this.covers(0, fix.coveredM, RACE_FINISH_MIN_COVERAGE);
		const best = this.best;
		if (best !== null && (!qualifies || d > this.bestD)) return (this.finish = this.zoneFinish(best));
		if (qualifies && (best === null || d < this.bestD)) {
			this.best = fix;
			this.bestD = d;
		}
		return null;
	}

	private process(fix: RaceFix): RaceFinish | null {
		if (!Number.isFinite(fix.lat) || !Number.isFinite(fix.lng) || !Number.isFinite(fix.coveredM)) {
			return null;
		}
		if (!Number.isFinite(fix.atMs)) return null;
		const t = fix.atMs;
		const prev = this.prev;
		if (prev !== null && t <= prev.fix.atMs) return null;
		const sg = this.startGate;
		const cur: Sampled = { fix, s: sg === null ? 0 : gateProjection(sg, fix.lat, fix.lng).s };
		this.prev = cur;

		const go = this.goMs;
		if (this.mode === 'gun' && sg !== null && this.state === 'preGo' && go !== null && t >= go) {
			this.resolveGo(prev, cur, go);
		}

		const gf = { lat: fix.lat, lng: fix.lng, tMs: t, coveredM: fix.coveredM };
		const sc = this.startLine?.offer(gf) ?? null;
		const fc = this.finishLine?.offer(gf) ?? null;
		if (sc !== null && fc !== null && (sc.tMs < fc.tMs || (sc.tMs === fc.tMs && this.mode === 'gun'))) {
			this.onStartCrossing(sc);
			this.onFinishCrossing(fc);
		} else {
			if (fc !== null) this.onFinishCrossing(fc);
			if (this.finish === null && sc !== null) this.onStartCrossing(sc);
		}
		if (this.finish !== null) return this.finish;

		this.advanceCommit(fix.coveredM);
		this.zone(fix);
		return this.finish;
	}

	private resolveGo(prev: Sampled | null, cur: Sampled, go: number): void {
		let sGo = cur.s;
		let cGo = cur.fix.coveredM;
		if (prev !== null && prev.fix.atMs < go) {
			const f = (go - prev.fix.atMs) / (cur.fix.atMs - prev.fix.atMs);
			sGo = prev.s + f * (cur.s - prev.s);
			cGo = prev.fix.coveredM + f * (cur.fix.coveredM - prev.fix.coveredM);
		}
		if (sGo >= 0) {
			this.committed = { atMs: go, coveredM: cGo, kind: 'go', gapped: false };
			this.state = 'committed';
		} else {
			this.goCoveredM = cGo;
			this.state = 'seeking';
		}
	}

	private advanceCommit(coveredM: number): void {
		const p = this.pending;
		if (this.state !== 'pending' || p === null) return;
		if (coveredM >= p.coveredM + RACE_START_COMMIT_M) {
			if (this.committed !== null) this.forgetLaps();
			this.committed = lineStart(p);
			this.pending = null;
			this.state = 'committed';
		}
	}

	private onStartCrossing(x: GateCrossing): void {
		this.advanceCommit(x.coveredM);
		if (this.mode === 'selfTimed') {
			if (x.direction === 'forward') {
				if (this.state === 'committed') return;
				this.pending = x;
				this.state = 'pending';
			} else {
				if (this.startHeld(x.coveredM)) return;
				this.pending = null;
				this.state = 'seeking';
			}
			return;
		}
		if (this.state !== 'seeking' && this.state !== 'pending') return;
		if (x.direction === 'forward' && this.missedStart(x.coveredM)) {
			this.committed = { atMs: this.goMs as number, coveredM: this.goCoveredM, kind: 'go', gapped: false };
			this.pending = null;
			this.state = 'committed';
			return;
		}
		if (x.direction === 'forward') {
			this.pending = x;
			this.state = 'pending';
		} else {
			this.pending = null;
			this.state = 'seeking';
		}
	}

	private onFinishCrossing(x: GateCrossing): void {
		if (x.direction !== 'forward') return;
		this.advanceCommit(x.coveredM);
		const base = this.base(x.tMs);
		if (base === null) return;
		if (base.start !== null) this.finishSeen = true;
		const pass = this.countPass(base, x.coveredM);
		if (this.lapCount !== null && base.start !== null && (!pass || this.passes < this.lapCount)) return;
		const share = base.start !== null ? RACE_FINISH_MIN_COVERAGE_WITH_START : RACE_FINISH_MIN_COVERAGE;
		if (!this.covers(base.fromM, x.coveredM, share)) return;
		this.finish = {
			atMs: Math.round(x.tMs),
			distanceToFinishM: Math.abs(x.offsetM),
			coveredM: x.coveredM,
			detection: 'gate',
			start: base.start,
			gapped: x.gapped,
		};
	}

	private zone(fix: RaceFix): void {
		const d = raceDistanceM(fix.lat, fix.lng, this.finishLat, this.finishLng);
		const base = this.base(fix.atMs);
		const qualifies =
			raceInFinishZone(d) &&
			base !== null &&
			this.coversShare(base.fromM, fix.coveredM, RACE_FINISH_MIN_COVERAGE) &&
			this.lapsMet(fix.coveredM) !== false;
		const best = this.best;
		if (this.finishGate !== null) {
			if (!qualifies) {
				this.best = null;
				this.bestD = Infinity;
				this.bestStart = null;
			} else if (best === null || d < this.bestD) {
				this.best = fix;
				this.bestD = d;
				this.bestStart = base.start;
			}
			return;
		}
		if (best !== null && (!qualifies || d > this.bestD)) {
			this.finish = this.zoneFinish(best);
			return;
		}
		if (qualifies && (best === null || d < this.bestD)) {
			this.best = fix;
			this.bestD = d;
			this.bestStart = base.start;
		}
	}

	/** Where coverage counts from at tMs, and its start; null when no finish can count then. */
	private base(tMs: number): CoverageBase | null {
		if (this.mode === 'selfTimed') {
			const c = this.committed;
			return c === null ? null : { fromM: c.coveredM, start: c };
		}
		const go = this.goMs;
		if (go !== null && tMs < go) return null;
		if (this.startGate === null) return { fromM: 0, start: null };
		if (go === null) return null;
		if (this.state === 'committed' && this.committed !== null) {
			return { fromM: this.committed.coveredM, start: this.committed };
		}
		if (this.state === 'seeking') return { fromM: this.goCoveredM, start: null };
		return null;
	}

	/**
	 * A self-timed start a backward crossing may no longer re-arm: the runner
	 * has passed the finish line forward since it, or covered the no-start
	 * share of the course, so they are on a later lap or coming home.
	 */
	private startHeld(coveredM: number): boolean {
		const c = this.committed;
		if (c === null) return false;
		if (this.finishSeen) return true;
		const d = this.courseDistanceM;
		return Number.isFinite(d) && d > 0 && coveredM - c.coveredM >= d * RACE_FINISH_MIN_COVERAGE;
	}

	/**
	 * Whether a forward finish crossing at coveredM is a lap pass: from a
	 * committed start, at least the lines' separation plus RACE_START_COMMIT_M
	 * past it (so the start's own pass is not one), and RACE_START_COMMIT_M
	 * past the last pass (so a wobble across the line is one pass). Records it.
	 */
	private countPass(base: CoverageBase, coveredM: number): boolean {
		if (base.start === null) return false;
		if (coveredM - base.fromM < this.sepM + RACE_START_COMMIT_M) return false;
		const last = this.lastPassM;
		if (last !== null && coveredM - last < RACE_START_COMMIT_M) return false;
		this.lapM = last === null ? coveredM - base.fromM - this.sepM : coveredM - last;
		this.lastPassM = coveredM;
		this.passes += 1;
		return true;
	}

	private forgetLaps(): void {
		this.passes = 0;
		this.lastPassM = null;
		this.lapM = null;
		this.finishSeen = false;
	}

	/**
	 * Whether coveredM completes the laps, for a stop or a zone finish: with a
	 * lap count, lapsCounted; with none, from the second pass on, the course
	 * less RACE_LAP_SHORT_SHARE of the lap just run (a wider margin than the
	 * line's half lap, so a GPS that under-reads is not a DNF at the stop).
	 * Null when no lap rule applies (no lap known, or no committed start to
	 * count from).
	 */
	lapsMet(coveredM: number): boolean | null {
		const b = this.base(Infinity);
		if (b === null) return null;
		if (this.lapCount !== null) return b.start === null ? null : this.lapsCounted(b.fromM, coveredM);
		const d = this.courseDistanceM;
		const lap = this.lapM;
		if (this.passes < 2 || lap === null || !Number.isFinite(d) || d <= 0) return null;
		return coveredM - b.fromM >= d - RACE_LAP_SHORT_SHARE * lap;
	}

	/**
	 * Every lap counted, or one short (a crossing dropped by a wide pass or a
	 * fix gap) with the course, less the lines' separation, covered within
	 * RACE_LAP_SHORT_SHARE of a lap of the frozen count's own (D / k): an
	 * honest pass a lap early is a whole lap short, so it is not taken. Only a
	 * stop and the zone use the one-short path; the line finish needs every
	 * pass, because against a GPS that over-reads the path's margin is
	 * 0.25 / (k - 1) of the course (2.8 % at 10 laps, 1 % at 25), too thin for
	 * a finish nobody asked for.
	 */
	private lapsCounted(fromM: number, coveredM: number): boolean {
		const k = this.lapCount;
		if (k === null) return false;
		if (this.passes >= k) return true;
		const d = this.courseDistanceM;
		if (this.passes < k - 1 || !Number.isFinite(d) || d <= 0) return false;
		return coveredM - fromM - this.sepM >= d - (RACE_LAP_SHORT_SHARE * d) / k;
	}

	/**
	 * A gun runner on a counted lap course whose first forward start crossing
	 * comes RACE_LAP_SHORT_SHARE of a lap or more after GO crossed the line
	 * once already unseen: their start is GO, so the lap is not lost.
	 */
	private missedStart(coveredM: number): boolean {
		const k = this.lapCount;
		const d = this.courseDistanceM;
		if (this.mode !== 'gun' || k === null || this.goMs === null || this.committed !== null) return false;
		if (!Number.isFinite(d) || d <= 0) return false;
		return coveredM - this.goCoveredM >= (RACE_LAP_SHORT_SHARE * d) / k;
	}

	/**
	 * Covered distance from the base a finish needs at share; null when nothing
	 * can gate. With no lap count frozen, from the second pass on, the lap
	 * just run raises it to the course less half that lap (the runner's own
	 * lap, so a course whose laps differ is judged by the latest one). A first
	 * pass needs no floor: on a course of two or more laps it is at most half
	 * the course, under the share, and a single loop keeps the share's margin.
	 */
	private required(share: number): number | null {
		const d = this.courseDistanceM;
		const known = Number.isFinite(d) && d > 0;
		const lap = this.lapCount === null && this.passes >= 2 ? this.lapM : null;
		const floor = known && lap !== null ? d - lap / 2 : null;
		if (!known) return null;
		return floor === null ? d * share : Math.max(d * share, floor);
	}

	private covers(fromM: number, coveredM: number, share: number): boolean {
		const need = this.required(share);
		return need === null || coveredM - fromM >= need;
	}

	/** The share alone, without the line's lap floor: the zone's distance gate, beside lapsMet. */
	private coversShare(fromM: number, coveredM: number, share: number): boolean {
		const d = this.courseDistanceM;
		return !Number.isFinite(d) || d <= 0 || coveredM - fromM >= d * share;
	}

	private zoneFinish(best: RaceFix): RaceFinish {
		return {
			atMs: best.atMs,
			distanceToFinishM: this.bestD,
			coveredM: best.coveredM,
			detection: 'zone',
			start: this.bestStart,
			gapped: false,
		};
	}
}

/**
 * Whether a racer's start should be flagged: recording began more than
 * RACE_LATE_START_AFTER_MS after GO, or the first fix was more than
 * RACE_LATE_START_FAR_M from the course start. Both instants on the server
 * clock. An unknown distance does not flag.
 */
export function raceStartFlagged(
	gunAtMs: number,
	recordingStartedAtMs: number,
	firstFixFromStartM: number | null,
): boolean {
	if (recordingStartedAtMs - gunAtMs > RACE_LATE_START_AFTER_MS) return true;
	const d = firstFixFromStartM;
	return d !== null && Number.isFinite(d) && d > RACE_LATE_START_FAR_M;
}

/**
 * Device-to-server clock offset from request round trips: the server stamped
 * somewhere inside the round trip, so its midpoint is the best device-side
 * estimate. The shortest round trip wins; an equal one replaces.
 */
export class ServerClockOffset {
	private offset: number | null = null;
	private bestRtt: number | null = null;

	get known(): boolean {
		return this.offset !== null;
	}

	/** Server minus device, in ms; 0 until a sample lands. */
	get offsetMs(): number {
		return this.offset ?? 0;
	}

	addSample(sentAtMs: number, receivedAtMs: number, serverAtMs: number): void {
		const rtt = receivedAtMs - sentAtMs;
		if (rtt < 0) return;
		if (this.bestRtt !== null && rtt > this.bestRtt) return;
		this.offset = serverAtMs - (sentAtMs + rtt / 2);
		this.bestRtt = rtt;
	}

	toServer(deviceMs: number): number {
		return deviceMs + this.offsetMs;
	}
}

/**
 * Seconds from GO (server clock) to a device-clock finish moved onto the
 * server clock by clockOffsetMs. Null, not clamped, when negative. A non-finite
 * instant (which a Dart DateTime or a Kotlin Long cannot hold) is null too.
 */
export function raceGunTimeS(finishAtDeviceMs: number, gunAtMs: number, clockOffsetMs = 0): number | null {
	const ms = finishAtDeviceMs + clockOffsetMs - gunAtMs;
	return !Number.isFinite(ms) || ms < 0 ? null : Math.floor(ms / 1000);
}

/** Seconds from a device-clock start to the finish, pauses included. Null when negative or not finite. */
export function raceChipTimeS(finishAtDeviceMs: number, startedAtMs: number): number | null {
	const ms = finishAtDeviceMs - startedAtMs;
	return !Number.isFinite(ms) || ms < 0 ? null : Math.floor(ms / 1000);
}

/** How a result was recorded. `host` is written server-side only. */
export type RaceFinishMethod = 'auto' | 'manual' | 'host';

export interface RaceOutcome {
	finisherStatus: 'finished' | 'dnf';
	/** Null for a DNF. */
	method: RaceFinishMethod | null;
	/** Device-clock instant the gun time is measured to; null for a DNF. */
	finishAtMs: number | null;
}

/**
 * An open in-zone approach is an automatic finish at its closest fix;
 * otherwise a runner who covered enough finishes manually at nowMs (the
 * instant they stopped), and one who did not is a DNF. lapsMet is the
 * detector's `lapsMet` at the stop: false (a lap course not run to its last
 * lap) is a DNF whatever the distance; null leaves the distance to decide.
 */
export function raceStopOutcome(
	candidate: RaceFinish | null,
	coveredM: number,
	courseDistanceM: number | null,
	nowMs: number,
	lapsMet: boolean | null = null,
): RaceOutcome {
	if (candidate !== null) return { finisherStatus: 'finished', method: 'auto', finishAtMs: candidate.atMs };
	if (raceCoverageMet(coveredM, courseDistanceM) && lapsMet !== false) {
		return { finisherStatus: 'finished', method: 'manual', finishAtMs: nowMs };
	}
	return { finisherStatus: 'dnf', method: null, finishAtMs: null };
}

export interface RaceResultTiming {
	durationS: number;
	gunTimeS: number | null;
	chipTimeS: number | null;
}

export interface RaceResultTimingInput {
	outcome: RaceOutcome;
	gunAtMs: number | null;
	clockOffsetMs?: number;
	recordingStartedAtMs: number | null;
	/** The committed start (line crossing, or GO when past the line), device clock. */
	startAtMs?: number | null;
	elapsedS: number;
}

/**
 * The timing columns of a result row. A finish carries the gun time (when the
 * race had a GO) and the chip time, from the committed start when there is
 * one and the Start press otherwise, capped at the gun time (decisions
 * § 1861); duration is gun ?? chip ?? elapsed. A DNF carries neither time
 * and its duration is the recording's elapsed seconds (§ 1855).
 */
export function raceResultTiming(i: RaceResultTimingInput): RaceResultTiming {
	const finishAt = i.outcome.finishAtMs;
	if (i.outcome.finisherStatus !== 'finished' || finishAt === null) {
		return { durationS: i.elapsedS, gunTimeS: null, chipTimeS: null };
	}
	const gun = i.gunAtMs === null ? null : raceGunTimeS(finishAt, i.gunAtMs, i.clockOffsetMs ?? 0);
	const began = i.startAtMs ?? i.recordingStartedAtMs;
	const fromStart = began === null ? null : raceChipTimeS(finishAt, began);
	const chip = gun !== null && fromStart !== null && fromStart > gun ? gun : fromStart;
	return { durationS: gun ?? chip ?? i.elapsedS, gunTimeS: gun, chipTimeS: chip };
}
