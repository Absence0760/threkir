import { test } from 'node:test';
import assert from 'node:assert/strict';
import { neutraliseSpreadsheetFormula } from './csv_formula';

test('neutraliseSpreadsheetFormula: every formula trigger at the start is prefixed with a quote', () => {
	for (const v of ['=1+1', '+1', '-2+3', '@SUM(A1)', '\t=cmd', '\r=cmd']) {
		assert.equal(neutraliseSpreadsheetFormula(v), `'${v}`, JSON.stringify(v));
	}
});

test('neutraliseSpreadsheetFormula: a trigger anywhere but the first character, or none, is left alone', () => {
	for (const v of ['', 'Hill repeats', 'a=b', '5k - easy', ' =x', "'=already", '10:00']) {
		assert.equal(neutraliseSpreadsheetFormula(v), v, JSON.stringify(v));
	}
});
