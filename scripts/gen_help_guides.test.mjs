// Unit tests for scripts/gen_help_guides.mjs — the writer of the phone apps'
// help-guide JSON, whose `--check` mode is the CI step that keeps the twins'
// copy in step with the web guides.
//
// Run: node --test scripts/gen_help_guides.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { join } from 'node:path';

import { GUIDES_DIR, OUTPUTS, REPO_ROOT, loadGuides, renderJson, staleOutputs } from './gen_help_guides.mjs';

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

test('staleOutputs names both twins when the expected JSON differs', async () => {
	const json = renderJson(await loadGuides());
	assert.deepEqual(staleOutputs(json), [], 'the committed twins are stale; run pnpm gen:help-guides');
	assert.deepEqual(staleOutputs(json + ' '), OUTPUTS);
});

test('--check exits 0 on the committed tree', () => {
	const r = spawnSync(process.execPath, [join(REPO_ROOT, 'scripts', 'gen_help_guides.mjs'), '--check'], {
		encoding: 'utf8',
	});
	assert.equal(r.status, 0, r.stderr);
});
