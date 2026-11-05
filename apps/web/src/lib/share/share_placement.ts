// Where the title-and-stats block sits on a photo share image, and how big it
// is. Twin of apps/mobile_android/lib/share_placement.dart: the same frame,
// scale bounds, clamp and fail-closed decode.
//
// A placement is the block's centre as a fraction of the canvas plus a scale
// on the size the block is laid out at, so it means the same thing on the
// fixed 360 px logical canvas, in the editor's preview at any size, and in the
// 1080 px export.

/// The block's centre as fractions of the canvas width (`x`) and height (`y`),
/// and its size as a multiple of the size it is laid out at (`scale`).
export interface SharePlacement {
	x: number;
	y: number;
	scale: number;
}

/// Centred, and as low as the frame lets it sit: `y` 1 clamps the block onto
/// the frame's bottom edge, which is where the stats sat before they could
/// move.
export const DEFAULT_SHARE_PLACEMENT: Readonly<SharePlacement> = Object.freeze({ x: 0.5, y: 1, scale: 1 });

/// The block is laid out at the frame's full width (320 of the canvas's 360
/// logical px), so it cannot grow past the size it is laid out at without
/// leaving the frame.
export const SHARE_PLACEMENT_MAX_SCALE = 1;

/// The smallest size, in logical px, the block's smallest text may shrink to:
/// 18 px on the 1080 px export. The default strip layout already draws its
/// 12 px labels at 12 × 320 / 560 = 6.86 px, so this lets a block shrink to
/// about an eighth under the smallest text the share images ship by default.
export const SHARE_PLACEMENT_MIN_TEXT_PX = 6;

/// The block's 12 px labels at the smallest text floor: 6 / 12.
export const SHARE_PLACEMENT_MIN_SCALE = 0.5;

/// The inset every edge of the frame keeps from the canvas edge.
export const SHARE_PLACEMENT_MARGIN = 20;

/// The bottom eighth a story viewer's reply bar covers, kept clear on a story.
export const STORY_REPLY_BAR_FRACTION = 0.13;

/// The bottom inset on a 4:5 post, which has no reply bar.
export const POST_BOTTOM_MARGIN = 22;

export interface PlacementRect {
	left: number;
	top: number;
	width: number;
	height: number;
}

/// The part of a `width` × `height` canvas the block must stay inside: the
/// margin on every side, and on a story the reply-bar strip as well.
export function sharePlacementFrame(width: number, height: number, story: boolean): PlacementRect {
	const bottom = story ? height * STORY_REPLY_BAR_FRACTION : POST_BOTTOM_MARGIN;
	return {
		left: SHARE_PLACEMENT_MARGIN,
		top: SHARE_PLACEMENT_MARGIN,
		width: width - SHARE_PLACEMENT_MARGIN * 2,
		height: height - SHARE_PLACEMENT_MARGIN - bottom,
	};
}

/// The smallest scale that keeps text drawn at `smallestTextPx` (at scale 1)
/// no smaller than SHARE_PLACEMENT_MIN_TEXT_PX. A block whose smallest text is
/// already at the floor cannot shrink at all.
export function minSharePlacementScale(smallestTextPx: number): number {
	if (!(smallestTextPx > 0)) return SHARE_PLACEMENT_MAX_SCALE;
	return Math.min(
		SHARE_PLACEMENT_MAX_SCALE,
		Math.max(SHARE_PLACEMENT_MIN_SCALE, SHARE_PLACEMENT_MIN_TEXT_PX / smallestTextPx),
	);
}

export interface PlacedShareBlock extends PlacementRect {
	/// The scale the block is drawn at, inside its bounds.
	scale: number;
	/// The placement the block actually took, clamped: what a drag starts from
	/// and what is stored.
	placement: SharePlacement;
}

function clamp(v: number, lo: number, hi: number): number {
	return Math.min(hi, Math.max(lo, v));
}

/// Where a block `blockW` × `blockH` (at scale 1) lands on a `canvasW` ×
/// `canvasH` canvas: scaled within [minScale, MAX], never larger than the
/// frame, and moved the least distance that keeps it wholly inside the frame.
export function placeShareBlock(
	placement: SharePlacement,
	blockW: number,
	blockH: number,
	canvasW: number,
	canvasH: number,
	frame: PlacementRect,
	minScale: number,
): PlacedShareBlock {
	const fit = blockW > 0 && blockH > 0 ? Math.min(frame.width / blockW, frame.height / blockH) : 1;
	const hi = Math.min(SHARE_PLACEMENT_MAX_SCALE, fit);
	const lo = Math.min(minScale, hi);
	const p = Number.isFinite(placement.scale) ? placement : { ...placement, scale: DEFAULT_SHARE_PLACEMENT.scale };
	const scale = clamp(p.scale, lo, hi);
	const width = blockW * scale;
	const height = blockH * scale;
	const x = Number.isFinite(p.x) ? p.x : DEFAULT_SHARE_PLACEMENT.x;
	const y = Number.isFinite(p.y) ? p.y : DEFAULT_SHARE_PLACEMENT.y;
	const cx = clamp(x * canvasW, frame.left + width / 2, frame.left + frame.width - width / 2);
	const cy = clamp(y * canvasH, frame.top + height / 2, frame.top + frame.height - height / 2);
	return {
		left: cx - width / 2,
		top: cy - height / 2,
		width,
		height,
		scale,
		placement: { x: cx / canvasW, y: cy / canvasH, scale },
	};
}

/// `placement` moved by `dx` × `dy` logical px on a `canvasW` × `canvasH`
/// canvas. Unclamped: place it again to keep it in the frame.
export function moveSharePlacement(
	placement: SharePlacement,
	dx: number,
	dy: number,
	canvasW: number,
	canvasH: number,
): SharePlacement {
	return { x: placement.x + dx / canvasW, y: placement.y + dy / canvasH, scale: placement.scale };
}

/// `placement` resized by `factor` about its centre. Unclamped.
export function resizeSharePlacement(placement: SharePlacement, factor: number): SharePlacement {
	return { ...placement, scale: placement.scale * factor };
}

export function sharePlacementEquals(a: SharePlacement, b: SharePlacement): boolean {
	return a.x === b.x && a.y === b.y && a.scale === b.scale;
}

export function sharePlacementToJson(p: SharePlacement): Record<string, number> {
	return { x: p.x, y: p.y, scale: p.scale };
}

function inRange(v: unknown, lo: number, hi: number): v is number {
	return typeof v === 'number' && Number.isFinite(v) && v >= lo && v <= hi;
}

/// A stored placement, or the default when any of its three values is
/// missing, not a number, or outside the range a placement can hold. Fails
/// closed as a whole: a centre with no trustworthy scale is not a placement.
export function sharePlacementFromJson(json: unknown): SharePlacement {
	if (json === null || typeof json !== 'object' || Array.isArray(json)) return { ...DEFAULT_SHARE_PLACEMENT };
	const o = json as Record<string, unknown>;
	if (
		!inRange(o.x, 0, 1) ||
		!inRange(o.y, 0, 1) ||
		!inRange(o.scale, SHARE_PLACEMENT_MIN_SCALE, SHARE_PLACEMENT_MAX_SCALE)
	) {
		return { ...DEFAULT_SHARE_PLACEMENT };
	}
	return { x: o.x, y: o.y, scale: o.scale };
}
