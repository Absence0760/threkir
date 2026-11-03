import { test } from 'node:test';
import assert from 'node:assert/strict';
import { recapCardLayout, recapCellOrigin, RECAP_CARD_ASPECTS } from './recap_card_layout';

test('the square card keeps the coordinates it has always had', () => {
	const l = recapCardLayout('square');
	assert.deepEqual(
		[l.width, l.height, l.pad, l.brandY, l.kickerY, l.heroY, l.subheadY, l.gridTop, l.colW, l.rowH, l.footerY],
		[1080, 1080, 72, 100, 182, 352, 422, 512, 468, 150, null],
	);
});

test('the story is 1080x1920 with its content below the top UI band', () => {
	const l = recapCardLayout('story');
	assert.deepEqual(
		[l.width, l.height, l.brandY, l.kickerY, l.heroY, l.subheadY, l.gridTop, l.rowH, l.footerY],
		[1080, 1920, 388, 470, 640, 710, 960, 200, 1620],
	);
});

test('every aspect fits its last stat value above its footer and inside the canvas', () => {
	for (const aspect of RECAP_CARD_ASPECTS) {
		const l = recapCardLayout(aspect);
		const last = recapCellOrigin(l, 5);
		assert.ok(last.valueY < (l.footerY ?? l.height) - 40, aspect);
		assert.ok(last.valueY <= l.height - l.pad, aspect);
	}
});

test('cells fill two columns, then the next row', () => {
	const l = recapCardLayout('square');
	assert.deepEqual(recapCellOrigin(l, 0), { x: 72, labelY: 512, valueY: 570 });
	assert.deepEqual(recapCellOrigin(l, 1), { x: 540, labelY: 512, valueY: 570 });
	assert.deepEqual(recapCellOrigin(l, 2), { x: 72, labelY: 662, valueY: 720 });
	assert.deepEqual(recapCellOrigin(l, 5), { x: 540, labelY: 812, valueY: 870 });
});
