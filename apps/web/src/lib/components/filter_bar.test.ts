import { test } from 'node:test';
import assert from 'node:assert/strict';
import { filtersButtonLabel, loneChipInTopRow } from './filter_bar.ts';

const withCount = (n: number) => `Filters, ${n} on`;

test('the Filters button is named by its label while nothing is on', () => {
	assert.equal(filtersButtonLabel(0, 'Filters', withCount), 'Filters');
});

test('the Filters button names the count once a filter is on', () => {
	assert.equal(filtersButtonLabel(1, 'Filters', withCount), 'Filters, 1 on');
	assert.equal(filtersButtonLabel(3, 'Filters', withCount), 'Filters, 3 on');
});

test('a lone chip with an icon joins the top row as a toggle', () => {
	assert.equal(loneChipInTopRow(1, true, true), true);
});

test('two chips, an iconless chip or no top row keep the chip line', () => {
	assert.equal(loneChipInTopRow(2, true, true), false);
	assert.equal(loneChipInTopRow(1, false, true), false);
	assert.equal(loneChipInTopRow(1, true, false), false);
	assert.equal(loneChipInTopRow(0, true, true), false);
});
