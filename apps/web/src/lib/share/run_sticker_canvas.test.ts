import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import {
	RUN_STICKER_LAYOUTS,
	SPLITS_STICKER_BUDGET,
	splitsStickerMaxHeight,
	type RunStickerLayout,
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
	OCCASION_CONTENT_WIDTH,
	SPLIT_ROW_TEXT,
	badgeStickerBody,
	layoutBodyContent,
	prStickerBody,
	raceStickerBody,
	routeStickerBody,
	splitsCapacity,
	splitsForm,
	streakStickerBody,
	type DrawOp,
	type SplitsStickerEntry,
	type StickerBody,
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

const statsBody = (layout: RunStickerLayout, stats: RunShareStat[], hasRoute: boolean): StickerBody => ({
	kind: 'stats',
	layout,
	stats,
	hasRoute,
});

const texts = (ops: DrawOp[]) => ops.flatMap((op) => (op.kind === 'text' ? [op] : []));
const of = <K extends DrawOp['kind']>(ops: DrawOp[], kind: K) =>
	ops.filter((op): op is Extract<DrawOp, { kind: K }> => op.kind === kind);

describe('sticker', () => {
	test('is its own content plus the padding, so the PNG is cropped to what it draws', () => {
		for (const layout of RUN_STICKER_LAYOUTS) {
			const content = layoutStickerContent(layout, three, true, 'Threkir', measure);
			const sticker = layoutSticker(statsBody(layout, three, true), 'Threkir', measure);
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
		const laid = layoutPhoto('story', statsBody('stack', three, true), 'Morning run', 'T', measure);
		const lowest = Math.max(...laid.ops.map((op) => op.y + (op.kind === 'route' || op.kind === 'mark' ? op.size : 0)));
		assert.ok(lowest <= 640 * 0.87 + 1e-6, `lowest at ${lowest}`);
	});

	test('fits a wide strip into the photo width', () => {
		const laid = layoutPhoto('post', statsBody('strip', four, false), 'Morning run', 'T', measure);
		assert.ok(laid.contentScale <= 320 / 560 + 1e-9);
		for (const op of laid.ops) assert.ok(op.x >= 20 - 1e-6, `${op.kind} at ${op.x}`);
	});

	test('a tall layout on a post shrinks into the height the title leaves', () => {
		const laid = layoutPhoto('post', statsBody('stack', four, true), 'A title', 'T', measure);
		assert.ok(laid.contentScale < 1);
		const title = texts(laid.ops).find((op) => op.text === 'A title');
		assert.ok(title && title.y >= 20);
	});

	test('the default placement sits the block on the frame bottom, centred', () => {
		const laid = layoutPhoto('story', statsBody('stack', three, true), 'Morning run', 'T', measure);
		assert.equal(laid.block.scale, 1);
		assert.equal(laid.block.left, 20);
		assert.ok(Math.abs(laid.block.top + laid.block.height - 640 * 0.87) < 1e-9);
	});

	test('a placement moves and scales every op with the block, never into the reply bar', () => {
		const base = layoutPhoto('story', statsBody('stack', three, true), 'Morning run', 'T', measure, { x: 0.5, y: 0.5, scale: 1 });
		const small = layoutPhoto('story', statsBody('stack', three, true), 'Morning run', 'T', measure, { x: 0.5, y: 0.5, scale: 0.5 });
		const title = (l: typeof base) => texts(l.ops).find((op) => op.text === 'Morning run');
		assert.equal(title(small)?.scale, 0.5);
		const label = (l: typeof base) => texts(l.ops).find((op) => op.text === 'DISTANCE');
		assert.equal(label(small)!.scale, label(base)!.scale * 0.5);
		for (const y of [0, 1]) {
			const laid = layoutPhoto('story', statsBody('hero', three, false), 'Morning run', 'T', measure, { x: 0, y, scale: 0.6 });
			for (const op of laid.ops) {
				assert.ok(op.x >= 20 - 1e-6 && op.y >= 20 - 1e-6, `${op.kind} at ${op.x},${op.y}`);
				assert.ok(op.y <= 640 * 0.87 + 1e-6, `${op.kind} at ${op.y}`);
			}
		}
	});

	test('the strip layout cannot shrink its labels under the 6 px floor', () => {
		const laid = layoutPhoto('story', statsBody('strip', three, false), 'Morning run', 'T', measure, { x: 0.5, y: 0.5, scale: 0.5 });
		const label = texts(laid.ops).find((op) => op.text === 'DISTANCE');
		assert.ok(label && 12 * label.scale >= 6 - 1e-9, `label at ${12 * (label?.scale ?? 0)} px`);
	});

	test('an untitled run prints no title line', () => {
		const titled = layoutPhoto('story', statsBody('hero', three, false), 'Run', 'T', measure);
		const untitled = layoutPhoto('story', statsBody('hero', three, false), '  ', 'T', measure);
		assert.equal(texts(untitled.ops).length, texts(titled.ops).length - 1);
	});
});

const splitEntries = (n: number, partialTail = false): SplitsStickerEntry[] =>
	Array.from({ length: n }, (_, i) => {
		const partial = partialTail && i === n - 1;
		const pace = 300 + ((i * 7) % 23);
		return { label: partial ? '0.2 km' : String(i + 1), pace: `${Math.floor(pace / 60)}:${String(pace % 60).padStart(2, '0')}`, row: { paceSecPerKm: partial ? 250 : pace, metres: partial ? 200 : 1000, partial } };
	});
const splitsBody = (n: number, partialTail = false): StickerBody => ({ kind: 'splits', heading: `${n} splits`, entries: splitEntries(n, partialTail) });

const occasions: Record<string, StickerBody> = {
	splits: splitsBody(5),
	pr: prStickerBody({ headline: 'New personal record', distance: '5K', time: '22:41', improvement: '18s faster' }, true),
	streak: streakStickerBody({ kicker: 'Run streak', days: '147', caption: 'days in a row' }),
	raceTimed: raceStickerBody({ name: 'Richmond Marathon', finisher: 'Finisher', time: '3:41:07' }, true),
	raceUntimed: raceStickerBody({ name: 'Richmond Marathon', finisher: 'Finisher', time: null }, false),
	badge: badgeStickerBody({ kicker: 'Badge earned', name: 'Marathon finisher', tier: 'Gold' }),
	route: routeStickerBody(),
};

describe('occasion stickers', () => {
	test('every kind lays out inside its width, signed, and cropped to its padding', () => {
		for (const [name, body] of Object.entries(occasions)) {
			const sticker = layoutSticker(body, 'Threkir', measure);
			assert.equal(sticker.width, OCCASION_CONTENT_WIDTH + STICKER_PAD * 2, name);
			assert.equal(of(layoutBodyContent(body, 'Threkir', measure).ops, 'mark').length, 1, name);
			assert.equal(of(layoutBodyContent(body, null, measure).ops, 'mark').length, 0, name);
			for (const op of texts(sticker.ops)) {
				const w = measure(op.text, op.font) * op.scale;
				const left = op.align === 'center' ? op.x - w / 2 : op.align === 'right' ? op.x - w : op.x;
				assert.ok(left >= STICKER_PAD - 1e-6 && left + w <= sticker.width - STICKER_PAD + 1e-6, `${name}: "${op.text}" overflows`);
			}
			for (const op of sticker.ops) assert.ok(op.y >= STICKER_PAD - 1e-9 && op.y <= sticker.height - STICKER_PAD + 1e-9, `${name} ${op.kind}`);
		}
	});

	test('the race sticker heroes the official time when there is one, the word Finisher otherwise', () => {
		const timed = texts(layoutBodyContent(occasions.raceTimed, null, measure).ops);
		assert.equal(timed.find((t) => t.text === '3:41:07')?.ink, 'accent');
		const untimed = texts(layoutBodyContent(occasions.raceUntimed, null, measure).ops);
		assert.equal(untimed.find((t) => t.text === 'Finisher')?.ink, 'accent');
		assert.equal(of(layoutBodyContent(occasions.raceUntimed, null, measure).ops, 'route').length, 0);
	});

	test('the route sticker draws the line alone', () => {
		const { ops } = layoutBodyContent(occasions.route, null, measure);
		assert.equal(texts(ops).length, 0);
		assert.equal(of(ops, 'route').length, 1);
	});
});

describe('splits sticker', () => {
	const budget = splitsStickerMaxHeight(SPLIT_ROW_TEXT);

	test('the budget is half the usable story height at the legibility floor', () => {
		const b = SPLITS_STICKER_BUDGET;
		assert.equal(budget, (b.usableHeight * b.maxCover * SPLIT_ROW_TEXT) / b.legibleDigitsPx);
	});

	test('a full column and a full pair of columns both fit the budget, and one more row changes form', () => {
		const cap = splitsCapacity();
		assert.ok(cap > 0);
		assert.equal(splitsForm(cap), 'single');
		assert.equal(splitsForm(cap + 1), 'paired');
		assert.equal(splitsForm(cap * 2), 'paired');
		assert.equal(splitsForm(cap * 2 + 1), 'bars');
		for (const n of [cap, cap * 2, cap * 2 + 1, 120]) {
			const h = layoutSticker(splitsBody(n), 'Threkir', measure).height;
			assert.ok(h <= budget + 1e-9, `${n} rows: ${h} > ${budget}`);
		}
		assert.ok(layoutSticker(splitsBody(cap + 1), 'Threkir', measure).height <= budget);
	});

	test('a 10K that GPS reads at 11 splits and a half at 22 still print as tables', () => {
		assert.notEqual(splitsForm(11), 'bars');
		assert.notEqual(splitsForm(22), 'bars');
	});

	test('the fastest whole split takes the accent; a partial tail never does', () => {
		const body = splitsBody(6, true);
		const ops = texts(layoutBodyContent(body, null, measure).ops);
		const hot = ops.filter((t) => t.ink === 'accent');
		assert.equal(hot.length, 2);
		assert.ok(!hot.some((t) => t.text === '0.2 km'));
		assert.equal(hot[0].text, '1');
	});

	test('the bar form draws one bar per split, the fastest in the accent, over an average line', () => {
		const n = splitsCapacity() * 2 + 5;
		const { ops } = layoutBodyContent(splitsBody(n), null, measure);
		const bars = of(ops, 'bar');
		assert.equal(bars.length, n);
		assert.equal(bars.filter((b) => b.ink === 'accent').length, 1);
		assert.equal(of(ops, 'divider').length, 1);
		const right = Math.max(...bars.map((b) => b.x + b.w));
		assert.ok(right <= OCCASION_CONTENT_WIDTH + 1e-9);
		const fastest = bars.find((b) => b.ink === 'accent')!;
		assert.equal(Math.max(...bars.map((b) => b.h)), fastest.h);
	});
});

describe('occasions on a photo', () => {
	test('an occasion body places like the stats do, clear of the reply bar', () => {
		for (const [name, body] of Object.entries(occasions)) {
			const laid = layoutPhoto('story', body, 'Morning run', 'T', measure);
			for (const op of laid.ops) assert.ok(op.y <= 640 * 0.87 + 1e-6, `${name} ${op.kind} at ${op.y}`);
		}
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
