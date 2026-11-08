// Timing-line ("gate") crossing detection, spec `gate_crossing v1` (issue
// #1304, decisions § 2377). Pure: every instant is handed in.
//
// Parity pair with apps/mobile_android/lib/gate_crossing.dart, which is itself
// paired with Wear OS's GateCrossing.kt. All three read
// fixtures/gate_crossing_cases.json, so a rule changes there or nowhere.

export const GATE_EARTH_RADIUS_M = 6371008.8;

// Provisional until the #1304 calibration session measures them.
export const GATE_MAX_GAP_S = 10;
export const GATE_MAX_HOP_M = 50;
export const GATE_REJECT_GAP_S = 60;
export const GATE_HALF_WIDTH_RACE_M = 15;
export const GATE_HALF_WIDTH_SEGMENT_M = 15;

/** A line through (lat, lng), perpendicular to the direction of travel. */
export interface Gate {
	lat: number;
	lng: number;
	/** Direction of travel, degrees clockwise from north. */
	bearingDeg: number;
	/** How far the line reaches either side of the centre. */
	halfWidthM: number;
}

/**
 * One distinct, trusted fix, timed at its own fix instant (epoch ms), with
 * the distance the recording had covered at that instant.
 */
export interface GateFix {
	lat: number;
	lng: number;
	tMs: number;
	coveredM: number;
}

export type GateDirection = 'forward' | 'backward';

export interface GateCrossing {
	direction: GateDirection;
	/** Where between the two fixes the line was crossed, 0..1. */
	fraction: number;
	tMs: number;
	coveredM: number;
	/** Lateral offset from the centre, positive to the right of travel. */
	offsetM: number;
	/** The pair was more than maxGapS apart or hopped more than maxHopM. */
	gapped: boolean;
}

export interface GateCrossingOptions {
	maxGapS: number;
	maxHopM: number;
	rejectGapS: number;
}

export const GATE_DEFAULT_OPTIONS: GateCrossingOptions = {
	maxGapS: GATE_MAX_GAP_S,
	maxHopM: GATE_MAX_HOP_M,
	rejectGapS: GATE_REJECT_GAP_S,
};

/** s: signed distance past the line along travel. u: lateral offset. */
export interface GateProjection {
	s: number;
	u: number;
}

function rad(deg: number): number {
	return (deg * Math.PI) / 180;
}

function wrapLng(d: number): number {
	if (d >= 180) return d - 360;
	if (d < -180) return d + 360;
	return d;
}

/** Whether the gate can report crossings at all; an unusable gate reports none. */
export function gateUsable(gate: Gate): boolean {
	return (
		Number.isFinite(gate.lat) &&
		Number.isFinite(gate.lng) &&
		Number.isFinite(gate.bearingDeg) &&
		Number.isFinite(gate.halfWidthM) &&
		gate.halfWidthM >= 0 &&
		Math.abs(gate.lat) < 90 &&
		Math.abs(gate.lng) <= 180
	);
}

/** (lat, lng) on the tangent plane at the gate centre, on the gate's axes. */
export function gateProjection(gate: Gate, lat: number, lng: number): GateProjection {
	const x = rad(wrapLng(lng - gate.lng)) * GATE_EARTH_RADIUS_M * Math.cos(rad(gate.lat));
	const y = rad(lat - gate.lat) * GATE_EARTH_RADIUS_M;
	const sinB = Math.sin(rad(gate.bearingDeg));
	const cosB = Math.cos(rad(gate.bearingDeg));
	return { s: x * sinB + y * cosB, u: x * cosB - y * sinB };
}

interface Projected {
	fix: GateFix;
	s: number;
	u: number;
}

/**
 * Streaming form: offer each fix as it arrives; the call that completes a
 * crossing returns it. settle() ends the stream and returns every crossing.
 */
export class GateCrossingDetector {
	readonly gate: Gate;
	readonly options: GateCrossingOptions;
	private readonly usable: boolean;
	private prev: Projected | null = null;
	private readonly found: GateCrossing[] = [];
	private settled = false;

	constructor(gate: Gate, options: GateCrossingOptions = GATE_DEFAULT_OPTIONS) {
		this.gate = gate;
		this.options = options;
		this.usable = gateUsable(gate);
	}

	get crossings(): GateCrossing[] {
		return [...this.found];
	}

	offer(fix: GateFix): GateCrossing | null {
		if (this.settled || !this.usable) return null;
		if (
			!Number.isFinite(fix.lat) ||
			!Number.isFinite(fix.lng) ||
			!Number.isFinite(fix.tMs) ||
			!Number.isFinite(fix.coveredM)
		) {
			return null;
		}
		const prev = this.prev;
		if (prev !== null && fix.tMs <= prev.fix.tMs) return null;

		const p = gateProjection(this.gate, fix.lat, fix.lng);
		const cur: Projected = { fix, s: p.s, u: p.u };
		this.prev = cur;
		if (prev === null) return null;

		const crossing = this.cross(prev, cur);
		if (crossing !== null) this.found.push(crossing);
		return crossing;
	}

	settle(): GateCrossing[] {
		this.settled = true;
		return [...this.found];
	}

	private cross(a: Projected, b: Projected): GateCrossing | null {
		let direction: GateDirection;
		if (a.s < 0 && b.s >= 0) direction = 'forward';
		else if (a.s >= 0 && b.s < 0) direction = 'backward';
		else return null;

		const dtS = (b.fix.tMs - a.fix.tMs) / 1000;
		if (dtS > this.options.rejectGapS) return null;

		const f = -a.s / (b.s - a.s);
		const offsetM = a.u + f * (b.u - a.u);
		if (Math.abs(offsetM) > this.gate.halfWidthM) return null;

		const ds = b.s - a.s;
		const du = b.u - a.u;
		const hopM = Math.sqrt(ds * ds + du * du);
		return {
			direction,
			fraction: f,
			tMs: a.fix.tMs + f * (b.fix.tMs - a.fix.tMs),
			coveredM: a.fix.coveredM + f * (b.fix.coveredM - a.fix.coveredM),
			offsetM,
			gapped: dtS > this.options.maxGapS || hopM > this.options.maxHopM,
		};
	}
}

/** Batch form: every crossing of [track] through [gate], in order. */
export function crossingsOf(
	track: readonly GateFix[],
	gate: Gate,
	options: GateCrossingOptions = GATE_DEFAULT_OPTIONS,
): GateCrossing[] {
	const detector = new GateCrossingDetector(gate, options);
	for (const fix of track) detector.offer(fix);
	return detector.settle();
}
