import { test } from 'node:test';
import assert from 'node:assert/strict';
import { escapeHtml, escapeXml, safeHref, xmlNumber } from './html_escape.js';

test('escapeHtml: encodes all five context-changing characters', () => {
	assert.equal(
		escapeHtml(`<a href="x" onclick='y'>&z</a>`),
		'&lt;a href=&quot;x&quot; onclick=&#39;y&#39;&gt;&amp;z&lt;/a&gt;',
	);
});

test('escapeHtml: ampersand is escaped first (no double-encoding)', () => {
	assert.equal(escapeHtml('a & b < c'), 'a &amp; b &lt; c');
	// A literal "&lt;" in the input must round-trip to "&amp;lt;", not "&lt;".
	assert.equal(escapeHtml('&lt;'), '&amp;lt;');
});

test('escapeHtml: neutralises an attribute-breakout payload', () => {
	const out = escapeHtml('" onerror="alert(1)');
	assert.ok(!out.includes('"'), 'no raw double-quote survives');
	assert.equal(out, '&quot; onerror=&quot;alert(1)');
});

test('escapeHtml: apostrophe uses numeric &#39; (XML/SVG-safe, not &apos;)', () => {
	assert.equal(escapeHtml("O'Brien"), 'O&#39;Brien');
});

test('escapeHtml: leaves a plain string untouched', () => {
	assert.equal(escapeHtml('Richmond Run Club'), 'Richmond Run Club');
});

test('safeHref: allows root-relative URLs', () => {
	assert.equal(safeHref('/clubs/richmond'), '/clubs/richmond');
	assert.equal(safeHref('/routes/123'), '/routes/123');
});

test('safeHref: allows http(s) URLs (any case)', () => {
	assert.equal(safeHref('https://threkir.com/x'), 'https://threkir.com/x');
	assert.equal(safeHref('HTTP://example.com'), 'HTTP://example.com');
});

test('safeHref: rejects javascript: and data: schemes', () => {
	assert.equal(safeHref('javascript:alert(document.cookie)'), '#');
	assert.equal(safeHref('data:text/html,<script>alert(1)</script>'), '#');
	// Leading-whitespace evasion is trimmed before the check.
	assert.equal(safeHref('  javascript:alert(1)'), '#');
});

test('safeHref: rejects protocol-relative and bare-word hrefs', () => {
	// `//evil.com` resolves to an external origin in the browser — reject it.
	assert.equal(safeHref('//evil.com'), '#');
	assert.equal(safeHref('mailto:x@y.com'), '#');
	assert.equal(safeHref('tel:+15551234'), '#');
});

test('safeHref: a backslash after the first slash is protocol-relative too', () => {
	// Browsers treat `\` as `/` in http(s) URLs, so `/\evil.com` resolves to
	// `//evil.com` — the same external origin the `//` rule exists to refuse.
	assert.equal(safeHref('/\\evil.com'), '#');
	assert.equal(safeHref('/\\/evil.com'), '#');
	assert.equal(safeHref('\\\\evil.com'), '#');
});

test('safeHref: a tab or newline inside the slashes cannot split the // check', () => {
	// The URL parser strips ASCII tab / LF / CR anywhere in the string, so
	// `/\t/evil.com` is `//evil.com` by the time the browser follows it.
	assert.equal(safeHref('/\t/evil.com'), '#');
	assert.equal(safeHref('/\n/evil.com'), '#');
	assert.equal(safeHref('/\r\n\\evil.com'), '#');
	// Same stripping defeats a scheme split across a newline.
	assert.equal(safeHref('java\nscript:alert(1)'), '#');
});

test('safeHref: an inner double slash on a root-relative path is still internal', () => {
	assert.equal(safeHref('/routes//123'), '/routes//123');
	assert.equal(safeHref('/search?next=//evil.com'), '/search?next=//evil.com');
});

test('escapeHtml + safeHref: an http URL carrying a quote cannot break out of the attribute', () => {
	const href = escapeHtml(safeHref('https://x.com/"onmouseover="alert(1)'));
	assert.ok(!href.includes('"'), href);
	assert.equal(href, 'https://x.com/&quot;onmouseover=&quot;alert(1)');
});

// XML 1.0's Char production: #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD]
// | [#x10000-#x10FFFF]. Every code point outside it is checked at each edge.
test('escapeXml: replaces exactly the code points XML 1.0 cannot carry', () => {
	const forbidden = ['\u0000', '\u0008', '\u000B', '\u000C', '\u000E', '\u001F', '￾', '￿', '\uD800', '\uDFFF'];
	for (const ch of forbidden) {
		assert.equal(escapeXml(`a${ch}b`), 'a�b', `U+${ch.charCodeAt(0).toString(16)}`);
	}
	const legal = ['\t', '\n', '\r', ' ', '퟿', '', '�', '\u{10000}', '\u{10FFFF}'];
	for (const ch of legal) {
		assert.equal(escapeXml(`a${ch}b`), `a${ch}b`, `U+${ch.codePointAt(0)!.toString(16)} is legal`);
	}
});

test('escapeXml: still escapes the five reserved characters, and a surrogate pair is one legal char', () => {
	assert.equal(escapeXml(`<a href="x">'&'</a>`), '&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;');
	// A high+low pair is one astral code point; only an unpaired half is replaced.
	assert.equal(escapeXml('🏔'), '\u{1F3D4}');
	assert.equal(escapeXml('\uDFD4\uD83C'), '��');
});

test('xmlNumber: only a finite JS number becomes text', () => {
	assert.equal(xmlNumber(47.5), '47.5');
	assert.equal(xmlNumber(-0.25), '-0.25');
	assert.equal(xmlNumber(0), '0');
	for (const v of [Number.NaN, Infinity, -Infinity, '47.5', '"/><x', null, undefined, {}, [1]]) {
		assert.equal(xmlNumber(v), null, `${String(v)} is not written`);
	}
});
