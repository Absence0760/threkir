// The PR card: one personal record on a solid ground, in the share editor's
// post (4:5) or story (9:16) canvas, drawn by the same op painter as the photo
// and sticker images so the type, the route line and the signature match them.
// Web's twin of `RunPrShareCard` in apps/mobile_android/lib/widgets/
// run_share_overlays.dart. Layout is pure over a text-measuring callback so it
// is unit tested without a canvas.

import type { TrackPoint } from '../types';
import { OG_CARD_DARK, OG_CARD_LIGHT, THREKIR_MARK_GRADIENT } from './og_card_palette';
import {
	brand,
	canvasMeasure,
	paintOps,
	photoCanvasSize,
	sizedCanvas,
	type DrawOp,
	type FontSpec,
	type Laid,
	type MeasureText,
} from './run_sticker_canvas';
import type { RunPhotoAspect, RunShareInk } from './share_look';

/// The words the card prints, already localised.
export interface PrCardText {
	/// "New personal record".
	headline: string;
	/// The bracket, "5K" / "Half marathon".
	distance: string;
	/// The record time, "24:00".
	time: string;
	/// "00:42 faster", or null when nothing was beaten.
	improvement: string | null;
	/// "Previous best 24:42" / "First 5K on record", or null.
	detail: string | null;
	/// The run's date.
	date: string;
}

/// The ground each ink is drawn on: the white ink and the coral ink on the
/// dark card, the dark ink on white paper — the grounds their contrast was
/// measured against in og_card_palette.ts.
export const PR_CARD_GROUNDS: Record<RunShareInk, string> = {
	light: OG_CARD_DARK.bg,
	brand: OG_CARD_DARK.bg,
	dark: OG_CARD_LIGHT.bg,
};

const HEADLINE: FontSpec = { size: 13, weight: 800, letterSpacing: 2 };
const DISTANCE: FontSpec = { size: 30, weight: 800, letterSpacing: 0 };
const TIME: FontSpec = { size: 84, weight: 800, letterSpacing: -1 };
const IMPROVEMENT: FontSpec = { size: 24, weight: 800, letterSpacing: 0 };
const DETAIL: FontSpec = { size: 15, weight: 700, letterSpacing: 0 };
/// The route's largest size, and the smallest worth drawing: on a 4:5 post the
/// lines leave less than the largest, so the route takes what is left.
const ROUTE = 110;
const ROUTE_MIN = 40;
const ROUTE_GAP = 22;

/// The accent band across the top of the card, in logical pixels.
export const PR_CARD_BAND = 6;

export function layoutPrCard(
	aspect: RunPhotoAspect,
	text: PrCardText,
	hasRoute: boolean,
	wordmark: string | null,
	measure: MeasureText,
): Laid {
	const { w, h } = photoCanvasSize(aspect);
	const pad = 28;
	const boxW = w - pad * 2;
	// A story keeps its content clear of the bottom eighth the viewer's reply
	// bar covers, as the photo style does.
	const bottom = aspect === 'story' ? h * 0.13 : pad;

	type Line = { text: string; font: FontSpec; ink: 'text' | 'muted'; gapAfter: number };
	const lines: Line[] = [
		{ text: text.headline.toUpperCase(), font: HEADLINE, ink: 'muted', gapAfter: 14 },
		{ text: text.distance, font: DISTANCE, ink: 'text', gapAfter: 4 },
		{ text: text.time, font: TIME, ink: 'text', gapAfter: 10 },
	];
	if (text.improvement) lines.push({ text: text.improvement, font: IMPROVEMENT, ink: 'text', gapAfter: 6 });
	if (text.detail) lines.push({ text: text.detail, font: DETAIL, ink: 'muted', gapAfter: 6 });
	lines.push({ text: text.date, font: DETAIL, ink: 'muted', gapAfter: 0 });

	const lineH = (f: FontSpec) => f.size * 1.2;
	const linesH = lines.reduce((sum, l) => sum + lineH(l.font) + l.gapAfter, 0);

	const ops: DrawOp[] = [];
	const top = PR_CARD_BAND + pad;
	const brandLaid: Laid = wordmark === null ? { ops: [], width: w, height: 0 } : brand(w, wordmark, measure);
	const brandY = h - bottom - brandLaid.height;
	const room = brandY - 18 - top;
	const fits = Math.min(ROUTE, room - linesH - ROUTE_GAP);
	const routeSize = hasRoute && fits >= ROUTE_MIN ? fits : 0;
	const contentH = linesH + (routeSize > 0 ? routeSize + ROUTE_GAP : 0);
	let y = top + Math.max(0, (room - contentH) / 2);
	for (const l of lines) {
		const scale = Math.min(1, boxW / Math.max(1, measure(l.text, l.font)));
		const lh = lineH(l.font) * scale;
		ops.push({
			kind: 'text',
			text: l.text,
			x: w / 2,
			y: y + lh / 2 + l.font.size * 0.36 * scale,
			font: l.font,
			ink: l.ink,
			scale,
			align: 'center',
		});
		y += lh + l.gapAfter;
	}
	if (routeSize > 0) {
		y += ROUTE_GAP;
		ops.push({ kind: 'route', x: (w - routeSize) / 2, y, size: routeSize });
	}
	ops.push(...brandLaid.ops.map((op) => ({ ...op, y: op.y + brandY })));
	return { ops, width: w, height: h };
}

export interface PrCardInput {
	aspect: RunPhotoAspect;
	ink: RunShareInk;
	text: PrCardText;
	/// The clipped share line (`shareCardTrack`), never a raw track.
	track: TrackPoint[];
	wordmark: string | null;
}

export function paintPrCard(input: PrCardInput): HTMLCanvasElement {
	const probe = document.createElement('canvas').getContext('2d');
	if (!probe) throw new Error('2D canvas unavailable');
	const laid = layoutPrCard(input.aspect, input.text, input.track.length >= 2, input.wordmark, canvasMeasure(probe));
	const { canvas, ctx, k } = sizedCanvas(laid);
	ctx.fillStyle = PR_CARD_GROUNDS[input.ink];
	ctx.fillRect(0, 0, laid.width, laid.height);
	const band = ctx.createLinearGradient(0, 0, laid.width, 0);
	band.addColorStop(0, THREKIR_MARK_GRADIENT[0]);
	band.addColorStop(0.5, THREKIR_MARK_GRADIENT[1]);
	band.addColorStop(1, THREKIR_MARK_GRADIENT[2]);
	ctx.fillStyle = band;
	ctx.fillRect(0, 0, laid.width, PR_CARD_BAND);
	paintOps(ctx, laid.ops, input.track, input.ink, k);
	return canvas;
}
