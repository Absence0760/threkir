// GPS distance estimator, spec v1.2. docs/features/gps_distance.md is the spec
// and scripts/gps_distance/reference.py the reference; every port must
// reproduce fixtures/gps_distance_vectors.json to 1e-3 m, so keep the
// formulas in the reference's order. A copy of apps/web/src/lib/runs/gps_distance.ts
// because an Edge Function cannot import from apps/web; the shared vectors,
// not this comment, are what hold the two together.
//
// Two entry points: GpsDistanceEstimator is the forward (causal) filter a live
// screen runs; smoothDistance is the saved / recomputed figure, a forward pass
// plus a Rauch-Tung-Striebel backward pass over the whole run.

export const SPEC_VERSION = '1.2';

export const EARTH_RADIUS_M = 6371008.8;
export const Q_ACCEL = 0.6;
export const MIN_POS_SIGMA_M = 3.0;
export const INIT_VEL_VAR = 25.0;
export const MIN_SPEED_SIGMA_MPS = 0.3;
export const DEFAULT_SPEED_SIGMA_MPS = 0.5;
export const MAX_SPEED_SIGMA_MPS = 1.5;
export const STATIONARY_SPEED_MPS = 0.4;
export const POS_ONLY_STATIONARY_SPEED_MPS = 0.8;
export const GAP_S = 10.0;
export const FRESH_FIX_S = 2.0;
export const STRIDE_WINDOW_STEPS = 50;
export const MIN_STRIDE_M = 0.4;
export const MAX_STRIDE_M = 2.5;
export const STRIDE_EMA_ALPHA = 0.2;

export const GATE_CHI2 = 13.8155;
export const GATE_MAX_REJECTS = 5;
export const R_SCALE_ALPHA = 0.05;
export const R_SCALE_MIN = 1.0;
export const R_SCALE_MAX = 9.0;
export const XCHECK_TAU_S = 60.0;
export const XCHECK_MIN_S = 120.0;
export const XCHECK_ENTER_ABS_MPS = 0.4;
export const XCHECK_ENTER_REL = 0.15;
export const XCHECK_EXIT_ABS_MPS = 0.2;
export const XCHECK_EXIT_REL = 0.08;
export const XCHECK_PERSIST_S = 60.0;
export const XCHECK_MAX_SPAN_S = 5.0;
export const DEBIAS_FULL_MPS = 0.5;
export const DEBIAS_ZERO_MPS = 1.0;
export const ZUPT_NO_STEP_S = 6.0;
export const ZUPT_VEL_SIGMA_MPS = 0.1;
export const ZUPT_DOPPLER_OVERRIDE_MPS = 1.0;
export const ZUPT_RELEASE_M = 40.0;
export const STOP_HALF_WINDOW_S = 20.0;
export const STOP_MIN_HALF_FIXES = 3;
export const STOP_SPEED_MPS = 0.5;
export const STOP_RADIUS_M = 10.0;

type MaybeNumber = number | null | undefined;

function valid(x: MaybeNumber): x is number {
	return x !== null && x !== undefined && Number.isFinite(x);
}

function rad(deg: number): number {
	return (deg * Math.PI) / 180;
}

function deg(r: number): number {
	return (r * 180) / Math.PI;
}

function wrapLng(d: number): number {
	if (d >= 180.0) return d - 360.0;
	if (d < -180.0) return d + 360.0;
	return d;
}

function intervalScale(expectedIntervalS: MaybeNumber): number {
	return valid(expectedIntervalS) && expectedIntervalS > 1.0 ? expectedIntervalS : 1.0;
}

/** Usable, debiased Doppler speed and its sigma, or null. */
function dopplerSpeed(
	speedMps: MaybeNumber,
	speedAccuracyMps: MaybeNumber,
	maxSpeedMps: number,
): { s: number; sa: number } | null {
	if (!(valid(speedMps) && speedMps >= 0 && speedMps <= maxSpeedMps)) return null;
	const reported = valid(speedAccuracyMps) && speedAccuracyMps > 0;
	const sa = reported ? (speedAccuracyMps as number) : DEFAULT_SPEED_SIGMA_MPS;
	if (sa > MAX_SPEED_SIGMA_MPS) return null;
	let s = speedMps;
	if (reported && s < DEBIAS_ZERO_MPS) {
		const w = s <= DEBIAS_FULL_MPS ? 1.0 : (DEBIAS_ZERO_MPS - s) / (DEBIAS_ZERO_MPS - DEBIAS_FULL_MPS);
		s = Math.sqrt(Math.max(0.0, s * s - w * sa * sa));
	}
	return { s, sa };
}

/** Per-axis filter state: [p, v, a, b, c]. */
type AxisState = [number, number, number, number, number];

class Axis {
	p: number;
	v = 0;
	a: number;
	b = 0;
	c = INIT_VEL_VAR;

	constructor(p: number, posVar: number) {
		this.p = p;
		this.a = posVar;
	}

	predict(dt: number): void {
		this.p += this.v * dt;
		const a = this.a + 2.0 * dt * this.b + dt * dt * this.c + (Q_ACCEL * dt ** 3) / 3.0;
		const b = this.b + dt * this.c + (Q_ACCEL * dt * dt) / 2.0;
		const c = this.c + Q_ACCEL * dt;
		this.a = a;
		this.b = b;
		this.c = c;
	}

	updatePos(z: number, r: number): void {
		const s = this.a + r;
		const k0 = this.a / s;
		const k1 = this.b / s;
		const y = z - this.p;
		this.p += k0 * y;
		this.v += k1 * y;
		const { a, b, c } = this;
		this.a = (1 - k0) * a;
		this.b = (1 - k0) * b;
		this.c = c - k1 * b;
	}

	updateVel(z: number, r: number): void {
		const s = this.c + r;
		const k0 = this.b / s;
		const k1 = this.c / s;
		const y = z - this.v;
		this.p += k0 * y;
		this.v += k1 * y;
		const { a, b, c } = this;
		this.a = a - k0 * b;
		this.b = (1 - k1) * b;
		this.c = (1 - k1) * c;
	}

	/** Lock-out re-anchor: position jumps to z, velocity is kept. */
	resetPos(z: number, r: number): void {
		this.p = z;
		this.a = r;
		this.b = 0;
	}

	state(): AxisState {
		return [this.p, this.v, this.a, this.b, this.c];
	}
}

/** What smoothDistance's backward pass needs from each fix the filter took. */
type FixRecord = {
	anchor: boolean;
	chainBreak: boolean;
	dt: number;
	pred: [AxisState, AxisState] | null;
	x: AxisState;
	y: AxisState;
	zupt: boolean;
	dop: number | null;
	chord: number | null;
	stepDistanceM: number;
};

export class GpsDistanceEstimator {
	readonly maxSpeedMps: number;
	private readonly gapS: number;
	private readonly freshFixS: number;
	gpsDistanceM = 0;
	stepDistanceM = 0;
	strideM: number | null = null;
	rScale = 1.0;
	rejectedFixes = 0;
	zuptFixes = 0;
	dopplerTrusted = true;

	private lat0: number | null = null;
	private lng0: number | null = null;
	private x: Axis | null = null;
	private y: Axis | null = null;
	private t: number | null = null;
	private winSteps = 0;
	private winM = 0;
	private lastSteps: number | null = null;
	private lastStepT: number | null = null;
	private pendingStepM = 0;
	private rejectStreak = 0;
	private xcDoppler = 0;
	private xcPos = 0;
	private xcTime = 0;
	private xcPersistS = 0;
	private xcLast: [number, number, number] | null = null;
	private stepsSeen = false;
	private lastStepIncT: number | null = null;
	private zuptReleased = false;
	private zuptAnchor: [number, number] | null = null;
	/** @internal Filled only for smoothDistance. */
	readonly records: FixRecord[] | null;

	constructor(
		maxSpeedMps = 10.0,
		expectedIntervalS: MaybeNumber = 1.0,
		initialStrideM: number | null = null,
		record = false,
	) {
		this.maxSpeedMps = maxSpeedMps;
		const scale = intervalScale(expectedIntervalS);
		this.gapS = GAP_S * scale;
		this.freshFixS = FRESH_FIX_S * scale;
		this.strideM =
			valid(initialStrideM) && MIN_STRIDE_M <= initialStrideM && initialStrideM <= MAX_STRIDE_M
				? initialStrideM
				: null;
		this.records = record ? [] : null;
	}

	get distanceM(): number {
		return this.gpsDistanceM + this.stepDistanceM;
	}

	private project(lat: number, lng: number): [number, number] {
		const lat0 = this.lat0 as number;
		const lng0 = this.lng0 as number;
		const x = rad(wrapLng(lng - lng0)) * EARTH_RADIUS_M * Math.cos(rad(lat0));
		const y = rad(lat - lat0) * EARTH_RADIUS_M;
		return [x, y];
	}

	/** Inverse of the tangent-plane projection the first fix fixed. */
	unproject(x: number, y: number): [number, number] {
		const lat0 = this.lat0 as number;
		const lng0 = this.lng0 as number;
		const lat = lat0 + deg(y / EARTH_RADIUS_M);
		const lng = lng0 + deg(x / (EARTH_RADIUS_M * Math.cos(rad(lat0))));
		return [lat, wrapLng(lng)];
	}

	/** Pedometer says stationary: steps seen this run, none for ZUPT_NO_STEP_S, Doppler not contradicting. */
	private zuptDue(t: number, dop: number | null): boolean {
		if (
			!this.stepsSeen ||
			this.zuptReleased ||
			t - (this.lastStepIncT as number) <= ZUPT_NO_STEP_S
		) {
			return false;
		}
		return !(dop !== null && this.dopplerTrusted && dop >= ZUPT_DOPPLER_OVERRIDE_MPS);
	}

	private record(
		r: Omit<FixRecord, 'x' | 'y' | 'stepDistanceM'>,
		x: Axis,
		y: Axis,
	): void {
		if (this.records === null) return;
		this.records.push({ ...r, x: x.state(), y: y.state(), stepDistanceM: this.stepDistanceM });
	}

	/**
	 * `t`: seconds on a clock monotonic within the run. Returns metres credited.
	 * `stoppedHint`: the caller knows the runner is stationary (post-hoc stop
	 * detection); live recorders always pass false.
	 */
	addFix(
		t: MaybeNumber,
		lat: MaybeNumber,
		lng: MaybeNumber,
		accuracyM?: MaybeNumber,
		speedMps?: MaybeNumber,
		speedAccuracyMps?: MaybeNumber,
		bearingDeg?: MaybeNumber,
		stoppedHint = false,
	): number {
		if (!(valid(t) && valid(lat) && valid(lng))) return 0;
		if (this.lat0 === null) {
			this.lat0 = lat;
			this.lng0 = lng;
		}
		const [zx, zy] = this.project(lat, lng);
		const sigma = valid(accuracyM) && accuracyM > 0 ? accuracyM : MIN_POS_SIGMA_M;
		const rStated = Math.max(sigma, MIN_POS_SIGMA_M) ** 2;
		const r = Math.max(rStated * this.rScale, MIN_POS_SIGMA_M ** 2);
		if (this.t !== null && t <= this.t) return 0;
		const doppler = dopplerSpeed(speedMps, speedAccuracyMps, this.maxSpeedMps);
		const dop = doppler === null ? null : doppler.s;
		if (this.t === null || t - this.t > this.gapS || this.x === null || this.y === null) {
			// (Re-)anchor. Steps buffered across a real gap are committed now.
			if (this.t !== null) this.stepDistanceM += this.pendingStepM;
			this.pendingStepM = 0;
			this.x = new Axis(zx, r);
			this.y = new Axis(zy, r);
			this.t = t;
			this.xcLast = [zx, zy, t];
			this.rejectStreak = 0;
			this.zuptAnchor = null;
			const zupt = stoppedHint || this.zuptDue(t, dop);
			this.record(
				{
					anchor: true,
					chainBreak: true,
					dt: 0,
					pred: null,
					zupt,
					dop: dop !== null && this.dopplerTrusted ? dop : null,
					chord: null,
				},
				this.x,
				this.y,
			);
			return 0;
		}
		// The gap closed inside the gap window, so the filter integrates it: drop the buffer.
		this.pendingStepM = 0;
		const dt = t - this.t;
		this.t = t;
		const x = this.x;
		const y = this.y;
		x.predict(dt);
		y.predict(dt);
		const pred: [AxisState, AxisState] = [x.state(), y.state()];

		// 1. Innovation gate on the predicted position.
		const yx = zx - x.p;
		const yy = zy - y.p;
		const ax = x.a;
		const ay = y.a;
		const nis = (yx * yx) / (ax + r) + (yy * yy) / (ay + r);
		let chainBreak = false;
		const accepted = nis <= GATE_CHI2;
		if (accepted) {
			this.rejectStreak = 0;
			x.updatePos(zx, r);
			y.updatePos(zy, r);
			// 2. Adaptive R: covariance matching, sample clamped, EMA, bounded.
			let sample = (yx * yx - ax + (yy * yy - ay)) / (2.0 * rStated);
			sample = Math.min(Math.max(sample, 0.0), R_SCALE_MAX);
			const ema = (1.0 - R_SCALE_ALPHA) * this.rScale + R_SCALE_ALPHA * sample;
			this.rScale = Math.min(Math.max(ema, R_SCALE_MIN), R_SCALE_MAX);
		} else {
			this.rejectedFixes += 1;
			this.rejectStreak += 1;
			if (this.rejectStreak > GATE_MAX_REJECTS) {
				x.resetPos(zx, r);
				y.resetPos(zy, r);
				this.rejectStreak = 0;
				this.xcLast = [zx, zy, t];
				chainBreak = true;
			}
		}

		// 3. Zero-velocity update (pedometer, or the caller's stop hint).
		let pedZupt = this.zuptDue(t, dop);
		let chord: number | null = null;
		if (pedZupt) {
			if (this.zuptAnchor === null) {
				this.zuptAnchor = [x.p, y.p];
			} else {
				const moved = Math.hypot(x.p - this.zuptAnchor[0], y.p - this.zuptAnchor[1]);
				if (moved > ZUPT_RELEASE_M) {
					// The pedometer stalled while the runner moved: stop trusting it until it counts again.
					this.zuptReleased = true;
					this.zuptAnchor = null;
					pedZupt = false;
					chord = moved;
				}
			}
		} else {
			this.zuptAnchor = null;
		}
		const zupt = stoppedHint || pedZupt;
		if (zupt) {
			chord = null;
			this.zuptFixes += 1;
			const rz = ZUPT_VEL_SIGMA_MPS ** 2;
			x.updateVel(0.0, rz);
			y.updateVel(0.0, rz);
		}

		// 4. Doppler-vs-position cross-check, on the raw fixes' displacement
		//    projected on the Doppler bearing.
		if (accepted) {
			const [lx, ly, lt] = this.xcLast as [number, number, number];
			const span = t - lt;
			if (
				dop !== null &&
				!zupt &&
				valid(bearingDeg) &&
				dop >= POS_ONLY_STATIONARY_SPEED_MPS &&
				span <= XCHECK_MAX_SPAN_S
			) {
				const b = rad(bearingDeg);
				const u = ((zx - lx) * Math.sin(b) + (zy - ly) * Math.cos(b)) / span;
				if (this.xcTime === 0.0) {
					this.xcDoppler = dop;
					this.xcPos = dop;
				} else {
					const alpha = Math.min(1.0, span / XCHECK_TAU_S);
					this.xcDoppler += alpha * (dop - this.xcDoppler);
					this.xcPos += alpha * (u - this.xcPos);
				}
				this.xcTime += span;
				if (this.xcTime >= XCHECK_MIN_S) {
					const diff = Math.abs(this.xcDoppler - this.xcPos);
					const refSpeed = Math.abs(this.xcPos);
					const flip = this.dopplerTrusted
						? diff > Math.max(XCHECK_ENTER_ABS_MPS, XCHECK_ENTER_REL * refSpeed)
						: diff < Math.max(XCHECK_EXIT_ABS_MPS, XCHECK_EXIT_REL * refSpeed);
					this.xcPersistS = flip ? this.xcPersistS + span : 0.0;
					if (this.xcPersistS >= XCHECK_PERSIST_S) {
						this.dopplerTrusted = !this.dopplerTrusted;
						this.xcPersistS = 0.0;
					}
				}
			}
			this.xcLast = [zx, zy, t];
		}

		// 5. Doppler velocity update.
		const useDop = doppler !== null && this.dopplerTrusted ? doppler.s : null;
		if (useDop !== null && !zupt && valid(bearingDeg) && useDop >= STATIONARY_SPEED_MPS) {
			const rv = Math.max((doppler as { sa: number }).sa, MIN_SPEED_SIGMA_MPS) ** 2;
			const b = rad(bearingDeg);
			x.updateVel(useDop * Math.sin(b), rv);
			y.updateVel(useDop * Math.cos(b), rv);
		}

		// 6. Credit.
		let inc: number;
		if (chord !== null) {
			inc = chord;
		} else if (zupt) {
			inc = 0;
		} else {
			let speed: number;
			let floor: number;
			if (useDop !== null) {
				speed = useDop;
				floor = STATIONARY_SPEED_MPS;
			} else {
				speed = Math.hypot(x.v, y.v);
				floor = POS_ONLY_STATIONARY_SPEED_MPS;
			}
			inc = speed < floor ? 0 : Math.min(speed, this.maxSpeedMps) * dt;
		}
		this.gpsDistanceM += inc;
		this.winM += inc;
		this.record({ anchor: false, chainBreak, dt, pred, zupt, dop: useDop, chord }, x, y);
		return inc;
	}

	/**
	 * Cumulative pedometer count. Learns stride while GPS is good; buffers
	 * steps x stride while it is not (committed only if the gap exceeds the gap window).
	 */
	addSteps(t: MaybeNumber, cumulativeSteps: MaybeNumber): void {
		if (!valid(t) || cumulativeSteps === null || cumulativeSteps === undefined) return;
		const prev = this.lastSteps;
		const prevT = this.lastStepT;
		this.lastSteps = cumulativeSteps;
		this.lastStepT = t;
		if (prev === null || cumulativeSteps < prev || prevT === null || t <= prevT) return;
		const d = cumulativeSteps - prev;
		if (d > 0) {
			this.stepsSeen = true;
			this.lastStepIncT = t;
			this.zuptReleased = false;
		}
		if (this.t !== null && t - this.t <= this.freshFixS) {
			this.winSteps += d;
			if (this.winSteps >= STRIDE_WINDOW_STEPS) {
				const stride = this.winM / this.winSteps;
				if (stride >= MIN_STRIDE_M && stride <= MAX_STRIDE_M) {
					this.strideM =
						this.strideM === null
							? stride
							: (1 - STRIDE_EMA_ALPHA) * this.strideM + STRIDE_EMA_ALPHA * stride;
				}
				this.winSteps = 0;
				this.winM = 0;
			}
			return;
		}
		this.winSteps = 0;
		this.winM = 0;
		if (this.strideM === null) return;
		this.pendingStepM += Math.min(d * this.strideM, this.maxSpeedMps * (t - prevT));
	}

	/** End of run: commit buffered steps if the trailing gap exceeds the gap window. */
	finish(t: MaybeNumber): void {
		if (this.t !== null && valid(t) && t - this.t > this.gapS) {
			this.stepDistanceM += this.pendingStepM;
		}
		this.pendingStepM = 0;
	}
}

/** One input to smoothDistance, in arrival order. */
export type GpsEvent =
	| {
			type: 'fix';
			t: MaybeNumber;
			lat: MaybeNumber;
			lng: MaybeNumber;
			acc?: MaybeNumber;
			speed?: MaybeNumber;
			speedAcc?: MaybeNumber;
			bearing?: MaybeNumber;
	  }
	| { type: 'steps'; t: MaybeNumber; count: MaybeNumber }
	| { type: 'finish'; t: MaybeNumber };

export type SmoothedDistance = {
	distanceM: number;
	gpsDistanceM: number;
	stepDistanceM: number;
	/** Per event: smoothed GPS credit through it plus the step distance committed by then. */
	cumulativeM: number[];
	/** Per event: the smoothed [lat, lng] of a fix the filter took, else null. */
	positions: Array<[number, number] | null>;
	stoppedFixes: number;
};

/**
 * Post-hoc stop flags for a track with no Doppler. `fixes`: [t, x, y] in
 * strictly increasing t. Fix j is stopped when both half-windows around it
 * hold >= STOP_MIN_HALF_FIXES fixes, the net speed between the halves' mean
 * positions is < STOP_SPEED_MPS, and the RMS distance of the whole window
 * from its mean is < STOP_RADIUS_M.
 */
export function detectStops(
	fixes: ReadonlyArray<readonly [number, number, number]>,
	expectedIntervalS: MaybeNumber = 1.0,
): boolean[] {
	const half = STOP_HALF_WINDOW_S * intervalScale(expectedIntervalS);
	const n = fixes.length;
	const out = new Array<boolean>(n).fill(false);
	let lo = 0;
	let hi = 0;
	for (let j = 0; j < n; j++) {
		const tj = fixes[j][0];
		while (fixes[lo][0] < tj - half) lo += 1;
		while (hi + 1 < n && fixes[hi + 1][0] <= tj + half) hi += 1;
		const na = j - lo;
		const nb = hi - j + 1;
		if (na < STOP_MIN_HALF_FIXES || nb < STOP_MIN_HALF_FIXES) continue;
		let ta = 0;
		let xa = 0;
		let ya = 0;
		for (let k = lo; k < j; k++) {
			ta += fixes[k][0];
			xa += fixes[k][1];
			ya += fixes[k][2];
		}
		let tb = 0;
		let xb = 0;
		let yb = 0;
		for (let k = j; k <= hi; k++) {
			tb += fixes[k][0];
			xb += fixes[k][1];
			yb += fixes[k][2];
		}
		const net = Math.hypot(xb / nb - xa / na, yb / nb - ya / na) / (tb / nb - ta / na);
		if (net >= STOP_SPEED_MPS) continue;
		const mx = (xa + xb) / (na + nb);
		const my = (ya + yb) / (na + nb);
		let ss = 0;
		for (let k = lo; k <= hi; k++) {
			const dx = fixes[k][1] - mx;
			const dy = fixes[k][2] - my;
			ss += dx * dx + dy * dy;
		}
		out[j] = Math.sqrt(ss / (na + nb)) < STOP_RADIUS_M;
	}
	return out;
}

/** RTS backward pass over one unbroken chain records[s..e] for one axis: smoothed [p, v] per record. */
function rts(records: FixRecord[], s: number, e: number, axis: 0 | 1): Array<[number, number]> {
	const out = new Array<[number, number]>(e - s + 1);
	const last = axis === 0 ? records[e].x : records[e].y;
	out[e - s] = [last[0], last[1]];
	for (let k = e - s - 1; k >= 0; k--) {
		const [p, v, a, b, c] = axis === 0 ? records[s + k].x : records[s + k].y;
		const nxt = records[s + k + 1];
		const dt = nxt.dt;
		const [pp, pv, A, B, C] = (nxt.pred as [AxisState, AxisState])[axis];
		const det = A * C - B * B;
		const g00 = ((a + dt * b) * C - b * B) / det;
		const g01 = (b * A - (a + dt * b) * B) / det;
		const g10 = ((b + dt * c) * C - c * B) / det;
		const g11 = (c * A - (b + dt * c) * B) / det;
		const dp = out[k + 1][0] - pp;
		const dv = out[k + 1][1] - pv;
		out[k] = [p + g00 * dp + g01 * dv, v + g10 * dp + g11 * dv];
	}
	return out;
}

/**
 * The saved / recomputed distance: the forward filter over every event, then
 * a backward (RTS) pass per unbroken chain, credited along the smoothed
 * velocities. A track with no Doppler at all first runs post-hoc stop
 * detection, whose verdicts reach the filter as `stoppedHint`.
 */
export function smoothDistance(
	events: readonly GpsEvent[],
	maxSpeedMps = 10.0,
	expectedIntervalS: MaybeNumber = 1.0,
	initialStrideM: number | null = null,
): SmoothedDistance {
	// Fixes exactly as the estimator would take them.
	const kept: Array<[number, number, number, number]> = [];
	let lat0: number | null = null;
	let lng0: number | null = null;
	let lastT: number | null = null;
	let hasDoppler = false;
	events.forEach((ev, i) => {
		if (ev.type !== 'fix') return;
		const { t, lat, lng } = ev;
		if (!(valid(t) && valid(lat) && valid(lng))) return;
		if (lat0 === null || lng0 === null) {
			lat0 = lat;
			lng0 = lng;
		}
		if (lastT !== null && t <= lastT) return;
		lastT = t;
		if (valid(ev.speed)) hasDoppler = true;
		const x = rad(wrapLng(lng - lng0)) * EARTH_RADIUS_M * Math.cos(rad(lat0));
		const y = rad(lat - lat0) * EARTH_RADIUS_M;
		kept.push([i, t, x, y]);
	});
	const hints = new Set<number>();
	if (!hasDoppler) {
		const flags = detectStops(
			kept.map(([, t, x, y]) => [t, x, y] as const),
			expectedIntervalS,
		);
		flags.forEach((f, j) => {
			if (f) hints.add(kept[j][0]);
		});
	}

	const est = new GpsDistanceEstimator(maxSpeedMps, expectedIntervalS, initialStrideM, true);
	const recs = est.records as FixRecord[];
	const recEvent: number[] = [];
	events.forEach((ev, i) => {
		if (ev.type === 'fix') {
			const n = recs.length;
			est.addFix(ev.t, ev.lat, ev.lng, ev.acc, ev.speed, ev.speedAcc, ev.bearing, hints.has(i));
			if (recs.length > n) recEvent.push(i);
		} else if (ev.type === 'steps') {
			est.addSteps(ev.t, ev.count);
		} else {
			est.finish(ev.t);
		}
	});

	// Backward pass per unbroken chain (a gap re-anchor or a gate lock-out starts a new one).
	const sm = new Array<[number, number, number, number]>(recs.length);
	let s = 0;
	for (let k = 1; k <= recs.length; k++) {
		if (k === recs.length || recs[k].chainBreak) {
			const xs = rts(recs, s, k - 1, 0);
			const ys = rts(recs, s, k - 1, 1);
			for (let j = s; j < k; j++) {
				sm[j] = [xs[j - s][0], ys[j - s][0], xs[j - s][1], ys[j - s][1]];
			}
			s = k;
		}
	}

	// Credit along the smoothed velocities: trapezoid per interval, gap re-anchors not credited.
	const effs = recs.map((r, k) => {
		if (r.zupt) return 0;
		let speed: number;
		let floor: number;
		if (r.dop !== null) {
			speed = r.dop;
			floor = STATIONARY_SPEED_MPS;
		} else {
			speed = Math.hypot(sm[k][2], sm[k][3]);
			floor = POS_ONLY_STATIONARY_SPEED_MPS;
		}
		return speed < floor ? 0 : Math.min(speed, maxSpeedMps);
	});
	const credit = recs.map((r, k) => {
		if (r.anchor) return 0;
		return r.chord !== null ? r.chord : 0.5 * (effs[k - 1] + effs[k]) * r.dt;
	});

	const byEvent = new Map<number, number>();
	recEvent.forEach((e, k) => byEvent.set(e, k));
	const cumulativeM: number[] = [];
	const positions: Array<[number, number] | null> = [];
	let gps = 0;
	let stepM = 0;
	events.forEach((ev, i) => {
		const k = byEvent.get(i);
		let pos: [number, number] | null = null;
		if (k !== undefined) {
			gps += credit[k];
			stepM = recs[k].stepDistanceM;
			pos = est.unproject(sm[k][0], sm[k][1]);
		} else if (ev.type === 'finish') {
			stepM = est.stepDistanceM;
		}
		cumulativeM.push(gps + stepM);
		positions.push(pos);
	});
	return {
		distanceM: gps + est.stepDistanceM,
		gpsDistanceM: gps,
		stepDistanceM: est.stepDistanceM,
		cumulativeM,
		positions,
		stoppedFixes: hints.size,
	};
}
