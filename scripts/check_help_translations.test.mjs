// Unit tests for scripts/check_help_translations.mjs — the guard that fails CI
// when an English help guide changes under a translation recorded against
// its older text.
//
// Run: node --test scripts/check_help_translations.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

import { ONLY_IMPORT, sourceHash, translationProblems } from './check_help_translations.mjs';
import { REPO_ROOT } from './gen_help_guides.mjs';

const guide = (/** @type {Record<string, unknown>} */ over = {}) => ({
	id: 'g',
	title: 'Title',
	summary: 'Summary.',
	kind: 'how-to',
	category: 'clubs',
	audience: ['runner'],
	platforms: ['web'],
	sections: [
		{
			heading: 'One',
			blocks: [
				{ type: 'p', text: 'Press **Save**.' },
				{ type: 'steps', items: ['a', 'b'] },
				{ type: 'note', tone: 'tip', text: 'n' },
			],
		},
	],
	...over,
});

const translation = (/** @type {Record<string, unknown>} */ over = {}) => ({
	id: 'g',
	source: sourceHash(guide()),
	title: 'Titel',
	summary: 'Zusammenfassung.',
	sections: [
		{
			heading: 'Eins',
			blocks: [
				{ type: 'p', text: 'Tippe auf **Speichern**.' },
				{ type: 'steps', items: ['A', 'B'] },
				{ type: 'note', tone: 'tip', text: 'N' },
			],
		},
	],
	...over,
});

const file = (/** @type {Record<string, unknown>} */ t, extra = {}) => ({
	locale: 'de',
	file: 'g.ts',
	translation: t,
	text: `${ONLY_IMPORT}\n\nexport const translation = {};\n`,
	...extra,
});

const check = (/** @type {object[]} */ translations, extra = {}) =>
	translationProblems({ guides: [guide()], translations: /** @type {any} */ (translations), locales: ['de', 'fr'], ...extra });

test('a current translation passes', () => {
	assert.deepEqual(check([file(translation())]), []);
});

test('sourceHash is 16 hex digits and moves with any word of the English', () => {
	const base = sourceHash(guide());
	assert.match(base, /^[0-9a-f]{16}$/);
	assert.equal(sourceHash(guide()), base, 'deterministic');
	assert.notEqual(sourceHash(guide({ title: 'Title!' })), base);
	assert.notEqual(sourceHash(guide({ summary: 'Other.' })), base);
	const edited = guide();
	/** @type {any} */ (edited.sections)[0].blocks[1].items[1] = 'c';
	assert.notEqual(sourceHash(edited), base, 'a step item is translated text');
});

test('sourceHash ignores what a translation does not carry', () => {
	const base = sourceHash(guide());
	assert.equal(sourceHash(guide({ platforms: ['web', 'android'], routes: ['/clubs'], related: ['x'], audience: ['everyone'] })), base);
	const extraKey = guide();
	/** @type {any} */ (extraKey.sections)[0].blocks[0].debug = true;
	assert.equal(sourceHash(extraKey), base);
});

test('a translation recorded against older English is stale, naming the new hash and both ways out', () => {
	const [problem, ...rest] = check([file(translation({ source: '0123456789abcdef' }))]);
	assert.equal(rest.length, 0);
	assert.match(problem ?? '', /^translations\/de\/g\.ts: stale/);
	assert.ok(problem?.includes(sourceHash(guide())), 'names the current hash');
	assert.match(problem ?? '', /delete this file/);
});

test('a missing or malformed source hash fails', () => {
	assert.equal(check([file(translation({ source: undefined }))]).length, 1);
	assert.equal(check([file(translation({ source: 'ABC' }))]).length, 1);
});

test('a translation must line up with its guide section by section and block by block', () => {
	const t = translation();
	/** @type {any} */ (t.sections)[0].blocks[1].items.push('C');
	assert.match(check([file(t)]).join('\n'), /section 1 block 2: 3 items, the guide has 2/);

	const tone = translation();
	/** @type {any} */ (tone.sections)[0].blocks[2].tone = 'caution';
	assert.match(check([file(tone)]).join('\n'), /a caution note, the guide has a tip note/);

	assert.match(check([file(translation({ sections: [] }))]).join('\n'), /0 sections, the guide has 1/);
});

test('a translation of no guide, a mismatched id, or a missing export fails', () => {
	assert.match(check([file(translation({ id: 'nope' }), { file: 'nope.ts' })]).join('\n'), /no English guide "nope"/);
	assert.match(check([file(translation({ id: 'other' }))]).join('\n'), /id "other" does not match the file name/);
	assert.match(check([file(undefined)]).join('\n'), /does not export `translation`/);
	assert.match(check([file(translation(), { file: 'G_1.ts' })]).join('\n'), /translation files are <guide-id>\.ts/);
});

test('a translation file imports nothing but its type', () => {
	const runtime = `${ONLY_IMPORT}\nimport { x } from '../../markup';\n`;
	assert.match(check([file(translation(), { text: runtime })]).join('\n'), /the only import allowed/);
});

test('a directory that is not a translated locale fails', () => {
	assert.deepEqual(check([], { dirs: ['de', 'en', 'xx'] }), [
		'translations/en/: not a translated locale (de, fr)',
		'translations/xx/: not a translated locale (de, fr)',
	]);
});

test('the committed translations pass, and --hash prints a guide\'s hash', () => {
	const script = join(REPO_ROOT, 'scripts', 'check_help_translations.mjs');
	const r = spawnSync(process.execPath, [script], { encoding: 'utf8' });
	assert.equal(r.status, 0, r.stderr);
	const h = spawnSync(process.execPath, [script, '--hash', 'using-help'], { encoding: 'utf8' });
	assert.equal(h.status, 0, h.stderr);
	assert.match(h.stdout.trim(), /^[0-9a-f]{16}$/);
	const missing = spawnSync(process.execPath, [script, '--hash', 'no-such-guide'], { encoding: 'utf8' });
	assert.equal(missing.status, 1);
});
