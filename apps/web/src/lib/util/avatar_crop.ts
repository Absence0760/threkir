/// Pure geometry for the avatar crop step: a square viewport over an image
/// that can be rotated in quarter turns, zoomed, and panned.
///
/// Every quantity is in one of two spaces. VIEWPORT space is the on-screen
/// square, `viewport` px on a side, with the pan measured as the offset of the
/// image centre from the viewport centre. ROTATED space is the source image's
/// pixels after the quarter turns are applied, origin at the rotated image's
/// top-left. The crop rect is returned in rotated space, so the renderer
/// rotates the source first and crops second on both platforms.
///
/// The image always covers the viewport: zoom 1 fits the short side exactly,
/// and the pan is clamped so no edge of the viewport ever shows past the image.
///
/// TS↔Dart parity pair with `apps/mobile_android/lib/avatar_crop.dart`.

export const AVATAR_OUTPUT_MAX_PX = 512;
export const AVATAR_MIN_ZOOM = 1;
export const AVATAR_MAX_ZOOM = 4;

export interface Size {
	width: number;
	height: number;
}

export interface Pan {
	x: number;
	y: number;
}

export interface CropRect {
	x: number;
	y: number;
	size: number;
}

export interface CropState {
	/// Source dimensions with EXIF orientation already applied.
	sourceWidth: number;
	sourceHeight: number;
	quarterTurns: number;
	viewport: number;
	zoom: number;
	pan: Pan;
}

export function normalizeQuarterTurns(quarterTurns: number): number {
	return ((Math.trunc(quarterTurns) % 4) + 4) % 4;
}

export function rotatedSize(width: number, height: number, quarterTurns: number): Size {
	return normalizeQuarterTurns(quarterTurns) % 2 === 0
		? { width, height }
		: { width: height, height: width };
}

export function clampZoom(zoom: number): number {
	if (!Number.isFinite(zoom)) return AVATAR_MIN_ZOOM;
	return Math.min(AVATAR_MAX_ZOOM, Math.max(AVATAR_MIN_ZOOM, zoom));
}

/// Viewport px per rotated-image px at the given zoom.
export function displayScale(rotated: Size, viewport: number, zoom: number): number {
	return (viewport / Math.min(rotated.width, rotated.height)) * clampZoom(zoom);
}

export function clampPan(pan: Pan, rotated: Size, viewport: number, zoom: number): Pan {
	const s = displayScale(rotated, viewport, zoom);
	const maxX = Math.max(0, (rotated.width * s - viewport) / 2);
	const maxY = Math.max(0, (rotated.height * s - viewport) / 2);
	// `+ 0` folds a -0 (from negating a zero pan on rotate) into 0.
	return {
		x: Math.min(maxX, Math.max(-maxX, pan.x)) + 0,
		y: Math.min(maxY, Math.max(-maxY, pan.y)) + 0,
	};
}

/// Change the zoom about the viewport centre: the point under the centre stays
/// under the centre, so the pan scales with the zoom ratio before clamping.
export function rezoom(state: CropState, nextZoom: number): CropState {
	const zoom = clampZoom(nextZoom);
	const ratio = zoom / clampZoom(state.zoom);
	const rotated = rotatedSize(state.sourceWidth, state.sourceHeight, state.quarterTurns);
	return {
		...state,
		zoom,
		pan: clampPan({ x: state.pan.x * ratio, y: state.pan.y * ratio }, rotated, state.viewport, zoom),
	};
}

/// Turn the image a quarter about the viewport centre. `direction` is +1 for
/// clockwise and -1 for counter-clockwise, in screen coordinates (y down). The
/// pan rotates with the image so the same region stays in view.
export function rotate(state: CropState, direction: 1 | -1): CropState {
	const quarterTurns = normalizeQuarterTurns(state.quarterTurns + direction);
	const pan =
		direction === 1 ? { x: -state.pan.y, y: state.pan.x } : { x: state.pan.y, y: -state.pan.x };
	const rotated = rotatedSize(state.sourceWidth, state.sourceHeight, quarterTurns);
	return {
		...state,
		quarterTurns,
		pan: clampPan(pan, rotated, state.viewport, state.zoom),
	};
}

export function panBy(state: CropState, dx: number, dy: number): CropState {
	const rotated = rotatedSize(state.sourceWidth, state.sourceHeight, state.quarterTurns);
	return {
		...state,
		pan: clampPan({ x: state.pan.x + dx, y: state.pan.y + dy }, rotated, state.viewport, state.zoom),
	};
}

/// The square of rotated-space pixels the viewport shows, snapped to whole
/// pixels and kept inside the image.
export function cropRect(state: CropState): CropRect {
	const rotated = rotatedSize(state.sourceWidth, state.sourceHeight, state.quarterTurns);
	const pan = clampPan(state.pan, rotated, state.viewport, state.zoom);
	const s = displayScale(rotated, state.viewport, state.zoom);
	const shortSide = Math.min(rotated.width, rotated.height);
	const size = Math.max(1, Math.min(shortSide, Math.round(state.viewport / s)));
	const left = rotated.width / 2 - (state.viewport / 2 + pan.x) / s;
	const top = rotated.height / 2 - (state.viewport / 2 + pan.y) / s;
	return {
		x: Math.min(rotated.width - size, Math.max(0, Math.round(left))),
		y: Math.min(rotated.height - size, Math.max(0, Math.round(top))),
		size,
	};
}

/// Edge length of the encoded avatar: never upscaled, never above the cap.
export function outputSize(cropSize: number, max: number = AVATAR_OUTPUT_MAX_PX): number {
	return Math.max(1, Math.min(max, Math.round(cropSize)));
}

export function initialCropState(sourceWidth: number, sourceHeight: number, viewport: number): CropState {
	return { sourceWidth, sourceHeight, quarterTurns: 0, viewport, zoom: 1, pan: { x: 0, y: 0 } };
}
