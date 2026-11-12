import { test } from 'node:test';
import assert from 'node:assert/strict';
import { safeReturnTo, DEFAULT_RETURN_TO } from './safe_redirect.js';

test('null / undefined / empty falls back to /dashboard', () => {
	assert.equal(safeReturnTo(null), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo(undefined), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo(''), DEFAULT_RETURN_TO);
});

test('plain internal paths pass through unchanged', () => {
	assert.equal(safeReturnTo('/dashboard'), '/dashboard');
	assert.equal(safeReturnTo('/runs/abc-123'), '/runs/abc-123');
	assert.equal(safeReturnTo('/settings/account'), '/settings/account');
});

test('preserves query string and hash', () => {
	assert.equal(safeReturnTo('/social?tab=feed'), '/social?tab=feed');
	assert.equal(safeReturnTo('/u/me?tab=notifications#top'), '/u/me?tab=notifications#top');
});

test('open-redirect: protocol-relative // is rejected', () => {
	assert.equal(safeReturnTo('//evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('//evil.com/phish'), DEFAULT_RETURN_TO);
});

test('open-redirect: backslash confusion is rejected', () => {
	// Browsers normalise '\' to '/', so '/\evil.com' resolves off-origin.
	assert.equal(safeReturnTo('/\\evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('/\\/evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('\\\\evil.com'), DEFAULT_RETURN_TO);
});

test('open-redirect: absolute URLs are rejected', () => {
	assert.equal(safeReturnTo('https://evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('http://evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('javascript:alert(1)'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('data:text/html,<script>'), DEFAULT_RETURN_TO);
});

test('open-redirect: a non-slash relative path is rejected', () => {
	// 'evil.com' resolves to https://internal.invalid/evil.com which is
	// same-origin, but it is not a root-relative path the app would ever
	// emit — reject it to keep the contract "must start with /".
	assert.equal(safeReturnTo('evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('dashboard'), DEFAULT_RETURN_TO);
});

test('custom fallback is honoured', () => {
	assert.equal(safeReturnTo(null, '/login'), '/login');
	assert.equal(safeReturnTo('//evil.com', '/login'), '/login');
});

test('open-redirect: dot segments that collapse to a protocol-relative path are rejected', () => {
	// The URL parser removes `.` / `..` segments, so each of these resolves
	// on the throwaway origin with a pathname of `//evil.com` — which a
	// browser then reads as a protocol-relative URL to evil.com.
	for (const raw of [
		'/.//evil.com',
		'/..//evil.com',
		'/a/..//evil.com',
		'/%2e//evil.com',
		'/%2e%2e//evil.com',
		'/./\\evil.com',
	]) {
		const out = safeReturnTo(raw);
		assert.equal(out, DEFAULT_RETURN_TO, `${JSON.stringify(raw)} -> ${out}`);
	}
});

test('open-redirect: a tab or newline after the first slash cannot smuggle in a host', () => {
	// The parser strips ASCII tab / LF / CR before resolving, so `/\t/x`
	// becomes `//x`. raw[1] is the control char, so only the origin check
	// stands between this and an off-origin redirect.
	assert.equal(safeReturnTo('/\t/evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('/\n/evil.com'), DEFAULT_RETURN_TO);
	assert.equal(safeReturnTo('/\r\n/evil.com/x'), DEFAULT_RETURN_TO);
});

test('a percent-encoded double slash stays a same-origin path', () => {
	// `%2F` is not a path separator to the parser, so this is one literal
	// segment on our origin — safe, and kept rather than discarded.
	assert.equal(safeReturnTo('/%2F%2Fevil.com'), '/%2F%2Fevil.com');
});

test('dot segments that stay on a normal path are resolved, not refused', () => {
	assert.equal(safeReturnTo('/runs/../dashboard'), '/dashboard');
	assert.equal(safeReturnTo('/./settings'), '/settings');
});

test('embedded credentials or an @ in the path never become a host', () => {
	const out = safeReturnTo('/@evil.com');
	assert.equal(out, '/@evil.com');
	assert.ok(out.startsWith('/') && !out.startsWith('//'));
});

test('every accepted result is root-relative and single-slashed', () => {
	const inputs = [
		'/dashboard', '/a//b', '/.//x', '/..//x', '/\t/x', '//x', '/\\x',
		'/%2e%2e//x', '/runs?next=//evil.com', '/#//evil.com',
	];
	for (const raw of inputs) {
		const out = safeReturnTo(raw);
		assert.ok(out.startsWith('/'), `${JSON.stringify(raw)} -> ${out}`);
		assert.ok(!out.startsWith('//') && !out.startsWith('/\\'), `${JSON.stringify(raw)} -> ${out}`);
	}
	assert.equal(safeReturnTo('/a//b'), '/a//b', 'an inner double slash is not a host');
	assert.equal(safeReturnTo('/runs?next=//evil.com'), '/runs?next=//evil.com');
});
