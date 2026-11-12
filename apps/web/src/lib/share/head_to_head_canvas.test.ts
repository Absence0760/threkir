import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { MeasureText } from './run_sticker_canvas';
import type { HeadToHeadRow } from '../social/head_to_head';
import { HEAD_TO_HEAD_CANVAS, headToHeadPreviewKey, layoutHeadToHead, type HeadToHeadCardInput, type HeadToHeadOp } from './head_to_head_canvas';

const measure: MeasureText = (text, font) => text.length * (font.size * 0.6 + font.letterSpacing);

const input = (over: Partial<HeadToHeadCardInput> = {}): HeadToHeadCardInput => ({
	targetName: 'River Loop',
	myName: 'Me',
	friendName: '@sam',
	mySeconds: 1900,
	friendSeconds: 1950,
	kicker: 'Head to head',
	vs: 'vs',
	outcome: (winner, margin) => (winner === 'tie' ? 'Dead heat' : `${winner} by ${margin}`),
	wordmark: 'Threkir',
	...over,
});

type TextOp = Extract<HeadToHeadOp, { kind: 'text' }>;
const texts = (ops: HeadToHeadOp[]) => ops.filter((o): o is TextOp => o.kind === 'text');
const find = (ops: HeadToHeadOp[], t: string) => texts(ops).find((o) => o.text === t);

test('the card prints both names, both times, the outcome and the mark', () => {
	const ops = layoutHeadToHead(input(), measure);
	for (const t of ['HEAD TO HEAD', 'River Loop', 'Me', '@sam', 'VS', '31:40', '32:30', 'me by 0:50', 'THREKIR']) {
		assert.ok(find(ops, t), `missing ${t}`);
	}
	assert.equal(ops.filter((o) => o.kind === 'mark').length, 1);
});

test('the winner\'s time takes the brand ink, the other the stat ink', () => {
	const mine = layoutHeadToHead(input(), measure);
	assert.equal(find(mine, '31:40')?.ink, 'brand');
	assert.equal(find(mine, '32:30')?.ink, 'stat');
	const theirs = layoutHeadToHead(input({ mySeconds: 2000 }), measure);
	assert.equal(find(theirs, '33:20')?.ink, 'stat');
	assert.equal(find(theirs, '32:30')?.ink, 'brand');
	assert.ok(find(theirs, 'friend by 0:50'));
});

test('a dead heat brands neither time', () => {
	const ops = layoutHeadToHead(input({ mySeconds: 1950 }), measure);
	assert.ok(find(ops, 'Dead heat'));
	assert.ok(texts(ops).filter((o) => o.text === '32:30').every((o) => o.ink === 'stat'));
});

test('a long name scales down to its column instead of running over', () => {
	const ops = layoutHeadToHead(input({ friendName: '@a-very-long-handle-indeed-for-a-card' }), measure);
	const op = find(ops, '@a-very-long-handle-indeed-for-a-card');
	assert.ok(op && op.scale < 1);
	assert.ok(measure(op.text, op.font) * op.scale <= (HEAD_TO_HEAD_CANVAS.w - 56 - 44) / 2 + 1e-9);
});

test('a long target name wraps to two lines at most', () => {
	const ops = layoutHeadToHead(input({ targetName: 'The very long riverside loop out past the old mill and back again twice' }), measure);
	const titles = texts(ops).filter((o) => o.font.size === 22);
	assert.equal(titles.length, 2);
	assert.ok(titles[1].text.endsWith('…'));
});

test('everything sits inside the canvas', () => {
	for (const op of layoutHeadToHead(input(), measure)) {
		assert.ok(op.x >= 0 && op.x <= HEAD_TO_HEAD_CANVAS.w);
		assert.ok(op.y >= 0 && op.y <= HEAD_TO_HEAD_CANVAS.h);
	}
});

test('the preview key changes when a reload brings new times for the same friend', () => {
	const row: HeadToHeadRow = {
		friendId: 'f1',
		friendDisplayName: 'Sam',
		friendHandle: 'sam',
		friendAvatarUrl: null,
		targetName: 'River Loop',
		myRunId: 'r1',
		mySeconds: 1900,
		friendRunId: 'r2',
		friendSeconds: 1950,
	};
	const key = headToHeadPreviewKey(row);
	assert.equal(headToHeadPreviewKey({ ...row, friendAvatarUrl: 'https://x/a.png', myRunId: 'r9' }), key);
	for (const over of [
		{ friendId: 'f2' },
		{ mySeconds: 1880 },
		{ friendSeconds: 1940 },
		{ targetName: 'Hill Loop' },
		{ friendHandle: 'sammy' },
	]) {
		assert.notEqual(headToHeadPreviewKey({ ...row, ...over }), key, JSON.stringify(over));
	}
});
