import { shortestTurn, type FlyoverPath } from '#lib/routes/flyover_path.ts';

/// The flight's ending (#1284): from the chase camera at the finish, ease out
/// to a north-up view of the whole course at a lower pitch, then turn slowly
/// round it by a bounded angle and stop. Time is the only input, so the
/// dialog (driven by its animation frames) and the video export (driven by
/// its frame index) draw the same camera at the same moment.
///
/// It starts on its own when the flight ends, so it settles inside five
/// seconds (conventions § Web motion, rule 4), and under reduced motion it is
/// a direct cut to the overview with no orbit.

export const OVERVIEW_PITCH = 30;
export const OVERVIEW_PADDING_PX = 64;
export const OVERVIEW_EASE_MS = 2000;
export const ORBIT_MS = 3000;
export const ORBIT_DEG = 30;

/// The course's south-west and north-east corners, the box the overview fits.
export function pathBounds(path: FlyoverPath): [[number, number], [number, number]] {
	let minLng = Infinity;
	let minLat = Infinity;
	let maxLng = -Infinity;
	let maxLat = -Infinity;
	for (const p of path.points) {
		if (p.lng < minLng) minLng = p.lng;
		if (p.lng > maxLng) maxLng = p.lng;
		if (p.lat < minLat) minLat = p.lat;
		if (p.lat > maxLat) maxLat = p.lat;
	}
	return [
		[minLng, minLat],
		[maxLng, maxLat],
	];
}

export interface CameraPose {
	center: [number, number];
	bearing: number;
	pitch: number;
	zoom: number;
}

export interface FinalePlan {
	easeMs: number;
	orbitMs: number;
	orbitDeg: number;
}

export function finalePlan(reducedMotion: boolean): FinalePlan {
	return reducedMotion
		? { easeMs: 0, orbitMs: 0, orbitDeg: 0 }
		: { easeMs: OVERVIEW_EASE_MS, orbitMs: ORBIT_MS, orbitDeg: ORBIT_DEG };
}

export function finaleDurationMs(plan: FinalePlan): number {
	return plan.easeMs + plan.orbitMs;
}

/// The overview camera from a bounds fit (MapLibre's `cameraForBounds` at
/// bearing 0): north up, at the overview pitch.
export function overviewPose(fit: { center: [number, number]; zoom: number }): CameraPose {
	return { center: fit.center, zoom: fit.zoom, bearing: 0, pitch: OVERVIEW_PITCH };
}

function easeInOut(t: number): number {
	return t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2;
}

function clamp01(t: number): number {
	return Number.isFinite(t) ? Math.min(1, Math.max(0, t)) : 1;
}

/// The camera `tMs` after the flight ended. Before 0 it is the finish pose;
/// from the end of the plan on it holds the last orbit pose.
export function finaleCamera(from: CameraPose, to: CameraPose, tMs: number, plan: FinalePlan): CameraPose {
	const t = Number.isFinite(tMs) ? Math.max(0, tMs) : finaleDurationMs(plan);
	if (t < plan.easeMs) {
		const k = easeInOut(t / plan.easeMs);
		return {
			center: [
				from.center[0] + (to.center[0] - from.center[0]) * k,
				from.center[1] + (to.center[1] - from.center[1]) * k,
			],
			zoom: from.zoom + (to.zoom - from.zoom) * k,
			pitch: from.pitch + (to.pitch - from.pitch) * k,
			bearing: from.bearing + shortestTurn(from.bearing, to.bearing) * k,
		};
	}
	const p = plan.orbitMs > 0 ? clamp01((t - plan.easeMs) / plan.orbitMs) : 1;
	return { ...to, bearing: to.bearing + plan.orbitDeg * easeInOut(p) };
}
