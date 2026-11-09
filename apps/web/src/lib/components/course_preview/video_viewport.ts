import { OVERVIEW_PADDING_PX } from './overview.ts';

/// The CSS width of the phone the on-screen preview is framed for. A zoom
/// level shows ground in proportion to CSS pixels, so the export renders its
/// map at this width and scales it up, or zoom 14 would show ~2.8x more
/// ground at 1080 CSS px than the preview the runner just watched.
export const VIDEO_REFERENCE_CSS_WIDTH = 390;

export interface VideoMapViewport {
	cssWidth: number;
	cssHeight: number;
	pixelRatio: number;
}

function gcd(a: number, b: number): number {
	return b === 0 ? a : gcd(b, a % b);
}

/// The offscreen map's CSS size and pixel ratio for a `width` x `height`
/// video. MapLibre floors the container to whole CSS pixels and rounds the
/// canvas to `pixelRatio` times that, so the CSS size is the whole-pixel
/// multiple of the video's aspect nearest the reference width: then the
/// canvas comes out at exactly the video's size and is copied into it 1:1.
export function videoMapViewport(
	width: number,
	height: number,
	referenceCssWidth: number = VIDEO_REFERENCE_CSS_WIDTH,
): VideoMapViewport {
	const g = gcd(width, height);
	const stepW = width / g;
	const stepH = height / g;
	const k = Math.max(1, Math.min(g, Math.round(referenceCssWidth / stepW)));
	const cssWidth = stepW * k;
	return { cssWidth, cssHeight: stepH * k, pixelRatio: width / cssWidth };
}

/// The overview fit's padding, in the map's CSS pixels. The scrims are
/// measured in video pixels by `videoOverlayLayout`, so they are divided by
/// the pixel ratio; the side margin is the preview's own, already CSS.
export function videoOverviewPadding(
	scrims: { topScrim: number; bottomScrim: number },
	pixelRatio: number,
): { top: number; bottom: number; left: number; right: number } {
	return {
		top: scrims.topScrim / pixelRatio,
		bottom: scrims.bottomScrim / pixelRatio,
		left: OVERVIEW_PADDING_PX,
		right: OVERVIEW_PADDING_PX,
	};
}
