import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { extractLink } from './mailpit';

// extractLink used to take the first URL in the message. The brand mark in
// the email header put an <img src> ahead of the CTA, so these pin the thing
// that actually matters: the link the test clicks is the ACTION link, not
// whatever asset the template happens to load first.

function msg(parts: { HTML?: string; Text?: string }) {
	return {
		ID: 'x',
		From: { Address: 'noreply@threkir.com', Name: 'Threkir' },
		To: [{ Address: 'runner@test.com', Name: '' }],
		Subject: 'Reset your password',
		HTML: parts.HTML ?? '',
		Text: parts.Text ?? ''
	};
}

const VERIFY = 'https://threkir.com/auth/reset?token_hash=abc123&type=recovery';

test('prefers the CTA anchor over an image that precedes it', () => {
	const html =
		`<img src="https://threkir.com/email-logo.png" width="32" height="32" alt="">` +
		`<a href="${VERIFY.replace(/&/g, '&amp;')}">Reset password</a>`;

	assert.equal(extractLink(msg({ HTML: html })), VERIFY);
});

test('decodes &amp; in the anchor href', () => {
	const html = `<a href="https://threkir.com/x?a=1&amp;b=2">go</a>`;
	assert.equal(extractLink(msg({ HTML: html })), 'https://threkir.com/x?a=1&b=2');
});

test('falls back to the text part when there is no anchor', () => {
	const html = `<img src="https://threkir.com/email-logo.png" alt="">`;
	const text = `Open ${VERIFY} to continue.`;

	assert.equal(extractLink(msg({ HTML: html, Text: text })), VERIFY);
});

test('single-quoted hrefs are matched too', () => {
	assert.equal(
		extractLink(msg({ HTML: `<a href='https://threkir.com/y'>y</a>` })),
		'https://threkir.com/y'
	);
});

test('throws when the message carries no URL at all', () => {
	assert.throws(() => extractLink(msg({ Text: 'Your code is 123456' })), /no URL found/);
});
