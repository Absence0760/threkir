// Unit tests for the help-illustration allow-list and the web theming pass.
//   npx tsx --test src/lib/help/illustration.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ILLUSTRATION_MAX_BYTES, ILLUSTRATION_PALETTE, illustrationProblems, themeIllustration } from './illustration';

const wrap = (inner: string, root = 'xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 200"') => `<svg ${root}>${inner}</svg>\n`;
const CLEAN = wrap(
	'<!-- a note --><g stroke="currentColor"><rect x="1" y="1" width="9" height="9" rx="2" fill="#ff00a4"/><path d="M0 0 L5 5" stroke="#ff00a1" stroke-dasharray="2 4"/></g>',
);

test('a clean diagram passes', () => {
	assert.deepEqual(illustrationProblems(CLEAN), []);
});

test('text, script, foreignObject, image, style and links fail', () => {
	for (const inner of [
		'<text x="1" y="1">Hi</text>',
		'<script>alert(1)</script>',
		'<foreignObject width="1" height="1"></foreignObject>',
		'<image href="x.png" width="1" height="1"/>',
		'<style>rect{fill:red}</style>',
		'<use href="#a"/>',
	]) {
		assert.notDeepEqual(illustrationProblems(wrap(inner)), [], inner);
	}
});

test('a stray word between elements is text, and fails', () => {
	assert.match(illustrationProblems(wrap('Hello<g></g>')).join('\n'), /text or a malformed tag/);
});

test('event handlers, href, style, class and url() references fail', () => {
	assert.match(illustrationProblems(wrap('<rect onclick="x()" width="1" height="1"/>')).join('\n'), /onclick/);
	assert.match(illustrationProblems(wrap('<rect style="fill:red" width="1" height="1"/>')).join('\n'), /style/);
	assert.match(illustrationProblems(wrap('<rect class="a" width="1" height="1"/>')).join('\n'), /class/);
	assert.match(illustrationProblems(wrap('<rect fill="url(#g)" width="1" height="1"/>')).join('\n'), /url/);
});

test('only currentColor, none and the palette placeholders may paint', () => {
	assert.match(illustrationProblems(wrap('<rect fill="#C24E24" width="1" height="1"/>')).join('\n'), /outside the token set/);
	assert.match(illustrationProblems(wrap('<rect stroke="red" width="1" height="1"/>')).join('\n'), /outside the token set/);
	for (const colour of ['none', 'currentColor', ...Object.values(ILLUSTRATION_PALETTE)]) {
		assert.deepEqual(illustrationProblems(wrap(`<rect fill="${colour}" width="1" height="1"/>`)), [], colour);
	}
});

test('the root must be one responsive <svg> with a viewBox and no fixed size', () => {
	assert.match(illustrationProblems(wrap('', 'xmlns="http://www.w3.org/2000/svg"')).join('\n'), /viewBox/);
	assert.match(illustrationProblems(wrap('', 'xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1" width="10"')).join('\n'), /no width or height/);
	assert.match(illustrationProblems('<g></g>').join('\n'), /root element is <g>/);
	assert.match(illustrationProblems('<?xml version="1.0"?>' + CLEAN).join('\n'), /XML declaration/);
	assert.match(illustrationProblems('<!DOCTYPE svg>' + CLEAN).join('\n'), /DOCTYPE/);
});

test('a file over the byte budget fails', () => {
	const big = wrap(`<path d="M0 0 ${'L1 1 '.repeat(ILLUSTRATION_MAX_BYTES / 5)}"/>`);
	assert.match(illustrationProblems(big).join('\n'), /byte budget/);
});

test('themeIllustration swaps each placeholder for its token variable and hides the drawing from assistive tech', () => {
	const out = themeIllustration(CLEAN);
	assert.ok(out.startsWith('<svg aria-hidden="true" focusable="false" xmlns='));
	assert.ok(out.includes('fill="var(--illus-surface)"'));
	assert.ok(out.includes('stroke="var(--illus-accent)"'));
	assert.ok(!out.includes('#ff00a'));
	assert.ok(!out.includes('<!--'));
});
