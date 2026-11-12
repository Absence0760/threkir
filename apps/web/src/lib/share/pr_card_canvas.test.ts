import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { RUN_PHOTO_ASPECTS, RUN_SHARE_INKS } from './share_look';
import { PR_CARD_BAND, PR_CARD_GROUNDS, layoutPrCard, type PrCardText } from './pr_card_canvas';
import { photoCanvasSize, type DrawOp, type MeasureText } from './run_sticker_canvas';

const measure: MeasureText = (text, font) => text.length * (font.size * 0.6 + font.letterSpacing);

const text: PrCardText = {
	headline: 'New personal record',
	distance: '5K',
	time: '24:00',
	improvement: '00:42 faster',
	detail: 'Previous best 24:42',
	date: '1 Nov 2026',
};

const texts = (ops: DrawOp[]) => ops.flatMap((op) => (op.kind === 'text' ? [op] : []));

describe('PR card layout', () => {
	test('is the photo canvas for its aspect', () => {
		for (const aspect of RUN_PHOTO_ASPECTS) {
			const laid = layoutPrCard(aspect, text, true, 'Threkir', measure);
			assert.deepEqual({ w: laid.width, h: laid.height }, photoCanvasSize(aspect));
		}
	});

	test('prints the headline, distance, time, improvement, detail and date in that order', () => {
		const laid = layoutPrCard('post', text, false, 'Threkir', measure);
		const printed = texts(laid.ops).map((t) => t.text);
		assert.deepEqual(printed.slice(0, 6), [
			'NEW PERSONAL RECORD',
			'5K',
			'24:00',
			'00:42 faster',
			'Previous best 24:42',
			'1 Nov 2026',
		]);
		const ys = texts(laid.ops).slice(0, 6).map((t) => t.y);
		for (let i = 1; i < ys.length; i++) assert.ok(ys[i] > ys[i - 1]);
	});

	test('drops the improvement and detail lines it was not given', () => {
		const laid = layoutPrCard('post', { ...text, improvement: null, detail: null }, false, 'Threkir', measure);
		const printed = texts(laid.ops).map((t) => t.text);
		assert.ok(!printed.includes('00:42 faster'));
		assert.ok(!printed.includes('Previous best 24:42'));
	});

	test('draws the route only when there is one', () => {
		assert.equal(layoutPrCard('post', text, true, 'Threkir', measure).ops.filter((o) => o.kind === 'route').length, 1);
		assert.equal(layoutPrCard('post', text, false, 'Threkir', measure).ops.filter((o) => o.kind === 'route').length, 0);
	});

	test('every op sits inside the canvas, below the band, and a long line scales down to fit', () => {
		for (const aspect of RUN_PHOTO_ASPECTS) {
			const long = { ...text, distance: 'Half marathon half marathon half marathon' };
			const laid = layoutPrCard(aspect, long, true, 'Threkir', measure);
			for (const op of laid.ops) {
				assert.ok(op.y >= PR_CARD_BAND && op.y <= laid.height, `${aspect} ${op.kind} at y=${op.y}`);
			}
			for (const t of texts(laid.ops)) {
				assert.ok(measure(t.text, t.font) * t.scale <= laid.width - 56 + 0.001, `${t.text} overflows`);
			}
		}
	});

	test('the route shrinks into the room the lines leave, never under the signature', () => {
		for (const aspect of RUN_PHOTO_ASPECTS) {
			const laid = layoutPrCard(aspect, text, true, 'Threkir', measure);
			const route = laid.ops.find((o) => o.kind === 'route');
			const mark = laid.ops.find((o) => o.kind === 'mark');
			assert.ok(route && route.kind === 'route' && mark);
			assert.ok(route.y + route.size <= mark.y, `${aspect}: route ends at ${route.y + route.size}, mark at ${mark.y}`);
		}
		const post = layoutPrCard('post', text, true, 'Threkir', measure).ops.find((o) => o.kind === 'route');
		const story = layoutPrCard('story', text, true, 'Threkir', measure).ops.find((o) => o.kind === 'route');
		assert.ok(post?.kind === 'route' && story?.kind === 'route' && post.size < story.size);
	});

	test('the signature is last, and on a story it stays clear of the reply bar', () => {
		const laid = layoutPrCard('story', text, true, 'Threkir', measure);
		const mark = laid.ops.find((o) => o.kind === 'mark');
		assert.ok(mark);
		assert.ok(mark.y + 18 <= laid.height * 0.87 + 0.001);
	});

	test('with the mark turned off the card draws no signature', () => {
		const laid = layoutPrCard('story', text, true, null, measure);
		assert.equal(laid.ops.filter((o) => o.kind === 'mark').length, 0);
		assert.ok(!texts(laid.ops).some((t) => t.text === 'THREKIR'));
	});

	test('every ink has a ground', () => {
		for (const ink of RUN_SHARE_INKS) assert.match(PR_CARD_GROUNDS[ink], /^#[0-9A-F]{6}$/i);
	});
});
