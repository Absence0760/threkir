// Unit tests for scripts/gen_help_guides.mjs — the writer of the per-locale
// help-guide JSON (both phone twins, and the web's fetched translations),
// whose `--check` mode is the CI step that keeps every copy in step with the
// web guides and their translations.
//
// Run: node --test scripts/gen_help_guides.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
	GUIDES_DIR,
	LOCALES,
	OUTPUT_DIRS,
	REPO_ROOT,
	SOURCE_LOCALE,
	TRANSLATED_LOCALES,
	loadGuides,
	loadTranslations,
	renderAll,
	renderJson,
	staleOutputs,
} from './gen_help_guides.mjs';

const guide = (/** @type {Record<string, unknown>} */ over) => ({
	id: 'b',
	title: 'T',
	summary: 'S',
	kind: 'how-to',
	category: 'clubs',
	audience: ['participant'],
	platforms: ['web'],
	routes: [],
	sections: [{ heading: 'H', blocks: [{ type: 'p', text: 'x' }] }],
	related: [],
	...over,
});

test('renderJson sorts by category, then id', () => {
	const out = JSON.parse(
		renderJson([guide({ id: 'b', category: 'races' }), guide({ id: 'z', category: 'clubs' }), guide({ id: 'a', category: 'races' })]),
	);
	assert.deepEqual(
		out.map((/** @type {{ id: string }} */ g) => g.id),
		['z', 'a', 'b'],
	);
});

test('renderJson writes the contract keys in contract order and drops anything else', () => {
	const [out] = JSON.parse(renderJson([{ stray: 1, ...guide({ requires: ['pro'] }) }]));
	assert.deepEqual(Object.keys(out), [
		'id',
		'lang',
		'title',
		'summary',
		'kind',
		'category',
		'audience',
		'requires',
		'platforms',
		'routes',
		'sections',
		'related',
	]);
});

test('renderJson keeps only the block contract keys, in order', () => {
	const [out] = JSON.parse(
		renderJson([guide({ sections: [{ heading: 'H', extra: 1, blocks: [{ text: 'x', debug: true, tone: 'tip', type: 'callout' }] }] })]),
	);
	assert.deepEqual(out.sections, [{ heading: 'H', blocks: [{ type: 'callout', tone: 'tip', text: 'x' }] }]);
});

test('renderJson is byte-stable and newline-terminated', () => {
	const guides = [guide({ id: 'a' }), guide({ id: 'b' })];
	const once = renderJson(guides);
	assert.equal(once, renderJson([...guides].reverse()));
	assert.ok(once.endsWith('}\n]\n'));
});

test('loadGuides loads one guide per guide file, each named after its file', async () => {
	const files = readdirSync(GUIDES_DIR).filter((f) => /^[a-z0-9]+(?:-[a-z0-9]+)*\.ts$/.test(f));
	const guides = await loadGuides();
	assert.equal(guides.length, files.length);
	assert.ok(guides.length > 0, 'no guides loaded, so --check would compare against an empty array');
	assert.deepEqual(guides.map((g) => `${g.id}.ts`).sort(), [...files].sort());
});

const translation = (/** @type {Record<string, unknown>} */ over) => ({
	id: 'b',
	source: '0000000000000000',
	title: 'Tb',
	summary: 'Sb',
	sections: [{ heading: 'Hb', blocks: [{ type: 'p', text: 'xb' }] }],
	...over,
});

test('renderJson lays a locale\'s translation over its guide and marks the language', () => {
	const [out] = JSON.parse(renderJson([guide({})], [{ locale: 'de', translation: translation({}) }], 'de'));
	assert.equal(out.lang, 'de');
	assert.equal(out.title, 'Tb');
	assert.equal(out.summary, 'Sb');
	assert.deepEqual(out.sections, [{ heading: 'Hb', blocks: [{ type: 'p', text: 'xb' }] }]);
	assert.deepEqual(out.platforms, ['web'], 'everything but the words is the English guide\'s');
});

test('renderJson falls back to English per guide: no translation, another locale\'s, or one that does not line up', () => {
	const misaligned = translation({ id: 'c', sections: [{ heading: 'Hc', blocks: [{ type: 'list', items: ['y'] }] }] });
	const out = JSON.parse(
		renderJson(
			[guide({ id: 'a' }), guide({ id: 'b' }), guide({ id: 'c' })],
			[{ locale: 'fr', translation: translation({}) }, { locale: 'de', translation: misaligned }],
			'de',
		),
	);
	assert.deepEqual(
		out.map((/** @type {{ lang: string, title: string }} */ g) => [g.lang, g.title]),
		[
			['en', 'T'],
			['en', 'T'],
			['en', 'T'],
		],
	);
});

test('renderAll writes every locale to both twins and every translated locale to web', () => {
	const all = renderAll([guide({})], []);
	assert.equal(all.size, LOCALES.length * 2 + TRANSLATED_LOCALES.length);
	for (const locale of LOCALES) {
		const name = `guides.${locale}.json`;
		assert.equal(all.get(join(OUTPUT_DIRS.android, name)), all.get(join(OUTPUT_DIRS.ios, name)), `${name}: twins differ`);
		assert.equal(all.has(join(OUTPUT_DIRS.web, name)), locale !== SOURCE_LOCALE);
	}
});

test('staleOutputs names a changed file, a missing one and an orphan', async () => {
	const expected = renderAll(await loadGuides(), await loadTranslations());
	assert.deepEqual(staleOutputs(expected), [], 'the committed JSON is stale; run pnpm gen:help-guides');
	const [first] = expected.keys();
	const changed = new Map(expected);
	changed.set(/** @type {string} */ (first), 'x');
	assert.deepEqual(staleOutputs(changed), [first]);
	const missing = join(mkdtempSync(join(tmpdir(), 'help-guides-')), 'guides.xx.json');
	assert.deepEqual(staleOutputs(new Map([...expected, [missing, '[]\n']])), [missing]);
	const fewer = new Map(expected);
	fewer.delete(/** @type {string} */ (first));
	assert.deepEqual(staleOutputs(fewer), [first], 'a file the generator no longer writes is reported');
});

test('loadTranslations reads every translation file, each exporting `translation`', async () => {
	for (const t of await loadTranslations()) {
		assert.ok(t.translation, `translations/${t.locale}/${t.file} exports no translation`);
	}
});

test('--check exits 0 on the committed tree', () => {
	const r = spawnSync(process.execPath, [join(REPO_ROOT, 'scripts', 'gen_help_guides.mjs'), '--check'], {
		encoding: 'utf8',
	});
	assert.equal(r.status, 0, r.stderr);
});
