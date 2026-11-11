import { cameraAt, DEFAULT_FLYOVER_SPEED_MPS, pointAtDistance, type FlyoverPath } from '#lib/routes/flyover_path.ts';
import type { FlyoverMode } from '#lib/routes/flyover_capability.ts';

/// How Grisnir moves on the course preview (decisions § 2455): which way he
/// faces, how fast he trots, and whether he is drawn at all. Pure, so the
/// dialog and the video export cannot disagree.

/// The model's trot: 15 frames at 30 fps, two cycles a second, at the
/// dialog's default speed.
export const TROT_CYCLES_PER_S = 2;
/// The flight covers hundreds of metres a second, so his hooves cannot keep
/// pace with the ground (a 0.62 m stride would be 400 cycles a second). The
/// trot speeds up with the playback instead, as the square root of the speed
/// factor, and stays inside a range a trot still reads as one.
export const MIN_TROT_CYCLES_PER_S = 1.25;
export const MAX_TROT_CYCLES_PER_S = 3.5;

/// His heading is the course's direction over a short chord centred on him:
/// `HEADING_WINDOW_S` of flight, never under `MIN_HEADING_WINDOW_M`, so a GPS
/// wiggle in a recorded line does not spin him, and a real turn does.
export const HEADING_WINDOW_S = 0.2;
export const MIN_HEADING_WINDOW_M = 30;

export function trotCyclesPerSecond(speedMps: number): number {
	const factor = speedMps > 0 && Number.isFinite(speedMps) ? speedMps / DEFAULT_FLYOVER_SPEED_MPS : 1;
	return Math.min(MAX_TROT_CYCLES_PER_S, Math.max(MIN_TROT_CYCLES_PER_S, TROT_CYCLES_PER_S * Math.sqrt(factor)));
}

/// The trot's phase (0..1, one cycle) after `elapsedMs` of playback. It is
/// accumulated rather than derived from the clock so a speed change mid-flight
/// changes his pace without jumping his legs.
export function advanceTrot(phase: number, elapsedMs: number, speedMps: number): number {
	const p = Number.isFinite(phase) ? phase : 0;
	const dt = elapsedMs > 0 && Number.isFinite(elapsedMs) ? elapsedMs / 1000 : 0;
	const next = p + dt * trotCyclesPerSecond(speedMps);
	return next - Math.floor(next);
}

/// The export's phase for frame `index`, from the frame clock alone, so a
/// slow machine renders the same legs as a fast one.
export function videoTrotPhase(index: number, fps: number, speedMps: number): number {
	if (!(fps > 0) || !Number.isFinite(index)) return 0;
	const p = (Math.max(0, index) / fps) * trotCyclesPerSecond(speedMps);
	return p - Math.floor(p);
}

export function headingWindowM(speedMps: number): number {
	const s = speedMps > 0 && Number.isFinite(speedMps) ? speedMps : DEFAULT_FLYOVER_SPEED_MPS;
	return Math.max(MIN_HEADING_WINDOW_M, s * HEADING_WINDOW_S);
}

/// The course's compass bearing at `dM`, in degrees clockwise from north,
/// over a chord of `windowM` centred there (shortened at the ends). A chord
/// with no length (a point repeated, or a course shorter than a metre) falls
/// back on the segment heading `cameraAt` gives.
export function mascotHeadingDeg(path: FlyoverPath, dM: number, windowM: number): number {
	const total = path.totalM;
	const d = Math.min(Math.max(0, Number.isFinite(dM) ? dM : 0), total);
	const half = Math.max(0, windowM) / 2;
	const a = pointAtDistance(path, Math.max(0, d - half));
	const b = pointAtDistance(path, Math.min(total, d + half));
	const cosLat = Math.cos((((a.lat + b.lat) / 2) * Math.PI) / 180);
	let dLng = b.lng - a.lng;
	if (dLng > 180) dLng -= 360;
	if (dLng < -180) dLng += 360;
	const x = dLng * cosLat;
	const y = b.lat - a.lat;
	if (Math.hypot(x, y) < 1e-9) return cameraAt(path, d, { smoothingM: 0, centreSmoothingM: 0 }).bearing;
	return normalizeDeg((Math.atan2(x, y) * 180) / Math.PI);
}

/// Which way he faces on screen: his compass heading against the map's
/// bearing, degrees clockwise from screen-up on the ground.
export function screenYawDeg(headingDeg: number, mapBearingDeg: number): number {
	return normalizeDeg(headingDeg - mapBearingDeg);
}

/// He replaces the dot only where the dialog draws in 3D and the viewer has
/// not hidden him. A flat fallback is a slow or WebGL-less device, which
/// should not pay for a second 3D context.
export function mascotWanted(showMascot: boolean, mode: FlyoverMode): boolean {
	return showMascot && mode !== 'flat2d';
}

/// He trots only while the flight plays; under reduced motion, paused, or at
/// the finish, he stands in his rest pose (a null phase).
export function mascotPhase(mode: FlyoverMode, playing: boolean, phase: number): number | null {
	return mode === 'flight' && playing ? phase : null;
}

function normalizeDeg(deg: number): number {
	const r = ((deg % 360) + 360) % 360;
	return r === 360 ? 0 : r;
}
