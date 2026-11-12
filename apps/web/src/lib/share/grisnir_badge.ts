/// Grisnir, the Threkir goat, as a small corner badge on a share card built as
/// an SVG string (the `/og/*` unfurls). resvg in the share Lambdas loads no
/// files, so the PNG travels inline as a data URI (`grisnir_badge_data.ts`,
/// generated from the head-and-horns crop, apps/web/static/brand/grisnir/grisnir-head-256.png:
/// the whole goat read as a white blob at feed width).
///
/// Each card picks its own corner, one clear of its route, stats and name; the
/// badge never sits over them (apps/web/static/brand/grisnir/README.md).

import { GRISNIR_BADGE_HEIGHT, GRISNIR_BADGE_PNG_BASE64, GRISNIR_BADGE_WIDTH } from './grisnir_badge_data';

/// The badge's drawn height on a 1200 x 630 unfurl: about 54 px when a feed
/// shows the card 360 px wide, so the face and horns read at feed size.
export const OG_GRISNIR_HEIGHT = 180;

/// The badge's width at `height`, from the render's own aspect.
export function grisnirBadgeWidth(height: number): number {
	return Math.round((height * GRISNIR_BADGE_WIDTH) / GRISNIR_BADGE_HEIGHT);
}

/// An `<image>` of the badge with its top-left corner at (`x`, `y`).
export function grisnirBadgeSvg(x: number, y: number, height: number = OG_GRISNIR_HEIGHT): string {
	const w = grisnirBadgeWidth(height);
	return `<image data-mascot="grisnir" x="${x}" y="${y}" width="${w}" height="${height}" href="data:image/png;base64,${GRISNIR_BADGE_PNG_BASE64}"/>`;
}
