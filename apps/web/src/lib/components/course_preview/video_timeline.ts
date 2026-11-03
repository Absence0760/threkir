import { DEFAULT_FLYOVER_SPEED_MPS } from '#lib/routes/flyover_path.ts';

/// The exported flyover video's clock. Every frame is a function of its index
/// alone, never of wall time, so a slow machine renders the same video a fast
/// one does, only more slowly: frame `i` shows the course at the distance
/// `videoFrame` names and carries the timestamp `frameTimestampUs` names.

export const VIDEO_WIDTH = 1080;
export const VIDEO_HEIGHT = 1920;
export const VIDEO_FPS = 30;

/// A flight takes as long as the dialog's default speed would, held between
/// these bounds: a 2 km loop still gets a reel worth posting, and an ultra
/// does not become a two-minute file nobody watches.
export const MIN_FLIGHT_S = 8;
export const MAX_FLIGHT_S = 20;
export const END_CARD_S = 3;
export const KEYFRAME_INTERVAL_S = 2;

export interface VideoTimeline {
	fps: number;
	flightFrames: number;
	endFrames: number;
	totalFrames: number;
}

export type VideoFrame =
	| { phase: 'flight'; dM: number; progress: number }
	| { phase: 'end'; dM: number; progress: number };

export function videoTimeline(totalM: number, fps = VIDEO_FPS): VideoTimeline {
	const naturalS = totalM > 0 ? totalM / DEFAULT_FLYOVER_SPEED_MPS : 0;
	const flightS = Math.min(MAX_FLIGHT_S, Math.max(MIN_FLIGHT_S, naturalS));
	const flightFrames = Math.max(2, Math.round(flightS * fps));
	const endFrames = Math.round(END_CARD_S * fps);
	return { fps, flightFrames, endFrames, totalFrames: flightFrames + endFrames };
}

/// The flight's first frame sits on the start and its last on the finish, so
/// the counter the overlay ticks up ends on the run's own distance. The end
/// card holds the finish while it fades in.
export function videoFrame(t: VideoTimeline, index: number, totalM: number): VideoFrame {
	const i = Math.min(Math.max(0, Math.floor(index)), t.totalFrames - 1);
	const total = totalM > 0 ? totalM : 0;
	if (i < t.flightFrames) {
		const progress = i / (t.flightFrames - 1);
		return { phase: 'flight', dM: total * progress, progress };
	}
	const e = i - t.flightFrames;
	return { phase: 'end', dM: total, progress: t.endFrames > 1 ? e / (t.endFrames - 1) : 1 };
}

/// Whole microseconds, rounded from the exact rational time, so the gaps
/// alternate 33333 / 33334 µs at 30 fps and never accumulate drift.
export function frameTimestampUs(index: number, fps: number): number {
	return Math.round((index * 1_000_000) / fps);
}

export function frameDurationUs(index: number, fps: number): number {
	return frameTimestampUs(index + 1, fps) - frameTimestampUs(index, fps);
}

export function isKeyFrame(index: number, fps: number): boolean {
	return index % Math.max(1, Math.round(fps * KEYFRAME_INTERVAL_S)) === 0;
}
