import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	feeTotalsByCurrency,
	formatFeeMonth,
	summarizeFeeMonths,
	type PlatformFeeMonthRow,
} from './platform_fee_summary.js';

function row(over: Partial<PlatformFeeMonthRow>): PlatformFeeMonthRow {
	return {
		month: '2026-09-01',
		currency: 'usd',
		source: 'event',
		charge_count: 1,
		gross_fee_cents: 100,
		reversed_fee_cents: 0,
		net_fee_cents: 100,
		refunded_count: 0,
		partially_refunded_count: 0,
		refund_failed_count: 0,
		...over,
	};
}

test('summarizeFeeMonths: event and donation rows for one month and currency fold into one', () => {
	const out = summarizeFeeMonths([
		row({ charge_count: 4, gross_fee_cents: 400, reversed_fee_cents: 225, net_fee_cents: 175, refunded_count: 1 }),
		row({ source: 'donation', gross_fee_cents: 200, reversed_fee_cents: 40, net_fee_cents: 160, partially_refunded_count: 1 }),
	]);
	assert.deepEqual(out, [
		{
			month: '2026-09-01',
			currency: 'usd',
			charge_count: 5,
			gross_fee_cents: 600,
			reversed_fee_cents: 265,
			net_fee_cents: 335,
			refunded_count: 1,
			partially_refunded_count: 1,
			refund_failed_count: 0,
		},
	]);
});

test('summarizeFeeMonths: currencies are never added together', () => {
	const out = summarizeFeeMonths([row({ currency: 'usd' }), row({ currency: 'eur', net_fee_cents: 50 })]);
	assert.deepEqual(
		out.map((r) => [r.currency, r.net_fee_cents]),
		[
			['eur', 50],
			['usd', 100],
		],
	);
});

test('summarizeFeeMonths: newest month first, then currency A-Z', () => {
	const out = summarizeFeeMonths([
		row({ month: '2026-08-01', currency: 'usd' }),
		row({ month: '2026-10-01', currency: 'usd' }),
		row({ month: '2026-09-01', currency: 'usd' }),
		row({ month: '2026-09-01', currency: 'eur' }),
	]);
	assert.deepEqual(
		out.map((r) => `${r.month} ${r.currency}`),
		['2026-10-01 usd', '2026-09-01 eur', '2026-09-01 usd', '2026-08-01 usd'],
	);
});

test('summarizeFeeMonths: no rows is no months', () => {
	assert.deepEqual(summarizeFeeMonths([]), []);
});

test('feeTotalsByCurrency: sums every month per currency', () => {
	const out = feeTotalsByCurrency([
		row({ month: '2026-08-01', gross_fee_cents: 150, net_fee_cents: 150 }),
		row({ month: '2026-09-01', gross_fee_cents: 400, reversed_fee_cents: 225, net_fee_cents: 175 }),
		row({ currency: 'eur', gross_fee_cents: 50, net_fee_cents: 50 }),
	]);
	assert.deepEqual(out, [
		{ currency: 'eur', gross_fee_cents: 50, reversed_fee_cents: 0, net_fee_cents: 50 },
		{ currency: 'usd', gross_fee_cents: 550, reversed_fee_cents: 225, net_fee_cents: 325 },
	]);
});

test('formatFeeMonth: names the UTC month whatever the reader zone', () => {
	// 2026-09-01T00:00Z is still 31 August in New York; the label must not be.
	assert.equal(formatFeeMonth('2026-09-01', 'en-US'), 'September 2026');
	assert.equal(formatFeeMonth('2026-01-01', 'en-US'), 'January 2026');
});

test('formatFeeMonth: localised month name', () => {
	assert.match(formatFeeMonth('2026-09-01', 'de-DE'), /September 2026/);
	assert.match(formatFeeMonth('2026-09-01', 'fr-FR'), /septembre 2026/);
});

test('formatFeeMonth: an unparseable month is shown as given rather than "Invalid Date"', () => {
	assert.equal(formatFeeMonth('not-a-month', 'en-US'), 'not-a-month');
});
