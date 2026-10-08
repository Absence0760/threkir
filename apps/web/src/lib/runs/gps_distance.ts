// GPS distance estimator, spec v1. docs/features/gps_distance.md is the spec
// and scripts/gps_distance/reference.py the reference; every port must
// reproduce fixtures/gps_distance_vectors.json to 1e-3 m, so keep the
// formulas in the reference's order. Parity pair with
// packages/run_recorder/lib/src/gps_distance_estimator.dart.

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

type MaybeNumber = number | null | undefined;

function valid(x: MaybeNumber): x is number {
	return x !== null && x !== undefined && Number.isFinite(x);
}

function rad(deg: number): number {
	return (deg * Math.PI) / 180;
}

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
}

export class GpsDistanceEstimator {
	readonly maxSpeedMps: number;
	gpsDistanceM = 0;
	stepDistanceM = 0;
	strideM: number | null = null;

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

	constructor(maxSpeedMps = 10.0) {
		this.maxSpeedMps = maxSpeedMps;
	}

	get distanceM(): number {
		return this.gpsDistanceM + this.stepDistanceM;
	}

	private project(lat: number, lng: number): [number, number] {
		const lat0 = this.lat0 as number;
		const lng0 = this.lng0 as number;
		const x = rad(lng - lng0) * EARTH_RADIUS_M * Math.cos(rad(lat0));
		const y = rad(lat - lat0) * EARTH_RADIUS_M;
		return [x, y];
	}

	/** `t`: seconds on a clock monotonic within the run. Returns metres credited. */
	addFix(
		t: MaybeNumber,
		lat: MaybeNumber,
		lng: MaybeNumber,
		accuracyM?: MaybeNumber,
		speedMps?: MaybeNumber,
		speedAccuracyMps?: MaybeNumber,
		bearingDeg?: MaybeNumber,
	): number {
		if (!(valid(t) && valid(lat) && valid(lng))) return 0;
		if (this.lat0 === null) {
			this.lat0 = lat;
			this.lng0 = lng;
		}
		const [zx, zy] = this.project(lat, lng);
		const sigma = valid(accuracyM) && accuracyM > 0 ? accuracyM : MIN_POS_SIGMA_M;
		const r = Math.max(sigma, MIN_POS_SIGMA_M) ** 2;
		if (this.t !== null && t <= this.t) return 0;
		if (this.t === null || t - this.t > GAP_S || this.x === null || this.y === null) {
			// (Re-)anchor. Steps buffered across a real gap are committed now.
			if (this.t !== null) this.stepDistanceM += this.pendingStepM;
			this.pendingStepM = 0;
			this.x = new Axis(zx, r);
			this.y = new Axis(zy, r);
			this.t = t;
			return 0;
		}
		// The gap closed inside GAP_S, so the filter integrates it: drop the buffer.
		this.pendingStepM = 0;
		const dt = t - this.t;
		this.t = t;
		this.x.predict(dt);
		this.y.predict(dt);
		this.x.updatePos(zx, r);
		this.y.updatePos(zy, r);

		let doppler: number | null = null;
		if (valid(speedMps) && speedMps >= 0 && speedMps <= this.maxSpeedMps) {
			const sa =
				valid(speedAccuracyMps) && speedAccuracyMps > 0 ? speedAccuracyMps : DEFAULT_SPEED_SIGMA_MPS;
			if (sa <= MAX_SPEED_SIGMA_MPS) {
				doppler = speedMps;
				if (valid(bearingDeg) && speedMps >= STATIONARY_SPEED_MPS) {
					const rv = Math.max(sa, MIN_SPEED_SIGMA_MPS) ** 2;
					const b = rad(bearingDeg);
					this.x.updateVel(speedMps * Math.sin(b), rv);
					this.y.updateVel(speedMps * Math.cos(b), rv);
				}
			}
		}

		let speed: number;
		let floor: number;
		if (doppler !== null) {
			speed = doppler;
			floor = STATIONARY_SPEED_MPS;
		} else {
			speed = Math.hypot(this.x.v, this.y.v);
			floor = POS_ONLY_STATIONARY_SPEED_MPS;
		}
		if (speed < floor) return 0;
		const inc = Math.min(speed, this.maxSpeedMps) * dt;
		this.gpsDistanceM += inc;
		this.winM += inc;
		return inc;
	}

	/**
	 * Cumulative pedometer count. Learns stride while GPS is good; buffers
	 * steps x stride while it is not (committed only if the gap exceeds GAP_S).
	 */
	addSteps(t: MaybeNumber, cumulativeSteps: MaybeNumber): void {
		if (!valid(t) || cumulativeSteps === null || cumulativeSteps === undefined) return;
		const prev = this.lastSteps;
		const prevT = this.lastStepT;
		this.lastSteps = cumulativeSteps;
		this.lastStepT = t;
		if (prev === null || cumulativeSteps < prev || prevT === null || t <= prevT) return;
		const d = cumulativeSteps - prev;
		if (this.t !== null && t - this.t <= FRESH_FIX_S) {
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

	/** End of run: commit buffered steps if the trailing gap exceeds GAP_S. */
	finish(t: MaybeNumber): void {
		if (this.t !== null && valid(t) && t - this.t > GAP_S) {
			this.stepDistanceM += this.pendingStepM;
		}
		this.pendingStepM = 0;
	}
}
