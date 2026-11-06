// The photo and sticker share images, drawn on a 2D canvas. Web's twin of
// `RunStickerContent` / `RunStickerShareCard` / `RunPhotoShareCard` in
// apps/mobile_android/lib/widgets/run_share_overlays.dart: the same fixed
// logical canvases (decisions § 2250), the same four layouts and the same
// occasion stickers at the same sizes and spacing, rasterised to 1080 px
// across.
//
// Layout is a pure function over a text-measuring callback, so it is unit
// tested without a canvas; `paintSticker` / `paintPhoto` only execute the ops
// it returns. The photo is drawn onto the canvas rather than forwarded, which
// re-encodes its pixels and leaves its EXIF, location included, behind
// (decisions § 2248). The sticker's canvas is its own content's size, so the
// PNG is cropped to what it draws and keeps its alpha.

import type { TrackPoint } from '../types';
import { projectTrack } from '../routes/track_projection';
import { SHARE_STICKER_INKS, THREKIR_MARK_GRADIENT } from './og_card_palette';
import type { RunShareStat } from './run_share_stats';
import {
	averageStickerPace,
	fastestStickerSplit,
	splitsColumnCapacity,
	splitsStickerForm,
	type RunPhotoAspect,
	type RunShareInk,
	type RunStickerLayout,
	type SplitsStickerForm,
	type SplitsStickerRow,
} from './share_look';
import {
	DEFAULT_SHARE_PLACEMENT,
	minSharePlacementScale,
	placeShareBlock,
	sharePlacementFrame,
	type PlacedShareBlock,
	type PlacementRect,
	type SharePlacement,
} from './share_placement';

/// Every share image is rasterised to this many pixels across, so a story or
/// a feed post is never upscaled, whatever screen made it.
export const SHARE_EXPORT_WIDTH_PX = 1080;

/// Padding round a sticker's content, inside its own canvas.
export const STICKER_PAD = 16;

/// The strip is one line, so it is laid out wide; every other layout stacks.
export function stickerContentWidth(layout: RunStickerLayout): number {
	return layout === 'strip' ? 560 : 320;
}

export function stickerCanvasWidth(layout: RunStickerLayout): number {
	return stickerContentWidth(layout) + STICKER_PAD * 2;
}

export function photoCanvasSize(aspect: RunPhotoAspect): { w: number; h: number } {
	return aspect === 'post' ? { w: 360, h: 450 } : { w: 360, h: 640 };
}

export const SHARE_FONT_STACK = "'Manrope', system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif";

export interface FontSpec {
	size: number;
	weight: number;
	letterSpacing: number;
}

/// Width of `text` in logical pixels at `font`, letter spacing included.
export type MeasureText = (text: string, font: FontSpec) => number;

export type InkRole = 'text' | 'muted' | 'accent';

export type DrawOp =
	| {
			kind: 'text';
			text: string;
			/// The run's horizontal centre, or its left or right edge.
			x: number;
			/// The alphabetic baseline.
			y: number;
			font: FontSpec;
			ink: InkRole;
			/// Scale-down applied about (x, y) so a long value fits its column.
			scale: number;
			align: 'center' | 'left' | 'right';
	  }
	| { kind: 'route'; x: number; y: number; size: number }
	| { kind: 'bar'; x: number; y: number; w: number; h: number; ink: InkRole }
	| { kind: 'divider'; x: number; y: number; w: number; h: number }
	| { kind: 'mark'; x: number; y: number; size: number };

export interface Laid {
	ops: DrawOp[];
	width: number;
	height: number;
}

// The Material 3 type steps the mobile overlays take from the theme.
const LABEL = { size: 12, weight: 700, letterSpacing: 1.6, lineHeight: 16 };
const UNIT = { size: 14, weight: 700, letterSpacing: 0 };
const BRAND = { size: 14, weight: 800, letterSpacing: 2.6 };
const BRAND_MARK = 18;
const STEP = { displayLarge: 57, displaySmall: 36, headlineMedium: 28, titleLarge: 22 } as const;

function translate(op: DrawOp, dx: number, dy: number): DrawOp {
	return { ...op, x: op.x + dx, y: op.y + dy };
}

/// A small uppercase label over a large value with its unit, centred in a
/// column `width` wide; each line scales down rather than overflowing it.
function figure(stat: RunShareStat, valueSize: number, width: number, measure: MeasureText): Laid {
	const label = stat.label.toUpperCase();
	const labelFont: FontSpec = { size: LABEL.size, weight: LABEL.weight, letterSpacing: LABEL.letterSpacing };
	const labelScale = Math.min(1, width / Math.max(1, measure(label, labelFont)));

	const valueFont: FontSpec = { size: valueSize, weight: 800, letterSpacing: -0.5 };
	const valueW = measure(stat.value, valueFont);
	const unitW = stat.unit ? measure(stat.unit, UNIT) : 0;
	const rowW = valueW + (stat.unit ? 4 + unitW : 0);
	const valueScale = Math.min(1, width / Math.max(1, rowW));

	const cx = width / 2;
	const labelH = LABEL.lineHeight * labelScale;
	const valueH = valueSize * 1.05 * valueScale;
	const ops: DrawOp[] = [
		{
			kind: 'text',
			text: label,
			x: cx,
			y: labelH * 0.5 + LABEL.size * 0.36 * labelScale,
			font: labelFont,
			ink: 'muted',
			scale: labelScale,
			align: 'center',
		},
	];
	const baseline = labelH + valueH * 0.5 + valueSize * 0.36 * valueScale;
	const left = cx - (rowW * valueScale) / 2;
	ops.push({ kind: 'text', text: stat.value, x: left, y: baseline, font: valueFont, ink: 'text', scale: valueScale, align: 'left' });
	if (stat.unit) {
		ops.push({
			kind: 'text',
			text: stat.unit,
			x: left + (valueW + 4) * valueScale,
			y: baseline,
			font: UNIT,
			ink: 'muted',
			scale: valueScale,
			align: 'left',
		});
	}
	return { ops, width, height: labelH + valueH };
}

export function brand(width: number, wordmark: string, measure: MeasureText): Laid {
	const text = wordmark.toUpperCase();
	const gap = BRAND_MARK * 0.45;
	const total = BRAND_MARK + gap + measure(text, BRAND);
	const left = (width - total) / 2;
	return {
		ops: [
			{ kind: 'mark', x: left, y: 0, size: BRAND_MARK },
			{
				kind: 'text',
				text,
				x: left + BRAND_MARK + gap,
				y: BRAND_MARK / 2 + BRAND.size * 0.36,
				font: BRAND,
				ink: 'text',
				scale: 1,
				align: 'left',
			},
		],
		width,
		height: BRAND_MARK,
	};
}

/// Stats side by side in equal columns, bottoms aligned.
function row(stats: RunShareStat[], valueSize: number, width: number, gap: number, measure: MeasureText): Laid {
	const col = (width - gap * (stats.length - 1)) / stats.length;
	const figs = stats.map((s) => figure(s, valueSize, col, measure));
	const height = Math.max(...figs.map((f) => f.height));
	const ops = figs.flatMap((f, i) => f.ops.map((op) => translate(op, i * (col + gap), height - f.height)));
	return { ops, width, height };
}

/// One layout's stats, route and signature, `stickerContentWidth(layout)`
/// wide and as tall as it draws, with no ground of its own. A null `wordmark`
/// draws no signature (the runner turned the Threkir mark off).
export function layoutStickerContent(
	layout: RunStickerLayout,
	stats: RunShareStat[],
	hasRoute: boolean,
	wordmark: string | null,
	measure: MeasureText,
): Laid {
	const width = stickerContentWidth(layout);
	const ops: DrawOp[] = [];
	let y = 0;
	const place = (laid: Laid, dx = 0) => {
		ops.push(...laid.ops.map((op) => translate(op, dx, y)));
		y += laid.height;
	};
	const route = (size: number, after: number) => {
		ops.push({ kind: 'route', x: (width - size) / 2, y, size });
		y += size + after;
	};

	switch (layout) {
		case 'stack':
			for (const stat of stats) {
				place(figure(stat, STEP.displaySmall * 1.25, width, measure));
				y += 14;
			}
			if (hasRoute) route(150, 16);
			break;
		case 'route':
			if (hasRoute) route(width * 0.82, 14);
			place(row(stats, STEP.headlineMedium, width, 12, measure));
			y += 16;
			break;
		case 'strip': {
			const divider = 2;
			const margin = 10;
			const gap = divider + margin * 2;
			const r = row(stats, STEP.headlineMedium, width, gap, measure);
			const h = Math.max(44, r.height);
			const col = (width - gap * (stats.length - 1)) / stats.length;
			// Centred rather than bottom-aligned: the strip is a Row with
			// `crossAxisAlignment.center` on mobile.
			ops.push(...r.ops.map((op) => translate(op, 0, y + (h - r.height) / 2)));
			for (let i = 1; i < stats.length; i++) {
				ops.push({ kind: 'divider', x: i * (col + gap) - margin - divider, y: y + (h - 44) / 2, w: divider, h: 44 });
			}
			y += h + 12;
			break;
		}
		case 'hero': {
			const [first, ...rest] = stats;
			place(figure(first, STEP.displayLarge * 1.6, width, measure));
			if (rest.length > 0) {
				y += 10;
				place(row(rest, STEP.titleLarge, width, 12, measure));
			}
			y += 16;
			break;
		}
	}
	if (wordmark !== null) place(brand(width, wordmark, measure));
	return { ops, width, height: y };
}


/// One line of an occasion sticker, set at one of the type steps below and
/// centred. `maxLines` above 1 wraps on words; a single line scales down
/// rather than overflowing the width.
export type OccasionStep = 'label' | 'title' | 'headline' | 'display' | 'hero';

export interface OccasionLine {
	text: string;
	step: OccasionStep;
	ink: InkRole;
	maxLines?: number;
}

const OCCASION_STEPS: Record<OccasionStep, FontSpec & { lineHeight: number }> = {
	label: { size: LABEL.size, weight: LABEL.weight, letterSpacing: LABEL.letterSpacing, lineHeight: LABEL.lineHeight },
	title: { size: STEP.titleLarge, weight: 700, letterSpacing: 0, lineHeight: 28 },
	headline: { size: STEP.headlineMedium, weight: 800, letterSpacing: 0, lineHeight: 34 },
	display: { size: STEP.displayLarge * 1.25, weight: 800, letterSpacing: -0.5, lineHeight: STEP.displayLarge * 1.25 * 1.05 },
	hero: { size: STEP.displayLarge * 1.8, weight: 800, letterSpacing: -1, lineHeight: STEP.displayLarge * 1.8 },
};

/// The gap between two lines of an occasion sticker.
export const OCCASION_LINE_GAP = 6;

/// One table row of the splits sticker: the split's number (or a partial
/// tail's length) and its pace, already formatted.
export interface SplitsStickerEntry {
	label: string;
	pace: string;
	row: SplitsStickerRow;
}

/// What a sticker draws. `stats` is the run's numbers in a layout; `lines` is
/// an occasion as a stack of lines (a record, a streak day, a race, a badge)
/// over an optional route; `splits` is the run's splits as a table or bars.
/// The route-only sticker is `lines` with no lines.
export type StickerBody =
	| { kind: 'stats'; layout: RunStickerLayout; stats: RunShareStat[]; hasRoute: boolean }
	| { kind: 'lines'; lines: OccasionLine[]; route: number }
	| { kind: 'splits'; heading: string; entries: SplitsStickerEntry[] };

export const OCCASION_CONTENT_WIDTH = 320;

/// The splits sticker's type and pitch. The cut-overs between its forms are
/// derived from these and the budget, never written down.
export const SPLIT_ROW_TEXT = STEP.titleLarge;
export const SPLIT_ROW_H = 30;
const SPLIT_HEADING_GAP = 10;
const SPLIT_BRAND_GAP = 12;
const SPLIT_BARS_H = 120;
const SPLIT_BAR_MIN = 0.2;
const SPLIT_SINGLE_W = 220;
const SPLIT_COLUMN_GAP = 20;

/// Everything on a splits sticker that is not a row: the padding, the
/// heading, the signature and their gaps.
export const SPLITS_CHROME = STICKER_PAD * 2 + LABEL.lineHeight + SPLIT_HEADING_GAP + SPLIT_BRAND_GAP + BRAND_MARK;

/// Rows one column holds inside SPLITS_STICKER_BUDGET.
export function splitsCapacity(): number {
	return splitsColumnCapacity(SPLIT_ROW_TEXT, SPLIT_ROW_H, SPLITS_CHROME);
}

export function splitsForm(rows: number): SplitsStickerForm {
	return splitsStickerForm(rows, splitsCapacity());
}

export function bodyContentWidth(body: StickerBody): number {
	return body.kind === 'stats' ? stickerContentWidth(body.layout) : OCCASION_CONTENT_WIDTH;
}

function centredLine(text: string, font: FontSpec, ink: InkRole, width: number, lineHeight: number, measure: MeasureText): Laid {
	const scale = Math.min(1, width / Math.max(1, measure(text, font)));
	return {
		ops: [
			{
				kind: 'text',
				text,
				x: width / 2,
				y: (lineHeight * scale) / 2 + font.size * 0.36 * scale,
				font,
				ink,
				scale,
				align: 'center',
			},
		],
		width,
		height: lineHeight * scale,
	};
}

function layoutLines(lines: OccasionLine[], route: number, width: number, measure: MeasureText): Laid {
	const ops: DrawOp[] = [];
	let y = 0;
	lines.forEach((line, i) => {
		if (i > 0) y += OCCASION_LINE_GAP;
		const step = OCCASION_STEPS[line.step];
		const font: FontSpec = { size: step.size, weight: step.weight, letterSpacing: step.letterSpacing };
		const text = line.step === 'label' ? line.text.toUpperCase() : line.text;
		const wrapped = (line.maxLines ?? 1) > 1 ? wrapLines(text, font, width, line.maxLines!, measure) : [text];
		for (const part of wrapped) {
			const laid = centredLine(part, font, line.ink, width, step.lineHeight, measure);
			ops.push(...laid.ops.map((op) => translate(op, 0, y)));
			y += laid.height;
		}
	});
	if (route > 0) {
		if (lines.length > 0) y += 18;
		ops.push({ kind: 'route', x: (width - route) / 2, y, size: route });
		y += route;
	}
	y += 16;
	return { ops, width, height: y };
}

function splitRows(entries: SplitsStickerEntry[], fastest: number, x: number, w: number, measure: MeasureText): DrawOp[] {
	const font: FontSpec = { size: SPLIT_ROW_TEXT, weight: 800, letterSpacing: 0 };
	const labelFont: FontSpec = { size: SPLIT_ROW_TEXT, weight: 700, letterSpacing: 0 };
	return entries.flatMap((e, i) => {
		const baseline = i * SPLIT_ROW_H + SPLIT_ROW_H / 2 + SPLIT_ROW_TEXT * 0.36;
		const hot = i === fastest;
		const paceW = measure(e.pace, font);
		const labelW = measure(e.label, labelFont);
		const scale = Math.min(1, w / Math.max(1, paceW + labelW + 12));
		return [
			{ kind: 'text', text: e.label, x, y: baseline, font: labelFont, ink: hot ? 'accent' : 'muted', scale, align: 'left' },
			{ kind: 'text', text: e.pace, x: x + w, y: baseline, font, ink: hot ? 'accent' : 'text', scale, align: 'right' },
		] satisfies DrawOp[];
	});
}

function splitBars(entries: SplitsStickerEntry[], fastest: number, width: number): DrawOp[] {
	const speeds = entries.map((e) => (e.row.paceSecPerKm > 0 ? 1 / e.row.paceSecPerKm : 0));
	const live = speeds.filter((v) => v > 0);
	const lo = Math.min(...live);
	const hi = Math.max(...live);
	const frac = (v: number) => (hi > lo ? SPLIT_BAR_MIN + ((1 - SPLIT_BAR_MIN) * (v - lo)) / (hi - lo) : 1);
	const gap = entries.length > 60 ? 1 : 2;
	const barW = (width - gap * (entries.length - 1)) / entries.length;
	const ops: DrawOp[] = entries.map((e, i) => {
		const h = speeds[i] > 0 ? SPLIT_BARS_H * frac(speeds[i]) : 0;
		return {
			kind: 'bar',
			x: i * (barW + gap),
			y: SPLIT_BARS_H - h,
			w: barW,
			h,
			ink: i === fastest ? 'accent' : e.row.partial ? 'muted' : 'text',
		};
	});
	const avg = averageStickerPace(entries.map((e) => e.row));
	if (avg != null) {
		const h = SPLIT_BARS_H * frac(1 / avg);
		ops.push({ kind: 'divider', x: 0, y: SPLIT_BARS_H - h - 0.75, w: width, h: 1.5 });
	}
	return ops;
}

function layoutSplits(heading: string, entries: SplitsStickerEntry[], width: number, measure: MeasureText): Laid {
	const ops: DrawOp[] = [];
	const labelFont: FontSpec = { size: LABEL.size, weight: LABEL.weight, letterSpacing: LABEL.letterSpacing };
	const head = centredLine(heading.toUpperCase(), labelFont, 'muted', width, LABEL.lineHeight, measure);
	ops.push(...head.ops);
	let y = LABEL.lineHeight + SPLIT_HEADING_GAP;
	const fastest = fastestStickerSplit(entries.map((e) => e.row));
	const form = splitsForm(entries.length);
	if (form === 'bars') {
		ops.push(...splitBars(entries, fastest, width).map((op) => translate(op, 0, y)));
		y += SPLIT_BARS_H;
	} else if (form === 'single') {
		const x = (width - SPLIT_SINGLE_W) / 2;
		ops.push(...splitRows(entries, fastest, x, SPLIT_SINGLE_W, measure).map((op) => translate(op, 0, y)));
		y += entries.length * SPLIT_ROW_H;
	} else {
		const perColumn = Math.ceil(entries.length / 2);
		const colW = (width - SPLIT_COLUMN_GAP) / 2;
		const left = splitRows(entries.slice(0, perColumn), fastest, 0, colW, measure);
		const right = splitRows(entries.slice(perColumn), fastest - perColumn, colW + SPLIT_COLUMN_GAP, colW, measure);
		ops.push(...[...left, ...right].map((op) => translate(op, 0, y)));
		y += perColumn * SPLIT_ROW_H;
	}
	y += SPLIT_BRAND_GAP;
	return { ops, width, height: y };
}

/// The route's size on an occasion sticker that carries one, and on the
/// route-only sticker.
export const OCCASION_ROUTE = 110;
export const ROUTE_STICKER = OCCASION_CONTENT_WIDTH * 0.82;

/// A personal record: what it is, the bracket in the accent, the time, and how
/// much it beat the old one by.
export function prStickerBody(
	t: { headline: string; distance: string; time: string; improvement: string | null },
	hasRoute: boolean,
): StickerBody {
	const lines: OccasionLine[] = [
		{ text: t.headline, step: 'label', ink: 'muted' },
		{ text: t.distance, step: 'headline', ink: 'accent' },
		{ text: t.time, step: 'display', ink: 'text' },
	];
	if (t.improvement) lines.push({ text: t.improvement, step: 'title', ink: 'text' });
	return { kind: 'lines', lines, route: hasRoute ? OCCASION_ROUTE : 0 };
}

/// A day of a streak: the day count huge, between what it is and what it means.
export function streakStickerBody(t: { kicker: string; days: string; caption: string }): StickerBody {
	return {
		kind: 'lines',
		lines: [
			{ text: t.kicker, step: 'label', ink: 'muted' },
			{ text: t.days, step: 'hero', ink: 'text' },
			{ text: t.caption, step: 'title', ink: 'accent' },
		],
		route: 0,
	};
}

/// A race finish: with an official time, the time is the hero under the race;
/// without one, the word Finisher is.
export function raceStickerBody(t: { name: string; finisher: string; time: string | null }, hasRoute: boolean): StickerBody {
	const lines: OccasionLine[] = t.time
		? [
				{ text: t.finisher, step: 'label', ink: 'muted' },
				{ text: t.name, step: 'headline', ink: 'text', maxLines: 2 },
				{ text: t.time, step: 'display', ink: 'accent' },
			]
		: [
				{ text: t.name, step: 'headline', ink: 'text', maxLines: 2 },
				{ text: t.finisher, step: 'display', ink: 'accent' },
			];
	return { kind: 'lines', lines, route: hasRoute ? OCCASION_ROUTE : 0 };
}

/// A badge the run earned: its name, and its tier in the accent.
export function badgeStickerBody(t: { kicker: string; name: string; tier: string }): StickerBody {
	return {
		kind: 'lines',
		lines: [
			{ text: t.kicker, step: 'label', ink: 'muted' },
			{ text: t.name, step: 'headline', ink: 'text', maxLines: 2 },
			{ text: t.tier, step: 'label', ink: 'accent' },
		],
		route: 0,
	};
}

export function routeStickerBody(): StickerBody {
	return { kind: 'lines', lines: [], route: ROUTE_STICKER };
}

/// A body's content with its signature, `bodyContentWidth(body)` wide and as
/// tall as it draws, with no ground of its own.
export function layoutBodyContent(body: StickerBody, wordmark: string | null, measure: MeasureText): Laid {
	if (body.kind === 'stats') return layoutStickerContent(body.layout, body.stats, body.hasRoute, wordmark, measure);
	const width = OCCASION_CONTENT_WIDTH;
	const laid =
		body.kind === 'lines' ? layoutLines(body.lines, body.route, width, measure) : layoutSplits(body.heading, body.entries, width, measure);
	if (wordmark === null) return laid;
	const b = brand(width, wordmark, measure);
	return { ops: [...laid.ops, ...b.ops.map((op) => translate(op, 0, laid.height))], width, height: laid.height + b.height };
}

/// The sticker's whole canvas: its content inset by STICKER_PAD on every side.
export function layoutSticker(body: StickerBody, wordmark: string | null, measure: MeasureText): Laid {
	const content = layoutBodyContent(body, wordmark, measure);
	return {
		ops: content.ops.map((op) => translate(op, STICKER_PAD, STICKER_PAD)),
		width: content.width + STICKER_PAD * 2,
		height: content.height + STICKER_PAD * 2,
	};
}

const TITLE = { size: STEP.titleLarge, weight: 800, letterSpacing: 0, lineHeight: 28 };

/// `text` broken into at most `maxLines` lines no wider than `width`, the last
/// one ellipsised when the text runs on.
export function wrapLines(text: string, font: FontSpec, width: number, maxLines: number, measure: MeasureText): string[] {
	const words = text.trim().split(/\s+/).filter(Boolean);
	const lines: string[] = [];
	let line = '';
	for (const word of words) {
		const next = line ? `${line} ${word}` : word;
		if (line && measure(next, font) > width) {
			lines.push(line);
			line = word;
		} else {
			line = next;
		}
	}
	if (line) lines.push(line);
	if (lines.length <= maxLines && lines.every((l) => measure(l, font) <= width)) return lines;
	const kept = lines.slice(0, maxLines);
	let last = kept[kept.length - 1];
	const runsOn = lines.length > maxLines;
	if (runsOn || measure(last, font) > width) {
		while (last.length > 0 && measure(`${last}…`, font) > width) last = last.slice(0, -1).trimEnd();
		kept[kept.length - 1] = `${last}…`;
	}
	return kept;
}

export interface PhotoLaid extends Laid {
	/// The scale the sticker content was fitted at: under 1 when a tall layout
	/// on a 4:5 post has to shrink into the height the title leaves.
	contentScale: number;
	/// The title-and-stats block at scale 1, before it is placed.
	blockWidth: number;
	blockHeight: number;
	/// The part of the canvas the block must stay inside.
	frame: PlacementRect;
	/// The smallest scale the block may take (`minSharePlacementScale`).
	minScale: number;
	/// Where the block landed.
	block: PlacedShareBlock;
}

/// The photo style's canvas: the title over the layout's content, as one
/// block the runner can move and resize. It is laid out at the frame's width,
/// fitted into the height the frame leaves, and then placed by `placement`:
/// by default centred on the frame's bottom edge, which on a story keeps it
/// clear of the bottom eighth the story viewer's reply bar covers.
export function layoutPhoto(
	aspect: RunPhotoAspect,
	body: StickerBody,
	title: string,
	wordmark: string | null,
	measure: MeasureText,
	placement: SharePlacement = DEFAULT_SHARE_PLACEMENT,
): PhotoLaid {
	const { w, h } = photoCanvasSize(aspect);
	const frame = sharePlacementFrame(w, h, aspect === 'story');
	const boxW = frame.width;

	const titleFont: FontSpec = { size: TITLE.size, weight: TITLE.weight, letterSpacing: 0 };
	const lines = title.trim() ? wrapLines(title, titleFont, boxW, 2, measure) : [];
	const titleH = lines.length * TITLE.lineHeight;
	const titleGap = lines.length > 0 ? 12 : 0;

	const content = layoutBodyContent(body, wordmark, measure);
	const availH = frame.height - titleH - titleGap;
	const contentScale = Math.min(1, boxW / content.width, availH / content.height);
	const cw = content.width * contentScale;
	const ch = content.height * contentScale;
	const blockHeight = titleH + titleGap + ch;
	const minScale = minSharePlacementScale(LABEL.size * contentScale);
	const block = placeShareBlock(placement, boxW, blockHeight, w, h, frame, minScale);
	const k = block.scale;
	const cx = block.left + ((boxW - cw) / 2) * k;
	const cy = block.top + (titleH + titleGap) * k;
	const ks = contentScale * k;

	const ops: DrawOp[] = lines.map((text, i) => ({
		kind: 'text',
		text,
		x: block.left + (boxW / 2) * k,
		y: block.top + (i * TITLE.lineHeight + TITLE.lineHeight / 2 + TITLE.size * 0.36) * k,
		font: titleFont,
		ink: 'text',
		scale: k,
		align: 'center',
	}));
	for (const op of content.ops) {
		const scaled: DrawOp =
			op.kind === 'text'
				? { ...op, x: cx + op.x * ks, y: cy + op.y * ks, scale: op.scale * ks }
				: op.kind === 'divider' || op.kind === 'bar'
					? { ...op, x: cx + op.x * ks, y: cy + op.y * ks, w: op.w * ks, h: op.h * ks }
					: { ...op, x: cx + op.x * ks, y: cy + op.y * ks, size: op.size * ks };
		ops.push(scaled);
	}
	return { ops, width: w, height: h, contentScale, blockWidth: boxW, blockHeight, frame, minScale, block };
}

// ---------------------------------------------------------------------------
// Painting. Everything below runs against a real CanvasRenderingContext2D.

function cssFont(font: FontSpec): string {
	return `${font.weight} ${font.size}px ${SHARE_FONT_STACK}`;
}

/// A MeasureText reading the canvas's own metrics, so layout and paint agree.
export function canvasMeasure(ctx: CanvasRenderingContext2D): MeasureText {
	return (text, font) => {
		ctx.font = cssFont(font);
		ctx.letterSpacing = `${font.letterSpacing}px`;
		return ctx.measureText(text).width;
	};
}

/// Waits for the product face at the weights the images use, so the first
/// export is not drawn in the fallback face. A failed load draws the fallback.
export async function loadShareFonts(): Promise<void> {
	if (typeof document === 'undefined' || !document.fonts) return;
	try {
		await Promise.all([400, 700, 800].map((wt) => document.fonts.load(`${wt} 28px Manrope`)));
	} catch (e) {
		console.warn('share fonts not loaded; drawing the fallback face', e);
	}
}

// logo-mark.svg's glyph, drawn at scale 7.6 about (54.5, 50) on a 1024 tile
// rounded at 180, the corner wordmark.svg gives it.
const MARK_GLYPH = 'M30 10 H44 V90 H30 Z M44 29 H58 A21 21 0 0 1 58 71 H44 Z M44 42 H56 A8 8 0 0 1 56 58 H44 Z';

export function paintMark(ctx: CanvasRenderingContext2D, x: number, y: number, size: number) {
	ctx.save();
	ctx.translate(x, y);
	ctx.scale(size / 1024, size / 1024);
	const g = ctx.createLinearGradient(0, 0, 1024, 1024);
	g.addColorStop(0, THREKIR_MARK_GRADIENT[0]);
	g.addColorStop(0.5, THREKIR_MARK_GRADIENT[1]);
	g.addColorStop(1, THREKIR_MARK_GRADIENT[2]);
	ctx.fillStyle = g;
	ctx.beginPath();
	ctx.roundRect(0, 0, 1024, 1024, 180);
	ctx.fill();
	ctx.translate(512, 512);
	ctx.scale(7.6, 7.6);
	ctx.translate(-54.5, -50);
	ctx.fillStyle = SHARE_STICKER_INKS.light.text;
	ctx.fill(new Path2D(MARK_GLYPH), 'evenodd');
	ctx.restore();
}

function paintRoute(
	ctx: CanvasRenderingContext2D,
	track: TrackPoint[],
	op: { x: number; y: number; size: number },
	ink: (typeof SHARE_STICKER_INKS)[RunShareInk],
	pxPerUnit: number,
) {
	const stroke = Math.min(7, Math.max(2.5, op.size * 0.032));
	const pts = projectTrack(track, op.size, op.size, stroke * 2);
	if (pts.length < 2) return;
	ctx.save();
	ctx.translate(op.x, op.y);
	const path = new Path2D();
	path.moveTo(pts[0].x, pts[0].y);
	for (const p of pts.slice(1)) path.lineTo(p.x, p.y);
	ctx.lineCap = 'round';
	ctx.lineJoin = 'round';
	// The halo is a blurred casing under the line. `ctx.filter` is missing from
	// Safari, so the casing is stroked a canvas-width off to the left and only
	// its shadow, offset back into place, lands in the image.
	const away = 4 * SHARE_EXPORT_WIDTH_PX;
	ctx.save();
	ctx.translate(-away / pxPerUnit, 0);
	// Opaque, because a shadow takes its alpha from the shape that casts it.
	ctx.strokeStyle = 'black';
	ctx.lineWidth = stroke * 2.4;
	ctx.shadowColor = ink.halo;
	ctx.shadowBlur = stroke * 2 * pxPerUnit;
	ctx.shadowOffsetX = away;
	ctx.stroke(path);
	ctx.restore();
	ctx.strokeStyle = ink.text;
	ctx.lineWidth = stroke;
	ctx.stroke(path);
	const end = pts[pts.length - 1];
	ctx.fillStyle = ink.text;
	ctx.beginPath();
	ctx.arc(end.x, end.y, stroke * 1.3, 0, Math.PI * 2);
	ctx.fill();
	ctx.restore();
}

export function paintOps(
	ctx: CanvasRenderingContext2D,
	ops: DrawOp[],
	track: TrackPoint[],
	inkName: RunShareInk,
	pxPerUnit: number,
) {
	const ink = SHARE_STICKER_INKS[inkName];
	for (const op of ops) {
		switch (op.kind) {
			case 'text': {
				ctx.save();
				ctx.translate(op.x, op.y);
				ctx.scale(op.scale, op.scale);
				ctx.font = cssFont(op.font);
				ctx.letterSpacing = `${op.font.letterSpacing}px`;
				ctx.textAlign = op.align;
				ctx.textBaseline = 'alphabetic';
				ctx.fillStyle = ink[op.ink];
				// Shadow geometry is in device pixels, outside the transform.
				ctx.shadowColor = ink.shadow;
				ctx.shadowBlur = 10 * pxPerUnit * op.scale;
				ctx.shadowOffsetY = pxPerUnit * op.scale;
				ctx.fillText(op.text, 0, 0);
				ctx.restore();
				break;
			}
			case 'route':
				paintRoute(ctx, track, op, ink, pxPerUnit);
				break;
			case 'divider':
				ctx.fillStyle = ink.muted;
				ctx.fillRect(op.x, op.y, op.w, op.h);
				break;
			case 'bar':
				if (op.h <= 0) break;
				ctx.save();
				ctx.shadowColor = ink.shadow;
				ctx.shadowBlur = 6 * pxPerUnit;
				ctx.fillStyle = ink[op.ink];
				ctx.beginPath();
				ctx.roundRect(op.x, op.y, op.w, op.h, Math.min(op.w / 2, 3));
				ctx.fill();
				ctx.restore();
				break;
			case 'mark':
				paintMark(ctx, op.x, op.y, op.size);
				break;
		}
	}
}

/// A canvas `laid.width` logical pixels wide, scaled to SHARE_EXPORT_WIDTH_PX.
export function sizedCanvas(laid: Laid): { canvas: HTMLCanvasElement; ctx: CanvasRenderingContext2D; k: number } {
	const k = SHARE_EXPORT_WIDTH_PX / laid.width;
	const canvas = document.createElement('canvas');
	canvas.width = SHARE_EXPORT_WIDTH_PX;
	canvas.height = Math.round(laid.height * k);
	const ctx = canvas.getContext('2d');
	if (!ctx) throw new Error('2D canvas unavailable');
	ctx.scale(k, k);
	return { canvas, ctx, k };
}

export interface StickerInput {
	body: StickerBody;
	ink: RunShareInk;
	/// The clipped share line (`shareCardTrack`), never a raw track.
	track: TrackPoint[];
	wordmark: string | null;
}

/// The sticker on a transparent ground, cropped to its own content.
export function paintSticker(input: StickerInput): HTMLCanvasElement {
	const probe = document.createElement('canvas').getContext('2d');
	if (!probe) throw new Error('2D canvas unavailable');
	const laid = layoutSticker(input.body, input.wordmark, canvasMeasure(probe));
	const { canvas, ctx, k } = sizedCanvas(laid);
	paintOps(ctx, laid.ops, input.track, input.ink, k);
	return canvas;
}

export interface PhotoInput extends StickerInput {
	aspect: RunPhotoAspect;
	/// Where the title and stats sit; the default when omitted.
	placement?: SharePlacement;
	title: string;
	photo: CanvasImageSource & { width: number; height: number };
}

/// The runner's photo, cropped to fill the aspect, under a scrim and the
/// title, stats, route and signature. Returns the layout with the canvas, so
/// the editor's handles sit on the block exactly where it was drawn.
export function paintPhoto(input: PhotoInput): { canvas: HTMLCanvasElement; laid: PhotoLaid } {
	const probe = document.createElement('canvas').getContext('2d');
	if (!probe) throw new Error('2D canvas unavailable');
	const laid = layoutPhoto(
		input.aspect,
		input.body,
		input.title,
		input.wordmark,
		canvasMeasure(probe),
		input.placement,
	);
	const { canvas, ctx, k } = sizedCanvas(laid);
	const { w, h } = { w: laid.width, h: laid.height };
	const cover = Math.max(w / input.photo.width, h / input.photo.height);
	const pw = input.photo.width * cover;
	const ph = input.photo.height * cover;
	ctx.imageSmoothingQuality = 'high';
	ctx.drawImage(input.photo, (w - pw) / 2, (h - ph) / 2, pw, ph);
	const scrim = SHARE_STICKER_INKS[input.ink].scrim;
	const g = ctx.createLinearGradient(0, 0, 0, h);
	g.addColorStop(0.3, `rgba(${scrim}, 0)`);
	g.addColorStop(1, `rgba(${scrim}, 0.7)`);
	ctx.fillStyle = g;
	ctx.fillRect(0, 0, w, h);
	paintOps(ctx, laid.ops, input.track, input.ink, k);
	return { canvas, laid };
}

export function canvasToPng(canvas: HTMLCanvasElement): Promise<Blob> {
	return new Promise((resolve, reject) => {
		canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('canvas produced no image'))), 'image/png');
	});
}
