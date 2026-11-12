import { DEFAULT_FLYOVER_SPEED_MPS } from '#lib/routes/flyover_path.ts';
import { VIDEO_FPS } from '#lib/video/frame_clock.ts';
import { finaleDurationMs, finalePlan } from './overview.ts';

/// The exported flyover's timeline on the shared frame clock
/// (`#lib/video/frame_clock.ts`): frame `i` shows the course at the distance
/// `videoFrame` names and carries the timestamp `frameTimestampUs` names.

/// A flight takes as long as the dialog's default speed would, held between
/// these bounds: a 2 km loop still gets a reel worth posting, and an ultra
/// does not become a two-minute file nobody watches.
export const MIN_FLIGHT_S = 8;
export const MAX_FLIGHT_S = 20;
export const END_CARD_S = 3;

/// A file is not motion on the viewer's screen (decisions § 2259), so the
/// video always carries the full ending: the ease out to the overview and
/// the orbit, between the finish and the end card.
export const VIDEO_FINALE = finalePlan(false);

export interface VideoTimeline {
	fps: number;
	flightFrames: number;
	overviewFrames: number;
	endFrames: number;
	totalFrames: number;
}

export type VideoFrame =
	| { phase: 'flight'; dM: number; progress: number }
	| { phase: 'overview'; dM: number; tMs: number }
	| { phase: 'end'; dM: number; progress: number };

export function videoTimeline(totalM: number, fps = VIDEO_FPS): VideoTimeline {
	const naturalS = totalM > 0 ? totalM / DEFAULT_FLYOVER_SPEED_MPS : 0;
	const flightS = Math.min(MAX_FLIGHT_S, Math.max(MIN_FLIGHT_S, naturalS));
	const flightFrames = Math.max(2, Math.round(flightS * fps));
	const overviewFrames = Math.round((finaleDurationMs(VIDEO_FINALE) / 1000) * fps);
	const endFrames = Math.round(END_CARD_S * fps);
	return { fps, flightFrames, overviewFrames, endFrames, totalFrames: flightFrames + overviewFrames + endFrames };
}

/// The speed the flight covers the course at, for the camera's heading
/// smoothing and turn limit (`cameraAt`): the first flight frame is the start
/// and the last the finish, `flightFrames - 1` frame steps apart.
export function videoFlightSpeedMps(t: VideoTimeline, totalM: number): number {
	const total = totalM > 0 ? totalM : 0;
	return (total * t.fps) / (t.flightFrames - 1);
}

/// The flight's first frame sits on the start and its last on the finish, so
/// the counter the overlay ticks up ends on the run's own distance. The
/// overview frames then step the ending's clock (`finaleCamera`) from the
/// frame after the finish to its last pose, which the end card holds while it
/// fades in.
export function videoFrame(t: VideoTimeline, index: number, totalM: number): VideoFrame {
	const i = Math.min(Math.max(0, Math.floor(index)), t.totalFrames - 1);
	const total = totalM > 0 ? totalM : 0;
	if (i < t.flightFrames) {
		const progress = i / (t.flightFrames - 1);
		return { phase: 'flight', dM: total * progress, progress };
	}
	const o = i - t.flightFrames;
	if (o < t.overviewFrames) {
		return { phase: 'overview', dM: total, tMs: ((o + 1) * 1000) / t.fps };
	}
	const e = o - t.overviewFrames;
	return { phase: 'end', dM: total, progress: t.endFrames > 1 ? e / (t.endFrames - 1) : 1 };
}
