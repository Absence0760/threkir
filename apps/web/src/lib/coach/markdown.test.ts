import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderCoachMarkdown } from './markdown.js';

// The `class` attribute is deliberately excluded from COACH_ALLOWED_ATTR so an
// LLM-emitted `<span class="modal-backdrop">` can't pick up the global overlay
// CSS and clickjack the page (audit-xss L1). This pins that invariant — it
// fails if a future edit adds `class` to the allow-list.
test('renderCoachMarkdown strips class attributes from LLM-emitted HTML', () => {
	const out = renderCoachMarkdown('<span class="modal-backdrop">trap</span>');
	assert.ok(out.includes('trap'), 'text content is preserved');
	assert.ok(!/class\s*=/.test(out), 'no class attribute survives sanitisation');
	assert.ok(!out.includes('modal-backdrop'), 'the global class name does not survive');
});

test('renderCoachMarkdown drops a javascript: link href but keeps the text', () => {
	const out = renderCoachMarkdown('[click](javascript:alert(document.cookie))');
	assert.ok(!out.toLowerCase().includes('javascript:'), 'javascript: scheme is removed');
	assert.ok(out.includes('click'), 'link text is preserved');
});

test('renderCoachMarkdown keeps an https link and forces target/rel', () => {
	const out = renderCoachMarkdown('[ok](https://threkir.com)');
	assert.ok(out.includes('href="https://threkir.com"'), 'https href survives');
	assert.ok(out.includes('rel="noopener noreferrer"'), 'rel is forced on every anchor');
	assert.ok(out.includes('target="_blank"'), 'target is forced on every anchor');
});

test('renderCoachMarkdown strips an event-handler attribute', () => {
	const out = renderCoachMarkdown('<img src="x" onerror="alert(1)">');
	assert.ok(!/onerror/i.test(out), 'inline event handler is removed');
});

// Multibyte + punctuation that lives in real LLM replies must survive the
// marked → DOMPurify round-trip verbatim. This pins the same invariant the
// `SSE: special characters` Playwright e2e checks, but at the cheap unit
// layer so a "works for ASCII, drops on multibyte" regression in marked or
// the sanitiser fails here first. Mirrors the e2e's STR exactly.
test('renderCoachMarkdown preserves emoji, accents, em-dash and curly quotes verbatim', () => {
	const STR = 'Pace: `5:30/km` — try “easy effort” 😅 (café tempo)';
	const out = renderCoachMarkdown(STR);
	assert.ok(out.includes('😅'), 'emoji survives');
	assert.ok(out.includes('café'), 'accented character survives');
	assert.ok(out.includes('—'), 'em-dash survives');
	assert.ok(out.includes('“easy effort”'), 'curly quotes survive');
	assert.ok(out.includes('<code>5:30/km</code>'), 'backtick span becomes a code element');
	// The e2e asserts the bubble textContent matches /😅.*café/ — guard the
	// same ordering at the HTML level (emoji precedes café, nothing between
	// drops out).
	assert.match(out, /😅[\s\S]*café/u, 'emoji precedes café with content intact');
});

const hrefsOf = (html: string) => [...html.matchAll(/href="([^"]*)"/g)].map((m) => m[1]);

test('renderCoachMarkdown removes script, style and embedding elements outright', () => {
	const out = renderCoachMarkdown(
		'hi <script>alert(1)</script><style>body{display:none}</style>' +
			'<iframe src="https://evil.example"></iframe><object data="x"></object>' +
			'<embed src="x"><form action="https://evil.example"><input name="pw"></form>',
	).toLowerCase();
	for (const tag of ['<script', '<style', '<iframe', '<object', '<embed', '<form', '<input']) {
		assert.ok(!out.includes(tag), `${tag} survived: ${out}`);
	}
	assert.ok(!out.includes('alert(1)'), 'script text is not left behind as copy');
	assert.ok(out.includes('hi'));
});

test('renderCoachMarkdown renders no image, so a reply cannot load a remote pixel', () => {
	// `img` is not on the allow-list: a markdown image in an LLM reply would
	// otherwise fetch an attacker URL with the reader's IP the moment the
	// bubble paints.
	const out = renderCoachMarkdown('![pace chart](https://tracker.example/p.gif?u=1)');
	assert.ok(!/<img/i.test(out), out);
	assert.ok(!out.includes('tracker.example'), out);
});

test('renderCoachMarkdown drops an svg or math payload with its handlers', () => {
	const out = renderCoachMarkdown(
		'<svg onload="alert(1)"><circle r="5"/></svg><math><mi xlink:href="javascript:alert(1)">x</mi></math>',
	);
	assert.ok(!/<svg|<math|onload|javascript:/i.test(out), out);
});

test('renderCoachMarkdown keeps only http(s) and mailto hrefs', () => {
	const out = renderCoachMarkdown(
		[
			'[a](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)',
			'[b](vbscript:msgbox(1))',
			'[c](tel:+15551234567)',
			'[d](//evil.example/x)',
			'[e](mailto:coach@threkir.com)',
			'[f](HTTPS://threkir.com/plan)',
		].join(' '),
	);
	assert.deepEqual(hrefsOf(out), ['mailto:coach@threkir.com', 'HTTPS://threkir.com/plan']);
});

test('renderCoachMarkdown is not fooled by an entity-encoded or whitespace-split javascript: scheme', () => {
	const out = renderCoachMarkdown(
		'<a href="&#106;avascript:alert(1)">x</a> <a href="java\tscript:alert(1)">y</a> <a href=" javascript:alert(1)">z</a>',
	);
	assert.deepEqual(hrefsOf(out), [], out);
	assert.ok(!/javascript/i.test(out), out);
});

test('renderCoachMarkdown strips style and id, so a reply cannot restyle or clobber the page', () => {
	const out = renderCoachMarkdown(
		'<span style="position:fixed;inset:0;z-index:9999" id="currentUser">overlay</span>' +
			'<p name="config" data-x="1">p</p>',
	);
	assert.ok(out.includes('overlay'));
	assert.ok(!/style\s*=|id\s*=|name\s*=|data-x/i.test(out), out);
});

test('renderCoachMarkdown forces a new tab and no opener even when the reply sets its own target', () => {
	const out = renderCoachMarkdown('<a href="https://threkir.com" target="_self" rel="opener">go</a>');
	assert.ok(out.includes('target="_blank"'), out);
	assert.ok(out.includes('rel="noopener noreferrer"'), out);
	assert.ok(!out.includes('_self') && !/rel="opener"/.test(out), out);
});

test('renderCoachMarkdown keeps the formatting a training reply actually uses', () => {
	const out = renderCoachMarkdown(
		'## Week 3\n\n| Day | Run |\n| --- | --- |\n| Tue | **6 x 800 m** |\n\n- easy\n- *long*\n\n> rest',
	);
	for (const tag of ['<h2>', '<table>', '<th>', '<td>', '<strong>', '<ul>', '<li>', '<em>', '<blockquote>']) {
		assert.ok(out.includes(tag), `${tag} missing from ${out}`);
	}
});
