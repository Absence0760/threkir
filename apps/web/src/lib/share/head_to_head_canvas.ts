// The head-to-head share card: "Me vs @friend" on one route or segment, with
// both times, who won and by how much, and the Threkir mark. Twin of
// `HeadToHeadCard` in apps/mobile_android/lib/widgets/head_to_head_card.dart:
// the same 360 x 450 logical canvas, rasterised 1080 px across.
//
// The card draws no line and no map, so it reads no track and owes no tile
// credit; the mark is its only attribution (decisions § 2267). Layout is a pure
// function over a text-measuring callback, unit tested without a canvas.

import { OG_CARD_DARK } from './og_card_palette';
import {
	SHARE_EXPORT_WIDTH_PX,
	SHARE_FONT_STACK,
	paintMark,
	wrapLines,
	type FontSpec,
	type MeasureText,
} from './run_sticker_canvas';
import { formatHeadToHeadTime, headToHeadOutcome, type HeadToHeadRow } from '../social/head_to_head';

export const HEAD_TO_HEAD_CANVAS = { w: 360, h: 450 } as const;

const PAD = 28;
const KICKER: FontSpec = { size: 12, weight: 700, letterSpacing: 1.6 };
const TITLE: FontSpec = { size: 22, weight: 800, letterSpacing: 0 };
const TITLE_LINE = 28;
const NAME: FontSpec = { size: 14, weight: 700, letterSpacing: 0 };
const TIME: FontSpec = { size: 36, weight: 800, letterSpacing: -0.5 };
const VS: FontSpec = { size: 14, weight: 800, letterSpacing: 2.6 };
const OUTCOME: FontSpec = { size: 20, weight: 800, letterSpacing: 0 };
const BRAND: FontSpec = { size: 14, weight: 800, letterSpacing: 2.6 };
const BRAND_MARK = 18;
const VS_GAP = 44;

export type HeadToHeadInk = 'hero' | 'label' | 'stat' | 'brand';

export type HeadToHeadOp =
	| {
			kind: 'text';
			text: string;
			x: number;
			y: number;
			font: FontSpec;
			ink: HeadToHeadInk;
			scale: number;
			align: 'left' | 'center' | 'right';
	  }
	| { kind: 'mark'; x: number; y: number; size: number };

export interface HeadToHeadCardInput {
	targetName: string;
	myName: string;
	friendName: string;
	mySeconds: number;
	friendSeconds: number;
	/// Localised strings the card prints, already resolved by the caller.
	kicker: string;
	vs: string;
	/// The outcome line, e.g. "I won by 0:50", "@sam won by 0:50", "Dead heat".
	outcome: (winner: 'me' | 'friend' | 'tie', margin: string) => string;
	wordmark: string;
}

function fit(text: string, font: FontSpec, width: number, measure: MeasureText): number {
	return Math.min(1, width / Math.max(1, measure(text, font)));
}

/// Every op the card draws, in logical pixels on HEAD_TO_HEAD_CANVAS.
export function layoutHeadToHead(input: HeadToHeadCardInput, measure: MeasureText): HeadToHeadOp[] {
	const { w, h } = HEAD_TO_HEAD_CANVAS;
	const inner = w - PAD * 2;
	const ops: HeadToHeadOp[] = [];
	const text = (
		t: string,
		x: number,
		y: number,
		font: FontSpec,
		ink: HeadToHeadInk,
		align: 'left' | 'center' | 'right',
		width: number,
	) => ops.push({ kind: 'text', text: t, x, y, font, ink, scale: fit(t, font, width, measure), align });

	text(input.kicker.toUpperCase(), PAD, 52, KICKER, 'label', 'left', inner);
	wrapLines(input.targetName, TITLE, inner, 2, measure).forEach((line, i) =>
		text(line, PAD, 86 + i * TITLE_LINE, TITLE, 'hero', 'left', inner),
	);

	const outcome = headToHeadOutcome(input.mySeconds, input.friendSeconds);
	const col = (inner - VS_GAP) / 2;
	const left = PAD + col / 2;
	const right = w - PAD - col / 2;
	text(input.myName, left, 196, NAME, 'label', 'center', col);
	text(input.friendName, right, 196, NAME, 'label', 'center', col);
	text(input.vs.toUpperCase(), w / 2, 238, VS, 'label', 'center', VS_GAP);
	text(formatHeadToHeadTime(input.mySeconds), left, 250, TIME, outcome.winner === 'me' ? 'brand' : 'stat', 'center', col);
	text(
		formatHeadToHeadTime(input.friendSeconds),
		right,
		250,
		TIME,
		outcome.winner === 'friend' ? 'brand' : 'stat',
		'center',
		col,
	);
	text(input.outcome(outcome.winner, formatHeadToHeadTime(outcome.marginSeconds)), w / 2, 332, OUTCOME, 'hero', 'center', inner);

	const word = input.wordmark.toUpperCase();
	const gap = BRAND_MARK * 0.45;
	const total = BRAND_MARK + gap + measure(word, BRAND);
	const bx = (w - total) / 2;
	const by = h - PAD - BRAND_MARK;
	ops.push({ kind: 'mark', x: bx, y: by, size: BRAND_MARK });
	ops.push({
		kind: 'text',
		text: word,
		x: bx + BRAND_MARK + gap,
		y: by + BRAND_MARK / 2 + BRAND.size * 0.36,
		font: BRAND,
		ink: 'hero',
		scale: 1,
		align: 'left',
	});
	return ops;
}

function cssFont(font: FontSpec): string {
	return `${font.weight} ${font.size}px ${SHARE_FONT_STACK}`;
}

const INKS: Record<HeadToHeadInk, string> = {
	hero: OG_CARD_DARK.hero,
	label: OG_CARD_DARK.label,
	stat: OG_CARD_DARK.stat,
	brand: OG_CARD_DARK.brand,
};

/// The card on its dark ground, SHARE_EXPORT_WIDTH_PX across.
/// What the painted card depends on. A reload that brings the same friend
/// back with a new best time must repaint, so the friend alone is not a key.
export function headToHeadPreviewKey(r: HeadToHeadRow): string {
	return JSON.stringify([r.friendId, r.mySeconds, r.friendSeconds, r.targetName, r.friendHandle, r.friendDisplayName]);
}

export function paintHeadToHead(input: HeadToHeadCardInput): HTMLCanvasElement {
	const { w, h } = HEAD_TO_HEAD_CANVAS;
	const k = SHARE_EXPORT_WIDTH_PX / w;
	const canvas = document.createElement('canvas');
	canvas.width = SHARE_EXPORT_WIDTH_PX;
	canvas.height = Math.round(h * k);
	const ctx = canvas.getContext('2d');
	if (!ctx) throw new Error('2D canvas unavailable');
	ctx.scale(k, k);
	ctx.fillStyle = OG_CARD_DARK.bg;
	ctx.fillRect(0, 0, w, h);
	const measure: MeasureText = (t, font) => {
		ctx.font = cssFont(font);
		ctx.letterSpacing = `${font.letterSpacing}px`;
		return ctx.measureText(t).width;
	};
	for (const op of layoutHeadToHead(input, measure)) {
		if (op.kind === 'mark') {
			paintMark(ctx, op.x, op.y, op.size);
			continue;
		}
		ctx.save();
		ctx.translate(op.x, op.y);
		ctx.scale(op.scale, op.scale);
		ctx.font = cssFont(op.font);
		ctx.letterSpacing = `${op.font.letterSpacing}px`;
		ctx.textAlign = op.align;
		ctx.textBaseline = 'alphabetic';
		ctx.fillStyle = INKS[op.ink];
		ctx.fillText(op.text, 0, 0);
		ctx.restore();
	}
	return canvas;
}
