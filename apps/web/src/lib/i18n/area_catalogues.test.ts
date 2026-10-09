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
import { AREA_NAMES, AREAS, partsForRoute } from './areas';
import {
	CORE,
	MIN_GROUP_SOURCE_BYTES,
	assignParts,
	deriveGroups,
	englishSourceBytes,
	keyUsage,
	pinnedNamespaces,
	routeIdOf,
	unitOf,
} from './area_scan';

const SRC = resolve('src');
const ROUTES = join(SRC, 'routes');
const KEYS = Object.keys(en);
const { usage, graph, reach } = keyUsage(SRC, KEYS);
const { parts, groups } = deriveGroups(assignParts(KEYS, usage), usage, englishSourceBytes(en));
const rel = (p: string) => relative(SRC, p);

test('every area and group key is rendered only on routes that load its part', () => {
	const violations: string[] = [];
	for (const [key, part] of parts) {
		if (part === CORE) continue;
		for (const use of usage.get(key) ?? []) {
			if (use.routes.size === 0) {
				violations.push(`${key} (${part}) is named by ${rel(use.file)}, which no route reaches`);
				continue;
			}
			for (const routeId of use.routes) {
				if (!partsForRoute(routeId, groups).includes(part)) {
					violations.push(`${key} (${part}) renders on ${routeId} via ${rel(use.file)}`);
				}
			}
		}
	}
	assert.deepEqual(
		violations,
		[],
		'these keys would render as their raw names: the route never loads the ' +
			'catalogue part that holds them',
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

test('keys several areas share are grouped by exactly who renders them, past a size', () => {
	const one = (file: string, ...routes: string[]) => ({ file, routes: new Set(routes) });
	const fixture = new Map([
		['gym.a', [one('a', '/gym'), one('b', '/plans/[id]')]],
		['gym.b', [one('c', '/plans'), one('d', '/gym/[id]')]],
		['gym.small', [one('e', '/gym'), one('f', '/clubs')]],
		['history.a', [one('g', '/history'), one('h', '/gym')]],
		['history.b', [one('g', '/history/x'), one('h', '/gym/[id]')]],
		['sessions.a', [one('i', '/sessions/[id]')]],
		['sessions.b', [one('i', '/sessions')]],
		['global.a', [one('j', '/'), one('k', '/gym')]],
		['global.b', [one('j', '/'), one('k', '/gym')]],
		['orphan.a', [one('l', '/gym'), one('m')]],
		['orphan.b', [one('l', '/gym'), one('m')]],
		['clubRole.owner', [one('n', '/gym'), one('o', '/plans')]],
		['clubRole.admin', [one('n', '/gym'), one('o', '/plans')]],
		['gym.only', [one('p', '/gym')]],
	]);
	const keys = [...fixture.keys()];
	// 600 bytes a key against the 1024 threshold: one key is never a group.
	const bytes = (ks: readonly string[]) =>
		ks.reduce((n, k) => n + (k === 'gym.small' ? 10 : 600), 0);
	const { parts: got, groups: table } = deriveGroups(assignParts(keys, fixture), fixture, bytes);
	assert.deepEqual(Object.fromEntries(got), {
		// /plans/[id]'s narrowest area is planDetail and /plans's is plans, so
		// these are two different sets of one key each: under the threshold.
		'gym.a': CORE,
		'gym.b': CORE,
		'gym.small': CORE,
		// An area with an unregistered segment, and a segment alone, both
		// reach it with two keys.
		'history.a': '_history~gym',
		'history.b': '_history~gym',
		'sessions.a': '_sessions',
		'sessions.b': '_sessions',
		// The root's layout renders everywhere, an orphan's reader is unknown,
		// and a pinned namespace is core whatever its size.
		'global.b': CORE,
		'orphan.b': CORE,
		'clubRole.admin': CORE,
		'global.a': CORE,
		'orphan.a': CORE,
		'clubRole.owner': CORE,
		'gym.only': 'gym',
	});
	assert.deepEqual(table, { '_history~gym': ['/gym', '/history'], _sessions: ['/sessions'] });
	assert.deepEqual(partsForRoute('/gym/[id]', table), ['gym', '_history~gym']);
	assert.deepEqual(partsForRoute('/history', table), ['_history~gym']);
	assert.deepEqual(partsForRoute('/sessions/[id]', table), ['_sessions']);
	assert.deepEqual(partsForRoute('/clubs', table), ['clubs']);
});

test('every derived group earns its part and names real route directories', () => {
	assert.ok(Object.keys(groups).length > 0, 'no group derived — the scan or the threshold is off');
	const source = englishSourceBytes(en);
	for (const [name, prefixes] of Object.entries(groups)) {
		const keys = [...parts].filter(([, p]) => p === name).map(([k]) => k);
		assert.ok(
			source(keys) >= MIN_GROUP_SOURCE_BYTES,
			`${name} holds ${source(keys)} bytes, under MIN_GROUP_SOURCE_BYTES`,
		);
		for (const prefix of prefixes) {
			assert.ok(existsSync(join(ROUTES, prefix)), `${name}: ${prefix} is not a route directory`);
		}
		// A group is loaded by its own units' routes and nothing else: the
		// root (unit null) would make it every reader's, which is core.
		for (const key of keys) {
			for (const use of usage.get(key) ?? []) {
				for (const routeId of use.routes) assert.notEqual(unitOf(routeId), null, `${key} renders on /`);
			}
		}
	}
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
	const body = /export async function loadRouteCatalogues\([\s\S]*?\n\}/.exec(store)?.[0] ?? '';
	assert.match(body, /const parts = partsForRoute\(routeId, GROUPS\);/);
	assert.match(
		body,
		/if \(await catalogues\.open\(next, parts\)\)/,
		'the first load must open the reader locale WITH the parts, before anything renders (§ 1812)',
	);
	assert.match(body, /await catalogues\.ensureAreas\(parts\);\n\}$/, 'every path must end by loading the parts');
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
