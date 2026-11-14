import { test } from 'node:test';
import assert from 'node:assert/strict';
import { filtersButtonLabel, lineFades, lineMask, loneChipInTopRow, trailingOnLine } from './filter_bar.ts';

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

test('a chip line fades its end while there is more, its start once scrolled', () => {
	assert.deepEqual(lineFades(0, 300, 600), { start: false, end: true });
	assert.deepEqual(lineFades(150, 300, 600), { start: true, end: true });
	assert.deepEqual(lineFades(300, 300, 600), { start: true, end: false });
	assert.deepEqual(lineFades(0, 300, 300), { start: false, end: false });
	// RTL scrollLeft runs negative from the start edge.
	assert.deepEqual(lineFades(-150, 300, 600), { start: true, end: true });
});

test('the mask fades the start on the right in RTL, and is none with no fade', () => {
	assert.equal(lineMask({ start: false, end: false }, false), 'none');
	assert.match(lineMask({ start: false, end: true }, false), /^linear-gradient\(to right, #000, .*, transparent\)$/);
	assert.match(lineMask({ start: false, end: true }, true), /^linear-gradient\(to right, transparent, .*, #000\)$/);
});

test('trailing actions stand on the chip line only when nothing shares a top row', () => {
	const base = { hasSearch: false, hasFilters: false, hasToggle: false, hasTrailing: true, hasLine: true };
	assert.equal(trailingOnLine(base), true);
	assert.equal(trailingOnLine({ ...base, hasSearch: true }), false);
	assert.equal(trailingOnLine({ ...base, hasFilters: true }), false);
	assert.equal(trailingOnLine({ ...base, hasToggle: true }), false);
	assert.equal(trailingOnLine({ ...base, hasLine: false }), false);
});
