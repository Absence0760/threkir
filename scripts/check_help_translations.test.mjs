// Unit tests for scripts/check_help_translations.mjs — the guard that fails CI
// when an English help-guide string changes under a translation recorded
// against its older text, naming each changed string.
//
// Run: node --test scripts/check_help_translations.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

import { ONLY_IMPORT, sourceHashes, stringHash, translationProblems } from './check_help_translations.mjs';
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
	sources: sourceHashes(guide()),
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

test('sourceHashes keys every translated string by its path, each a 16-hex-digit hash of that string alone', () => {
	const hashes = sourceHashes(guide());
	assert.deepEqual(Object.keys(hashes), ['title', 'summary', 's0.heading', 's0.b0', 's0.b1.i0', 's0.b1.i1', 's0.b2']);
	for (const h of Object.values(hashes)) assert.match(h, /^[0-9a-f]{16}$/);
	assert.equal(hashes['s0.b0'], stringHash('Press **Save**.'));
	assert.deepEqual(sourceHashes(guide()), hashes, 'deterministic');
	const edited = guide();
	/** @type {any} */ (edited.sections)[0].blocks[1].items[1] = 'c';
	const after = sourceHashes(edited);
	assert.notEqual(after['s0.b1.i1'], hashes['s0.b1.i1']);
	assert.deepEqual(
		Object.keys(after).filter((k) => after[k] !== hashes[k]),
		['s0.b1.i1'],
		'an edit moves only the edited string\'s hash',
	);
});

test('sourceHashes ignores what a translation does not carry', () => {
	const base = sourceHashes(guide());
	assert.deepEqual(sourceHashes(guide({ platforms: ['web', 'android'], routes: ['/clubs'], related: ['x'], audience: ['everyone'] })), base);
	const extraKey = guide();
	/** @type {any} */ (extraKey.sections)[0].blocks[0].debug = true;
	assert.deepEqual(sourceHashes(extraKey), base);
});

test('an English edit stales only the strings it touched, each named with where it is and what the English now says', () => {
	const edited = guide();
	/** @type {any} */ (edited.sections)[0].blocks[0].text = 'Press **Save** twice.';
	/** @type {any} */ (edited.sections)[0].blocks[1].items[0] = 'z';
	const problems = translationProblems({ guides: [edited], translations: /** @type {any} */ ([file(translation())]), locales: ['de'] });
	assert.equal(problems.length, 2);
	assert.match(problems[0] ?? '', /^translations\/de\/g\.ts › s0\.b0 \(section 1 block 1\): stale/);
	assert.ok(problems[0]?.includes('Press **Save** twice.'), 'quotes the English as it now reads');
	assert.ok(problems[0]?.includes(stringHash('Press **Save** twice.')), 'names the new hash');
	assert.match(problems[1] ?? '', /› s0\.b1\.i0 \(section 1 block 2 item 1\): stale/);
});

test('a missing, malformed or surplus source hash fails', () => {
	assert.match(check([file(translation({ sources: undefined }))]).join('\n'), /`sources` must map/);
	const { title: _t, ...noTitle } = sourceHashes(guide());
	assert.match(check([file(translation({ sources: noTitle }))]).join('\n'), /› title \(title\): no 16-hex-digit source hash/);
	assert.match(check([file(translation({ sources: { ...sourceHashes(guide()), summary: 'ABC' } }))]).join('\n'), /› summary/);
	assert.match(
		check([file(translation({ sources: { ...sourceHashes(guide()), 's9.b0': stringHash('x') } }))]).join('\n'),
		/`sources` names s9\.b0, which the guide does not have/,
	);
});

test('a translation that does not line up reports the shape, not a hash per string', () => {
	const t = translation();
	/** @type {any} */ (t.sections)[0].blocks.pop();
	assert.deepEqual(check([file(t)]), ['translations/de/g.ts: section 1: 2 blocks, the guide has 3']);
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

test('the committed translations pass, and --hash prints a guide\'s sources map or one string\'s hash', () => {
	const script = join(REPO_ROOT, 'scripts', 'check_help_translations.mjs');
	const r = spawnSync(process.execPath, [script], { encoding: 'utf8' });
	assert.equal(r.status, 0, r.stderr);
	const h = spawnSync(process.execPath, [script, '--hash', 'using-help'], { encoding: 'utf8' });
	assert.equal(h.status, 0, h.stderr);
	const map = JSON.parse(h.stdout);
	assert.match(map.title, /^[0-9a-f]{16}$/);
	const one = spawnSync(process.execPath, [script, '--hash', 'using-help', 'summary'], { encoding: 'utf8' });
	assert.equal(one.stdout.trim(), map.summary);
	assert.equal(spawnSync(process.execPath, [script, '--hash', 'using-help', 's99.b0'], { encoding: 'utf8' }).status, 1);
	assert.equal(spawnSync(process.execPath, [script, '--hash', 'no-such-guide'], { encoding: 'utf8' }).status, 1);
});
