// Tests for the pure RevenueCat hosted-checkout URL builder.
// `revenuecat.ts` (which imports `$env/dynamic/public`) can't be imported
// under node:test — this helper carries the testable behaviour.
//   npx tsx --test src/lib/billing/revenuecat_links.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { annualSavingPercent, buildCheckoutUrl, PRO_PACKAGE_IDS } from './revenuecat_links';

const BASE = 'https://pay.rev.cat/abc123';

test('appends the user id as the App User ID path segment', () => {
	assert.equal(buildCheckoutUrl(BASE, 'user-1'), `${BASE}/user-1`);
});

test('URL-encodes the user id (App User IDs can contain reserved chars)', () => {
	assert.equal(buildCheckoutUrl(BASE, 'a b/c'), `${BASE}/a%20b%2Fc`);
});

test('strips a trailing slash on the base before appending', () => {
	assert.equal(buildCheckoutUrl(`${BASE}/`, 'user-1'), `${BASE}/user-1`);
	assert.equal(buildCheckoutUrl(`${BASE}///`, 'user-1'), `${BASE}/user-1`);
});

test('appends a URL-encoded redirect_url when supplied', () => {
	const url = buildCheckoutUrl(BASE, 'user-1', 'https://app.example.com/settings/upgrade');
	assert.equal(
		url,
		`${BASE}/user-1?redirect_url=${encodeURIComponent('https://app.example.com/settings/upgrade')}`,
	);
});

test('omits the redirect_url query when no return URL is given', () => {
	const url = buildCheckoutUrl(BASE, 'user-1');
	assert.ok(!url?.includes('redirect_url'));
});

test('returns null when the base is empty (fail-closed / unconfigured)', () => {
	assert.equal(buildCheckoutUrl('', 'user-1'), null);
	assert.equal(buildCheckoutUrl('   ', 'user-1', 'https://x/y'), null);
});

test('appends the documented package_id for a preselected plan', () => {
	assert.equal(
		buildCheckoutUrl(BASE, 'user-1', undefined, PRO_PACKAGE_IDS.annual),
		`${BASE}/user-1?package_id=%24rc_annual`,
	);
	assert.equal(
		buildCheckoutUrl(BASE, 'user-1', undefined, PRO_PACKAGE_IDS.monthly),
		`${BASE}/user-1?package_id=%24rc_monthly`,
	);
});

test('carries package_id and redirect_url together', () => {
	const url = buildCheckoutUrl(BASE, 'user-1', 'https://app.example.com/settings/upgrade', '$rc_annual');
	assert.equal(
		url,
		`${BASE}/user-1?package_id=%24rc_annual&redirect_url=${encodeURIComponent('https://app.example.com/settings/upgrade')}`,
	);
});

test('the two plans map to the default offering packages', () => {
	assert.deepEqual(PRO_PACKAGE_IDS, { monthly: '$rc_monthly', annual: '$rc_annual' });
});

test('annualSavingPercent rounds down so the saving is never overstated', () => {
	// 1 - 79.99 / 119.88 = 33.27%.
	assert.equal(annualSavingPercent(9.99, 79.99), 33);
	// 1 - 9,800 / 14,400 = 31.94%: rounding would claim 32.
	assert.equal(annualSavingPercent(1200, 9800), 31);
});

test('annualSavingPercent does not floor an exact percentage below itself', () => {
	assert.equal(annualSavingPercent(10, 90), 25);
	assert.equal(annualSavingPercent(10, 60), 50);
});

test('annualSavingPercent states nothing when the year is no cheaper', () => {
	assert.equal(annualSavingPercent(9.99, 119.88), null);
	assert.equal(annualSavingPercent(9.99, 130), null);
});

test('annualSavingPercent states nothing under one percent', () => {
	assert.equal(annualSavingPercent(10, 119.5), null);
});

test('annualSavingPercent states nothing for a zero or negative price', () => {
	assert.equal(annualSavingPercent(0, 79.99), null);
	assert.equal(annualSavingPercent(9.99, 0), null);
	assert.equal(annualSavingPercent(-1, 79.99), null);
});
