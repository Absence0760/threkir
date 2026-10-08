// The scanner the area split is derived from (decisions § 1802), on fixtures.
// Invocation: npx tsx --test src/lib/i18n/area_scan.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

import { areasForRoute, routeUnder } from './areas';
import { englishSourceBytes, keyUsage, keysNamedIn, routeIdOf, unitOf, unitPrefixes } from './area_scan';

const KEYS = [
	'gym.title',
	'gym.slot_am',
	'gym.slot_pm',
	'nutrition.source_manual',
	'nutrition.source_scan',
	'settingsIntegrations.stravaLookback30',
	'common.cancel',
];
const named = (text: string) => [...keysNamedIn(text, KEYS, new Set(KEYS))].sort();

test('a literal equal to a key names it, in any quote style', () => {
	assert.deepEqual(named(`m('gym.title'); m("common.cancel")`), ['common.cancel', 'gym.title']);
	assert.deepEqual(named('const k = `gym.title`;'), ['gym.title']);
});

test('a template literal names every key its static head starts', () => {
	assert.deepEqual(named('m(`gym.slot_${slot}`)'), ['gym.slot_am', 'gym.slot_pm']);
	assert.deepEqual(named('m(`settingsIntegrations.stravaLookback${days}` as MessageKey)'), [
		'settingsIntegrations.stravaLookback30',
	]);
});

test('a dotted or underscored prefix glued on with + names its whole family', () => {
	assert.deepEqual(named(`m(('nutrition.source_' + s) as MessageKey)`), [
		'nutrition.source_manual',
		'nutrition.source_scan',
	]);
});

test('a template with no static head, or an unrelated string, names nothing', () => {
	assert.deepEqual(named('`${vocab}.${value}`'), []);
	assert.deepEqual(named(`'gym' + 'title'; "gymnastics"; 'gym.titles'`), []);
});

test('routeIdOf maps page, layout and error entries to their route id', () => {
	const routes = '/app/src/routes';
	assert.equal(routeIdOf(routes, '/app/src/routes/+page.svelte'), '/');
	assert.equal(routeIdOf(routes, '/app/src/routes/gym/[id]/+page.svelte'), '/gym/[id]');
	assert.equal(routeIdOf(routes, '/app/src/routes/settings/+layout.svelte'), '/settings');
	assert.equal(routeIdOf(routes, '/app/src/routes/plans/+page.ts'), '/plans');
	assert.equal(routeIdOf(routes, '/app/src/routes/+error.svelte'), '/');
	assert.equal(routeIdOf(routes, '/app/src/routes/api/coach/+server.ts'), null);
	assert.equal(routeIdOf(routes, '/app/src/routes/gym/helpers.ts'), null);
});

test('areasForRoute matches by whole segments, nested areas included', () => {
	assert.equal(routeUnder('/routes/new', '/routes'), true);
	assert.equal(routeUnder('/routesheatmap', '/routes'), false);
	assert.deepEqual(areasForRoute('/gym/[id]'), ['gym']);
	assert.deepEqual(areasForRoute('/settings/account'), ['settings', 'settingsAccount']);
	assert.deepEqual(areasForRoute('/'), []);
	assert.deepEqual(areasForRoute(null), []);
	assert.deepEqual(areasForRoute('/history'), []);
});

test('a route groups under its narrowest area, else its top-level segment, never the root', () => {
	assert.equal(unitOf('/settings/account/delete'), 'settingsAccount');
	assert.equal(unitOf('/settings'), 'settings');
	assert.equal(unitOf('/history'), '_history');
	assert.equal(unitOf('/sessions/[id]'), '_sessions');
	assert.equal(unitOf('/'), null, 'the root layout renders on every route');
	assert.deepEqual(unitPrefixes('_sessions'), ['/sessions']);
	assert.deepEqual(unitPrefixes('settingsAccount'), ['/settings/account']);
	assert.throws(() => unitPrefixes('noSuchArea'));
});

test('englishSourceBytes measures the keys it is given, as JSON', () => {
	const bytes = englishSourceBytes({ 'a.b': 'x', 'c.d': 'ü' });
	assert.equal(bytes(['a.b']), Buffer.byteLength('{"a.b":"x"}'));
	assert.equal(bytes(['a.b', 'c.d', 'missing.key']), Buffer.byteLength('{"a.b":"x","c.d":"ü"}'));
});

test('keyUsage follows $lib, relative, extensionless, dynamic and re-export imports', () => {
	const root = mkdtempSync(join(tmpdir(), 'area-scan-'));
	try {
		const src = join(root, 'src');
		const put = (path: string, text: string) => {
			mkdirSync(dirname(join(src, path)), { recursive: true });
			writeFileSync(join(src, path), text);
		};
		put('routes/+layout.svelte', `<script>import Shell from '$lib/components/Shell.svelte';</script>`);
		put('lib/components/Shell.svelte', `<script>m('common.cancel');</script>`);
		put('routes/gym/+page.svelte', `<script>import { label } from './helpers';</script>`);
		put('routes/gym/helpers.ts', `export { slots } from '$lib/gym/index'; export const label = 'gym.title';`);
		put('lib/gym/index.ts', 'export const slots = (s: string) => `gym.slot_${s}`;');
		// Spelled in two halves so unit_suite_resolvable_imports.test.ts does not
		// read the fixture as this suite importing through an alias.
		put('routes/nutrition/+page.svelte', '<script>const Lazy = import' + "('$lib/components/Nutri.svelte');</script>");
		put('lib/components/Nutri.svelte', `<script>m(('nutrition.source_' + s));</script>`);
		put('lib/Dead.svelte', `<script>m('settingsIntegrations.stravaLookback30');</script>`);
		put('lib/i18n/locales/en.ts', `export const en = { 'gym.title': 'Gym' };`);
		put('lib/thing.test.ts', `m('common.cancel')`);

		const { usage } = keyUsage(src, KEYS);
		const routesOf = (key: string) =>
			[...new Set((usage.get(key) ?? []).flatMap((u) => [...u.routes]))].sort();
		assert.deepEqual(routesOf('common.cancel'), ['/'], 'layouts reach their components; tests are not readers');
		assert.deepEqual(routesOf('gym.title'), ['/gym'], 'the catalogue itself is not a reader');
		assert.deepEqual(routesOf('gym.slot_am'), ['/gym'], 'reached through a re-export');
		assert.deepEqual(routesOf('nutrition.source_scan'), ['/nutrition'], 'reached through import()');
		assert.equal(usage.get('settingsIntegrations.stravaLookback30')?.[0].routes.size, 0, 'an orphan has no route');
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});
