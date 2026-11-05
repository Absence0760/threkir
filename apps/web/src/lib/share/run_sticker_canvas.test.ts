import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import {
	RUN_STICKER_LAYOUTS,
} from './share_look';
import type { RunShareStat } from './run_share_stats';
import {
	STICKER_PAD,
	layoutPhoto,
	layoutSticker,
	layoutStickerContent,
	photoCanvasSize,
	stickerContentWidth,
	wrapLines,
	type DrawOp,
	type MeasureText,
} from './run_sticker_canvas';

// A monospace stand-in for the canvas: every glyph is 0.6 of the font size,
// plus its letter spacing.
const measure: MeasureText = (text, font) => text.length * (font.size * 0.6 + font.letterSpacing);

const stat = (kind: RunShareStat['kind'], value: string, unit: string | null = null): RunShareStat => ({
	kind,
	label: kind,
	value,
	unit,
});
const three = [stat('distance', '10.00', 'km'), stat('pace', '5:00', '/km'), stat('time', '50:00')];
const four = [...three, stat('climb', '120', 'm')];

const texts = (ops: DrawOp[]) => ops.flatMap((op) => (op.kind === 'text' ? [op] : []));
const of = <K extends DrawOp['kind']>(ops: DrawOp[], kind: K) =>
	ops.filter((op): op is Extract<DrawOp, { kind: K }> => op.kind === kind);

describe('sticker', () => {
	test('is its own content plus the padding, so the PNG is cropped to what it draws', () => {
		for (const layout of RUN_STICKER_LAYOUTS) {
			const content = layoutStickerContent(layout, three, true, 'Threkir', measure);
			const sticker = layoutSticker(layout, three, true, 'Threkir', measure);
			assert.equal(sticker.width, stickerContentWidth(layout) + STICKER_PAD * 2, layout);
			assert.equal(sticker.height, content.height + STICKER_PAD * 2, layout);
			for (const op of sticker.ops) {
				assert.ok(op.y >= STICKER_PAD - 1e-9 && op.y <= sticker.height - STICKER_PAD + 1e-9, `${layout} ${op.kind} at ${op.y}`);
			}
		}
	});

	test('the strip is laid out wide and every other layout portrait', () => {
		assert.equal(stickerContentWidth('strip'), 560);
		for (const layout of ['stack', 'route', 'hero'] as const) assert.equal(stickerContentWidth(layout), 320);
	});

	test('every layout is signed with the Threkir mark and wordmark', () => {
		for (const layout of RUN_STICKER_LAYOUTS) {
			const { ops } = layoutStickerContent(layout, three, false, 'Threkir', measure);
			assert.equal(of(ops, 'mark').length, 1, layout);
			assert.ok(texts(ops).some((t) => t.text === 'THREKIR'), layout);
		}
	});

	test('with the mark turned off no layout draws a signature', () => {
		for (const layout of RUN_STICKER_LAYOUTS) {
			const signed = layoutStickerContent(layout, three, false, 'Threkir', measure);
			const bare = layoutStickerContent(layout, three, false, null, measure);
			assert.equal(of(bare.ops, 'mark').length, 0, layout);
			assert.ok(!texts(bare.ops).some((t) => t.text === 'THREKIR'), layout);
			assert.ok(bare.height < signed.height, layout);
		}
	});

	test('the route is drawn only when there is a clipped line to draw', () => {
		assert.equal(of(layoutStickerContent('stack', three, false, 'T', measure).ops, 'route').length, 0);
		assert.equal(of(layoutStickerContent('stack', three, true, 'T', measure).ops, 'route')[0].size, 150);
		assert.equal(of(layoutStickerContent('route', three, true, 'T', measure).ops, 'route')[0].size, 320 * 0.82);
	});

	test('each stat prints its label, value and unit once', () => {
		for (const layout of RUN_STICKER_LAYOUTS) {
			const t = texts(layoutStickerContent(layout, four, true, 'T', measure).ops).map((op) => op.text);
			for (const s of four) {
				assert.equal(t.filter((x) => x === s.value).length, 1, `${layout} ${s.value}`);
				assert.equal(t.filter((x) => x === s.kind.toUpperCase()).length, 1, `${layout} ${s.kind}`);
			}
		}
	});

	test('the strip separates its stats with a divider between each pair', () => {
		assert.equal(of(layoutStickerContent('strip', four, false, 'T', measure).ops, 'divider').length, 3);
		assert.equal(of(layoutStickerContent('stack', four, false, 'T', measure).ops, 'divider').length, 0);
	});

	test('the hero prints its first stat larger than the rest', () => {
		const values = texts(layoutStickerContent('hero', three, false, 'T', measure).ops).filter((op) =>
			three.some((s) => s.value === op.text),
		);
		const [first, ...rest] = values;
		for (const op of rest) assert.ok(first.font.size > op.font.size);
	});

	test('a long value scales down to its column rather than overflowing it', () => {
		const long = [stat('distance', '1234567890.00', 'km'), stat('pace', '5:00', '/km')];
		const { ops, width } = layoutStickerContent('route', long, false, 'T', measure);
		const value = texts(ops).find((op) => op.text === long[0].value);
		const unit = texts(ops).find((op) => op.text === 'km');
		assert.ok(value && unit && value.scale < 1);
		const right = unit.x + measure('km', unit.font) * unit.scale;
		assert.ok(right <= (width - 12) / 2 + 1e-6, `ends at ${right}`);
	});
});

describe('photo', () => {
	test('is cut to a 4:5 post or a 9:16 story at 360 logical px across', () => {
		assert.deepEqual(photoCanvasSize('post'), { w: 360, h: 450 });
		assert.deepEqual(photoCanvasSize('story'), { w: 360, h: 640 });
	});

	test('keeps the stats clear of the story viewer reply bar', () => {
		const laid = layoutPhoto('story', 'stack', 'Morning run', three, true, 'T', measure);
		const lowest = Math.max(...laid.ops.map((op) => op.y + (op.kind === 'route' || op.kind === 'mark' ? op.size : 0)));
		assert.ok(lowest <= 640 * 0.87 + 1e-6, `lowest at ${lowest}`);
	});

	test('fits a wide strip into the photo width', () => {
		const laid = layoutPhoto('post', 'strip', 'Morning run', four, false, 'T', measure);
		assert.ok(laid.contentScale <= 320 / 560 + 1e-9);
		for (const op of laid.ops) assert.ok(op.x >= 20 - 1e-6, `${op.kind} at ${op.x}`);
	});

	test('a tall layout on a post shrinks into the height the title leaves', () => {
		const laid = layoutPhoto('post', 'stack', 'A title', four, true, 'T', measure);
		assert.ok(laid.contentScale < 1);
		const title = texts(laid.ops).find((op) => op.text === 'A title');
		assert.ok(title && title.y >= 20);
	});

	test('the default placement sits the block on the frame bottom, centred', () => {
		const laid = layoutPhoto('story', 'stack', 'Morning run', three, true, 'T', measure);
		assert.equal(laid.block.scale, 1);
		assert.equal(laid.block.left, 20);
		assert.ok(Math.abs(laid.block.top + laid.block.height - 640 * 0.87) < 1e-9);
	});

	test('a placement moves and scales every op with the block, never into the reply bar', () => {
		const base = layoutPhoto('story', 'stack', 'Morning run', three, true, 'T', measure, { x: 0.5, y: 0.5, scale: 1 });
		const small = layoutPhoto('story', 'stack', 'Morning run', three, true, 'T', measure, { x: 0.5, y: 0.5, scale: 0.5 });
		const title = (l: typeof base) => texts(l.ops).find((op) => op.text === 'Morning run');
		assert.equal(title(small)?.scale, 0.5);
		const label = (l: typeof base) => texts(l.ops).find((op) => op.text === 'DISTANCE');
		assert.equal(label(small)!.scale, label(base)!.scale * 0.5);
		for (const y of [0, 1]) {
			const laid = layoutPhoto('story', 'hero', 'Morning run', three, false, 'T', measure, { x: 0, y, scale: 0.6 });
			for (const op of laid.ops) {
				assert.ok(op.x >= 20 - 1e-6 && op.y >= 20 - 1e-6, `${op.kind} at ${op.x},${op.y}`);
				assert.ok(op.y <= 640 * 0.87 + 1e-6, `${op.kind} at ${op.y}`);
			}
		}
	});

	test('the strip layout cannot shrink its labels under the 6 px floor', () => {
		const laid = layoutPhoto('story', 'strip', 'Morning run', three, false, 'T', measure, { x: 0.5, y: 0.5, scale: 0.5 });
		const label = texts(laid.ops).find((op) => op.text === 'DISTANCE');
		assert.ok(label && 12 * label.scale >= 6 - 1e-9, `label at ${12 * (label?.scale ?? 0)} px`);
	});

	test('an untitled run prints no title line', () => {
		const titled = layoutPhoto('story', 'hero', 'Run', three, false, 'T', measure);
		const untitled = layoutPhoto('story', 'hero', '  ', three, false, 'T', measure);
		assert.equal(texts(untitled.ops).length, texts(titled.ops).length - 1);
	});
});

describe('wrapLines', () => {
	const font = { size: 10, weight: 800, letterSpacing: 0 };

	test('keeps a short title on one line', () => {
		assert.deepEqual(wrapLines('Easy run', font, 100, 2, measure), ['Easy run']);
	});

	test('breaks on words and ellipsises a title that runs past two lines', () => {
		const lines = wrapLines('one two three four five six seven eight', font, 60, 2, measure);
		assert.equal(lines.length, 2);
		assert.ok(lines[1].endsWith('…'));
		for (const l of lines) assert.ok(measure(l, font) <= 60);
	});

	test('cuts a single word wider than the line', () => {
		const [line] = wrapLines('Supercalifragilistic', font, 60, 2, measure);
		assert.ok(line.endsWith('…') && measure(line, font) <= 60);
	});
});
