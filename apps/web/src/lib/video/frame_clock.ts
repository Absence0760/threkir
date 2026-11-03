/// The clock every exported video runs on (decisions § 2259, § 2269). A frame
/// is a function of its index alone, never of wall time, so a slow machine
/// renders the same file a fast one does, only more slowly.

export const VIDEO_WIDTH = 1080;
export const VIDEO_HEIGHT = 1920;
export const VIDEO_FPS = 30;
export const KEYFRAME_INTERVAL_S = 2;

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
