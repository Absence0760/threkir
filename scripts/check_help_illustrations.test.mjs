// Unit tests for scripts/check_help_illustrations.mjs — the guard that keeps
// every help-guide illustration text-free, theme-painted and referenced.
//
// Run: node --test scripts/check_help_illustrations.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

import { illustrationBlocks, illustrationGuardProblems } from './check_help_illustrations.mjs';
import { REPO_ROOT } from './gen_help_guides.mjs';

const SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4" fill="#ff00a1" stroke="currentColor"/></svg>\n';
const guide = (/** @type {Record<string, unknown>[]} */ blocks) => ({ id: 'g', sections: [{ heading: 'H', blocks }] });
const ill = (id = 'a', alt = 'A diagram.') => ({ type: 'illustration', id, alt });
const check = (/** @type {Record<string, unknown>[]} */ blocks, files = [{ name: 'a.svg', source: SVG }]) =>
	illustrationGuardProblems({ guides: [guide(blocks)], files });

test('a referenced, clean file with alt text passes', () => {
	assert.deepEqual(check([{ type: 'p', text: 'x' }, ill()]), []);
});

test('illustrationBlocks finds each block with where it is', () => {
	assert.deepEqual(illustrationBlocks([guide([{ type: 'p', text: 'x' }, ill()])]), [
		{ where: 'guides/g.ts › section 1 block 2', id: 'a', alt: 'A diagram.' },
	]);
});

test('a block naming no file, or with empty alt, fails', () => {
	assert.match(check([ill('a'), ill('missing')]).join('\n'), /"missing" has no illustrations\/missing\.svg/);
	assert.match(check([ill('a', ' ')]).join('\n'), /needs alt text/);
});

test('a file nothing references, or not named <id>.svg, fails', () => {
	assert.match(check([]).join('\n'), /a\.svg: no guide references it/);
	assert.match(check([ill()], [{ name: 'a.svg', source: SVG }, { name: 'Notes.txt', source: '' }]).join('\n'), /only <kebab-case-id>\.svg/);
});

test('a file with text or a foreign colour fails, naming the file', () => {
	const bad = SVG.replace('<circle', '<text>Hi</text><circle').replace('#ff00a1', '#123456');
	const problems = check([ill()], [{ name: 'a.svg', source: bad }]).join('\n');
	assert.match(problems, /illustrations\/a\.svg: <text> is not an allowed element/);
	assert.match(problems, /illustrations\/a\.svg: .*#123456.*outside the token set/);
});

test('the committed illustrations pass', () => {
	const r = spawnSync(process.execPath, [join(REPO_ROOT, 'scripts', 'check_help_illustrations.mjs')], { encoding: 'utf8' });
	assert.equal(r.status, 0, r.stderr);
});
