// The area split (decisions § 1802) against the real tree. Invocation:
//   npx tsx --test src/lib/i18n/area_catalogues.test.ts
//
// `m()` is synchronous, and an area catalogue only exists in the dict once
// the root layout's `load` has fetched it for a route that needs it. So the
// one way the split can show a reader a raw key name is a key living in an
// area catalogue while some route that does NOT load that area renders it.
// The Vite plugin derives every key's part from the same scan these tests
// run, so the split is sound by construction as long as (a) the scan sees
// every reader of every key, (b) the runtime loads what the scan assumed,
// and (c) nothing reads a message before that load resolves. Each test pins
// one of those.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

import { en } from './locales/en';
import { AREA_NAMES, AREAS, areasForRoute } from './areas';
import { CORE, assignParts, keyUsage, pinnedNamespaces, routeIdOf } from './area_scan';

const SRC = resolve('src');
const ROUTES = join(SRC, 'routes');
const KEYS = Object.keys(en);
const { usage, graph, reach } = keyUsage(SRC, KEYS);
const parts = assignParts(KEYS, usage);
const rel = (p: string) => relative(SRC, p);

test('every area key is rendered only on routes that load its area', () => {
	const violations: string[] = [];
	for (const [key, part] of parts) {
		if (part === CORE) continue;
		for (const use of usage.get(key) ?? []) {
			if (use.routes.size === 0) {
				violations.push(`${key} (${part}) is named by ${rel(use.file)}, which no route reaches`);
				continue;
			}
			for (const routeId of use.routes) {
				if (!areasForRoute(routeId).includes(part)) {
					violations.push(`${key} (${part}) renders on ${routeId} via ${rel(use.file)}`);
				}
			}
		}
	}
	assert.deepEqual(
		violations,
		[],
		'these keys would render as their raw names: the route never loads the area ' +
			'catalogue that holds them',
	);
});

test('a key shared by two areas, or named nowhere, ships in core', () => {
	const one = (file: string, ...routes: string[]) => ({ file, routes: new Set(routes) });
	const fixture = new Map([
		['gym.only', [one('a', '/gym'), one('b', '/gym/[id]')]],
		['gym.shared', [one('a', '/gym'), one('c', '/history')]],
		['gym.orphan', [one('d')]],
		['gym.layout', [one('e', '/')]],
		['settings.deep', [one('f', '/settings/account')]],
		['settings.shallow', [one('g', '/settings/account'), one('h', '/settings/gear')]],
		['clubRole.owner', [one('i', '/clubs')]],
	]);
	const got = assignParts([...fixture.keys(), 'unused.key'], fixture);
	assert.deepEqual(Object.fromEntries(got), {
		'gym.only': 'gym',
		'gym.shared': CORE,
		'gym.orphan': CORE,
		'gym.layout': CORE,
		'settings.deep': 'settingsAccount',
		'settings.shallow': 'settings',
		'clubRole.owner': CORE,
		'unused.key': CORE,
	});
});

test('the namespaces only a fully dynamic builder names are pinned to core', () => {
	// `enum_labels.ts` builds `${vocab}.${value}`: no literal names those keys,
	// so the scan cannot see who renders them. If a second builder of that
	// shape appears, its namespaces need the same treatment, so find them all.
	const builders: string[] = [];
	for (const file of graph.keys()) {
		if (file.includes(join('i18n', 'locales'))) continue;
		const text = readFileSync(file, 'utf8');
		if (/`\$\{[^}]+\}\.\$\{[^}]+\}`\s*as\s+MessageKey/.test(text)) builders.push(rel(file));
	}
	assert.deepEqual(builders, [join('lib', 'i18n', 'enum_labels.ts')]);
	for (const ns of pinnedNamespaces()) {
		const keys = KEYS.filter((k) => k.startsWith(ns));
		assert.ok(keys.length > 0, `pinned namespace ${ns} names no key`);
		for (const k of keys) assert.equal(parts.get(k), CORE, `${k} must ship in core`);
	}
});

test('the root layout loads the route catalogues in its load', () => {
	const source = readFileSync(join(ROUTES, '+layout.ts'), 'utf8');
	assert.match(
		source,
		/export const load[\s\S]*\(\{\s*route\s*\}\)[\s\S]*await loadRouteCatalogues\(route\.id\)/,
		'the root +layout.ts load must await loadRouteCatalogues(route.id); without it ' +
			'no area catalogue is ever fetched and every area key renders as its name',
	);
	const store = readFileSync(join(SRC, 'lib', 'i18n', 'store.svelte.ts'), 'utf8');
	assert.match(store, /ensureAreas\(areasForRoute\(routeId\)\)/);
});

test('no other load function can read a message before the catalogues arrive', () => {
	// SvelteKit runs a route's load functions in parallel, so a page or nested
	// layout load calling m() would race the root one. Components render after
	// every load resolves, which is why they are safe and these are not.
	const store = join(SRC, 'lib', 'i18n', 'store.svelte.ts');
	const offenders: string[] = [];
	for (const entry of graph.keys()) {
		const name = entry.slice(entry.lastIndexOf('/') + 1);
		if (!/^\+(page|layout)(\.server)?\.(ts|js)$/.test(name)) continue;
		if (entry === join(ROUTES, '+layout.ts')) continue;
		const stack = [entry];
		const seen = new Set<string>();
		while (stack.length) {
			const file = stack.pop()!;
			if (seen.has(file)) continue;
			seen.add(file);
			if (file === store) {
				offenders.push(rel(entry));
				break;
			}
			for (const next of graph.get(file) ?? []) if (!next.endsWith('.svelte')) stack.push(next);
		}
	}
	assert.deepEqual(offenders, [], 'these load modules reach i18n/store.svelte.ts');
});

test('every area names a real route and ships at least one key', () => {
	for (const area of AREA_NAMES) {
		for (const prefix of AREAS[area]) {
			assert.ok(existsSync(join(ROUTES, prefix)), `${area}: ${prefix} is not a route directory`);
		}
		const count = [...parts.values()].filter((p) => p === area).length;
		assert.ok(
			count > 0,
			`${area} receives no keys — every key under ${AREAS[area].join(', ')} is shared ` +
				'with another area. Delete the entry; an empty part is a round trip for nothing.',
		);
	}
});

test('app code never imports a whole catalogue', () => {
	// The runtime loads parts; a whole catalogue in the client graph is every
	// sentence of a language for every reader. `badges.ts` keeps one import of
	// English for the share Lambda's `englishBadge`, which the client tree-shakes
	// away — the bundle budget's catalogue-leak check is what proves that holds.
	const ALLOWED = new Set([
		join('lib', 'social', 'badges.ts'),
		join('lib', 'i18n', 'messages.ts'),
		join('lib', 'i18n', 'catalogues.ts'),
	]);
	const offenders: string[] = [];
	for (const [file, edges] of graph) {
		if (ALLOWED.has(rel(file)) || file.includes(join('i18n', 'locales'))) continue;
		for (const target of edges) {
			const r = rel(target);
			if (r === join('lib', 'i18n', 'catalogues.ts') || r.startsWith(join('lib', 'i18n', 'locales'))) {
				offenders.push(`${rel(file)} -> ${r}`);
			}
		}
	}
	assert.deepEqual(offenders, []);
});

test('the scan reaches the route entries it is reasoning about', () => {
	// A scan that silently resolved nothing would assign every key to core and
	// pass every test above. Pin a few edges the tree is known to have.
	const page = join(ROUTES, 'gym', '+page.svelte');
	assert.equal(routeIdOf(ROUTES, page), '/gym');
	assert.ok(reach.get(page)?.has('/gym'));
	const layout = join(SRC, 'lib', 'i18n', 'store.svelte.ts');
	assert.ok(reach.get(layout)?.has('/'), 'the root layout must reach the i18n store');
	const areaKeys = [...parts.values()].filter((p) => p !== CORE).length;
	assert.ok(
		areaKeys > KEYS.length / 2,
		`only ${areaKeys} of ${KEYS.length} keys landed in an area — the scan is likely blind`,
	);
});
