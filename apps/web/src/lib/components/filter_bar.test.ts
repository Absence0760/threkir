import { test } from 'node:test';
import assert from 'node:assert/strict';
import { filtersButtonLabel } from './filter_bar.ts';

const withCount = (n: number) => `Filters, ${n} on`;

test('the Filters button is named by its label while nothing is on', () => {
	assert.equal(filtersButtonLabel(0, 'Filters', withCount), 'Filters');
});

test('the Filters button names the count once a filter is on', () => {
	assert.equal(filtersButtonLabel(1, 'Filters', withCount), 'Filters, 1 on');
	assert.equal(filtersButtonLabel(3, 'Filters', withCount), 'Filters, 3 on');
});
