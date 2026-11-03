import { advance } from '#lib/routes/flyover_path.ts';

export interface Playback {
	dM: number;
	playing: boolean;
}

/// One animation frame of the flight. Reaching the finish stops playback
/// there, so the last frame is the finish rather than a loop back to the start.
export function tick(state: Playback, elapsedMs: number, speedMps: number, totalM: number): Playback {
	if (!state.playing) return state;
	const dM = advance(state.dM, elapsedMs, speedMps, totalM);
	return { dM, playing: dM < totalM };
}

/// Play from where the flight stands — or from the start when it already sits
/// at the finish, which is what a Play press after the end means.
export function play(state: Playback, totalM: number): Playback {
	if (!(totalM > 0)) return { dM: 0, playing: false };
	return { dM: state.dM >= totalM ? 0 : state.dM, playing: true };
}

export function seek(dM: number, totalM: number): Playback {
	const d = Number.isFinite(dM) ? Math.min(Math.max(0, dM), Math.max(0, totalM)) : 0;
	return { dM: d, playing: false };
}
