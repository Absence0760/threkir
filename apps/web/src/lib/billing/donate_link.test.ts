import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { donateUrlProblem } from './donate_link';

const __dirname = dirname(fileURLToPath(import.meta.url));

test('a Stripe Payment Link on either host is accepted', () => {
	assert.equal(donateUrlProblem('https://donate.stripe.com/abc123'), null);
	assert.equal(donateUrlProblem('https://buy.stripe.com/test_abc123'), null);
	assert.equal(donateUrlProblem('  https://donate.stripe.com/abc123  '), null);
});

test('empty, malformed, non-https and non-Stripe links are refused', () => {
	assert.ok(donateUrlProblem(''));
	assert.ok(donateUrlProblem('   '));
	assert.ok(donateUrlProblem('donate.stripe.com/abc'));
	assert.ok(donateUrlProblem('http://donate.stripe.com/abc123'));
	assert.ok(donateUrlProblem('https://stripe.com/abc123'));
	assert.ok(donateUrlProblem('https://donate.stripe.com.evil.example/abc'));
	assert.ok(donateUrlProblem('https://donate.stripe.com/'));
});

test('the GitHub Sponsors placeholder that shipped is refused', () => {
	// `https://github.com/sponsors` is nobody's sponsor page; GitHub redirects
	// it to its own marketing page, which is where every Donate click went.
	assert.ok(donateUrlProblem('https://github.com/sponsors'));
});

test('no source hard-codes a donation destination any more', () => {
	for (const rel of ['../../routes/settings/upgrade/+page.svelte', '../../routes/compare/+page.svelte']) {
		const src = readFileSync(resolve(__dirname, rel), 'utf-8');
		assert.ok(!/github\.com\/sponsors|DONATE_URL\s*=/.test(src), `${rel} hard-codes a donate URL; read it through donateUrl()`);
	}
});
